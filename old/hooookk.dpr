library hooookk;

{ DLL でのメモリ管理について:
  もしこの DLL が引数や返り値として String 型を使う関数/手続きをエクスポー
  トする場合、以下の USES 節とこの DLL を使うプロジェクトソースの USES 節
  の両方に、最初に現れるユニットとして ShareMem を指定しなければなりません。
  （プロジェクトソースはメニューから[プロジェクト｜ソース表示] を選ぶこと
  で表示されます）
  これは構造体やクラスに埋め込まれている場合も含め String 型を DLL とやり
  取りする場合に必ず必要となります。
  ShareMem は共用メモリマネージャである BORLNDMM.DLL とのインターフェース
  です。あなたの DLL と一緒に配布する必要があります。BORLNDMM.DLL を使うの
  を避けるには、PChar または ShortString 型を使って文字列のやり取りをおこ
  なってください。}


uses
  SysUtils, MMsystem,   Windows, Messages,
  Classes,Dialogs;

  //dialogはデバッグ時に使うのみ。
  //showmessageが残ってると大変な事になるので、
  //デバッグ終了時にはなるべく消しておいた方が良い？かも。

{$R *.res}

//-----------------------------------------------------------------------------
//宣言
//-----------------------------------------------------------------------------
const
    //通知メッセージ作成用・共有メモリファイル名
    uniqueName = 'chaaattteeerrr';


    //SDKから拾ってきた値
    WH_KEYBOARD_LL = 13;
    LLKHF_UP = $FFFFFF80;     //(DWORD 0x8000 >> 8)

type
    //キー情報
    TKeyInfo = record
        prevDownTime:Cardinal;       //前回DOWN時刻
        prevUpTime:Cardinal;         //前回UP時刻
        //prevSwitchTime:integer;   未使用

        prevChattering:boolean;     //チャタったフラグ
        nextUpDisableFlg:integer;     //次を捨てるフラグ(0:判定する,1:とにかく有効,2:とにかく捨てる)
        nextDownDisableFlg:integer;     //次を捨てるフラグ(0:判定する,1:とにかく有効,2:とにかく捨てる)
        whileRepeat:boolean;        //現在リピート中かどうか？

    end;
    PKeyInfo = ^TKeyInfo;


    //フック関連情報構造体　MMF(メモリマップドファイル)に保存
    THookInfo = record
        Keyhook:HHOOK;      //Hookハンドル
        HostWnd:hWnd;       //通知先を保存
        hookMsg:Cardinal;   //フックからの通知を判定するメッセージ
        //こっからチャタ関係（名前はキニシナイ）
        chaterThreshold:integer;    //閾値 [down]-up-[down]
        repeatThreshold:integer;    //閾値 [down]-[down] ※0推奨
        upDownThreshold:integer;    //閾値 [down]-[up]
        ignoreKeyRepert:boolean;    //リピート無視
        ignoreTenKey:boolean;       //テンキー無視
        accuracy:boolean;           //高精度タイマー
        chatteringCancel:boolean;   //チャタリングキャンセル（一番重要）
        keyUpchatter:boolean;       //UP監視（UP時に余計なDOWNが入る場合に使用。DOWN直後のUPは蛇足、しかもバグってた。）

        prevDownKey:cardinal;   //前回押下キー
        prevKeyDownTime:cardinal;   //前回押下時刻（どのキーでもいいので最新の時刻）
        //prevUpKey:integer;    //前回upキー
        keyInformation : array[0..255] of PKeyInfo; // #$FFって書いたらコンパイルエラーになったので255を直書き
    end;
    PHookInfo = ^THookInfo;




    //WH_KEYBOARD_LL用の構造体(windows.pasに無いのでSDKから)
    PKBDLLHOOKSTRUCT  =  ^TKBDLLHOOKSTRUCT;
    TKBDLLHOOKSTRUCT   =  packed record
        vkCode:         DWORD;
        scanCode:       DWORD;
        flags:          DWORD;
        time:           DWORD;
        dwExtraInfo:    Pointer;
    end;

var //こいつらの実態は一体メモリのどこに？呼び出しアプリ中？
    whileHooking : boolean;     //フック中フラグ
    hFileMapObj  : THandle;     //MMFのハンドル


//-----------------------------------------------------------------------------
//実現部
//-----------------------------------------------------------------------------
//共有メモリを用意
function GetFMObj(var h:THandle; var p:pointer):integer;
begin
  //MMFを開く
  h := OpenFileMapping(FILE_MAP_ALL_ACCESS, False, uniqueName);
  if h = 0 then begin
    result := -1;
    Exit;
  end;

  //MMFの割り当て
  p := MapViewOfFile(h, FILE_MAP_ALL_ACCESS, 0, 0, 0);
  if p = nil then begin
    result := -2;
    CloseHandle(h);
    Exit;
  end;
  Result := 0;
end;

//-----------------------------------------------------------------------------
//共有メモリを削除
procedure ReleaseFMObj(h:THandle; p:Pointer);
begin
  if p <> NIL then    //MMFのビューを解除
    UnmapViewOfFile(p);
  if h <> 0 then      //MMFのハンドルを閉じる
    CloseHandle(h);
end;

//-----------------------------------------------------------------------------
function isTenKey(key:integer):boolean;
begin
    case key of   //Virtual Key Code
		VK_NUMPAD0    :       Result := true;
		VK_NUMPAD1    :       Result := true;
		VK_NUMPAD2    :       Result := true;
		VK_NUMPAD3    :       Result := true;
		VK_NUMPAD4    :       Result := true;
		VK_NUMPAD5    :       Result := true;
		VK_NUMPAD6    :       Result := true;
		VK_NUMPAD7    :       Result := true;
		VK_NUMPAD8    :       Result := true;
		VK_NUMPAD9    :       Result := true;
		VK_MULTIPLY   :       Result := true;
		VK_ADD        :       Result := true;
		//VK_SEPARATOR  :       Result := 'SEPARATOR';
		VK_SUBTRACT   :       Result := true;
		VK_DECIMAL    :       Result := true;
		VK_DIVIDE     :       Result := true;
    else
        Result := false;
    end;
end;

//-----------------------------------------------------------------------------

//MS-IMEの確定アンドゥ（Ctrl+BS)の時に、BSが連続して送出されるので、キャンセルしないように対応。
//Ctrl押下中のBSチャタよりも、確定アンドゥ出来ない方が困る。
//右クリックメニューの再変換やは問題ない。
//ATOKの確定アンドゥは大丈夫っぽい。でもIMEの種類判定は行わない。
function undo_kakutei(p:Pointer; key:integer; ms:Cardinal):boolean;
begin
    Result := false;
    if key <> VK_BACK then exit;                            //BackSpaceが押された時に、

    with pHookInfo(p)^.keyInformation[VK_BACK]^ do          //BackSpaceが、
    if (nextDownDisableFlg = 1) and                         //次回は有効にする指定かつ
       ( (ms-prevDownTime) < pHookInfo(p)^.chaterThreshold) then begin    //チャタ閾値未満で押下かれた場合
        Result := true;                                     //確定アンドゥ中とみなす
        exit;
    end;

    with pHookInfo(p)^.keyInformation[VK_LCONTROL]^  do     //左コントロールが
    if prevDownTime = 0 then                                //押されたことがあって
        exit                                                //かつ
    else if prevUpTime <= prevDownTime then begin           //まだ離してない場合。
        Result := true;                                     //確定アンドゥ中
        exit;
    end;


    with pHookInfo(p)^.keyInformation[VK_RCONTROL]^  do     //右コントロールが、
    if prevDownTime = 0 then                                //押されたことがあって
        exit                                                //かつ
    else if prevUpTime <= prevDownTime then begin           //まだ離してない場合。
        Result := true;                                     //確定アンドゥ中
        exit;
    end;


end;

//-----------------------------------------------------------------------------
//フック本体
function hookProc(nCode:Integer;wParam:WPARAM;
                            lParam:LPARAM):LRESULT;stdcall;
var
    _hFMObject: THandle;
    p         : Pointer;
    RS        : integer;


    pKbdLL:PKBDLLHOOKSTRUCT;

    ms:Cardinal;
    wkMs,wkMs2:Cardinal;
    flgMaje:boolean; //チャタフラグ
    LP,WP:Cardinal;
    vc,sc :DWORD;//
    downFlg:boolean;
    qpc,qpf:int64;

begin
    //共有メモリからフック情報取得
    RS := GetFMObj(_hFMObject, p);
    if RS <> 0 then begin
        //*** RSによってエラーハンドリングする場合はここに記述 ***
        exit;
    end;


    //フック処理
    if nCode < 0 then begin
        Result := CallNextHookEx(pHookInfo(p)^.Keyhook, nCode, wParam, lParam);
    end else begin

        //LParamにKBDLLHOOKSTRUCTが入ってきます。
        pKbdLL := PKBDLLHOOKSTRUCT(LParam);

        downFlg := ( (pKbdLL.flags and LLKHF_UP) = 0 ) ;
        vc := pKbdLL.vkCode;

        //VK(255)は無視。メニューループを抜けるため(?)に一部ソフトが発生させるダミーイベントらしい。
        if (vc < 0) or ( 255 <= vc ) then begin
            Result := CallNextHookEx(pHookInfo(p)^.Keyhook, nCode, wParam, lParam);
        end else begin

            sc := pKbdLL.scanCode;
            //ShowMessage(inttostr(sc) + ' / ' + inttostr(pkbdll.flags));
            if pHookInfo(p)^.accuracy then begin
                ////現在時刻取得
                QueryPerformanceCounter(qpc);
                QueryPerformanceFrequency(qpf);
                ms := trunc( (qpc/qpf)*1000 );
            end else
                ms := trunc(pKbdLL.time{*10000}); //0msになることがあるので桁精度上げてみる→無駄でした。


            //初期化
            LP := 0;            //post情報
            flgMaje := false;   //チャタフラグ


            with pHookInfo(p)^ do
            //####################################################################################################################
            //DOWN時の処理
            if downFlg then begin
                //LPは初期値ママ。DOWNの場合は31ビットは0

                //[DOWN]-[DOWN] キーを押す時に起きるチャタの判定
                //前回DOWNからの時間
                if keyInformation[vc]^.prevDownTime = 0 then begin
                    wkMs :=0;    //初回押下時
                end else begin
                    wkMs := ms - keyInformation[vc]^.prevDownTime;
                end;
                //チャタリング判定
                if ( wkMs < chaterThreshold) and    //経過時間が指定ミリ秒未満
                                                    //  ギリギリはチャタじゃない判定だが、
                                                    //  パフォーマンスカウンタ使用時以外は
                                                    //  「＜」でも「≦」でも変化無いっぽい。
                   ( prevDownKey = vc ) then//and        //かつ、今回押されているのが、前回と同じキー
                begin
                    flgMaje := true;
                end;

                //リピート無視指定の場合は、前回のダウンがリピートによるものだった場合はチャタとみなさない。
                if flgMaje and ignoreKeyRepert and (keyInformation[vc]^.whileRepeat = true) then
                begin
                    flgMaje := false;
                end;


                keyInformation[vc]^.nextUpDisableFlg := 0;

                //[UP]-[DOWN] キーを離す時に起きるチャタの判定
                if keyUpchatter and (keyInformation[vc]^.prevUpTime <> 0) then
                begin       //UP監視をしている、かつ前回UP時刻が分かっている場合
                    if (keyInformation[vc]^.prevDownTime < keyInformation[vc]^.prevUpTime) then
                    begin                                                   //離した方が後(押下中ではない)の場合、
                        wkMs := ms - keyInformation[vc]^.prevUpTime;        //同一キーの前回UP時刻からの経過時間を求める
                        if not(flgMaje) and ( wkMs < upDownThreshold ) then begin
                            flgMaje := true;
                            keyInformation[vc]^.nextUpDisableFlg := 2;  //この次のUPは捨てたい
                        end;
                    end;
                end;



                //[DOWN]-[UP]後続 UP時チャタの直後DOWN
                //前回UP時に後続Down捨て指定(高精度タイマ前提)していたら、upDown閾値未満のDownはキャンセル
                with keyInformation[vc]^ do
                if (nextDownDisableFlg = 2) and ( (ms-prevUpTime) < upDownThreshold)    then
                begin
                    flgMaje := true;
                end;


                //リピート判定
                //　※ここから以下は今回のダウンがリピートによるものかどうかとして使用する。
                //　　これより前は前回のキーダウンがリピートであったかどうかを表しているので注意。
                if ( keyInformation[vc]^.prevUpTime < keyInformation[vc]^.prevDownTime) then
                begin                           //【注意】この判定を≦にするとチャタを見逃すようになる？
                    keyInformation[vc]^.whileRepeat:=true;
                end else begin
                    keyInformation[vc]^.whileRepeat := false;
                end;


                //キーリピート無視する場合は、upが来てなければチャタじゃない判定。
                if flgMaje and ignoreKeyRepert and (repeatThreshold <= wkMs) then begin
                    //キーリピート無視指定かつ、リピート中閾値以上の場合に判定を行う。
                    //リピート中閾値未満の場合はUP有無によるチャタフラグの再判定は行いません。
                    //不等号が「≦」なのはリピート中閾値に0を指定した時に、リピート完全無視できるようにです。
                    //環境によってはリピート中にpKbdLL.timeが同タイムのDOWNが連続発生することがあるようです。

                    if keyInformation[vc]^.whileRepeat then
                    begin                       //前回upが前回押下よりも過去の場合、
                        flgMaje := false;       //連続してDown⇒リピートなのでチャタじゃない
                    end;

                end;

                //テンキーレスマゼストチに外付けテンキーを付けて使っている人専用オプション
                if (ignoreTenKey and isTenKey(vc)) then
                    flgMaje := false;

                //###########################
                //チャタ判定ここまで
                //###########################


                //今回押下情報を保存
                keyInformation[vc]^.prevDownTime := ms;
                prevDownKey  := vc;

                //チャタ情報設定、保持
                if flgMaje then begin
                    LP := $40000000; //0100…  31がDown(0)で30がチャタ(1)、後ろはまだどうでも良い。
                    keyInformation[vc]^.prevChattering := true;
                end else begin
                    keyInformation[vc]^.prevChattering := false;
                end;


                //確定アンドゥはキャンセルさせない
                //（実際はチャタでは無いけど、内部的にはチャタとして記憶させておく）
                if (undo_kakutei(p,vc,ms)) then begin
                    LP := LP and $bfffffff;     //画面に表示させないように、30を0に戻す。
                    flgMaje := false;           //キャンセルさせないように
                    keyInformation[vc]^.nextDownDisableFlg := 1; //次回のDownは捨てさせない。
                    keyInformation[vc]^.nextUpDisableFlg   := 1; //UPも捨てさせない。
                end else begin
                    keyInformation[vc]^.nextDownDisableFlg := 0;
                end;
                //※これより後ろではnextDownDisableFlgは判定に使用しない


                //キャンセル判定
                if flgMaje and chatteringCancel then begin  //マジェっててかつキャンセル指定時
                    Result := 1;                            //次に送らないだけで何もしなくても良いのか？
                end else begin
                    //LPの値はALL0のままでおｋ。31bitはDown(0)だし、チャタってもいないので30も0
                    Result := CallNextHookEx(pHookInfo(p)^.Keyhook, nCode, wParam, lParam);
                end;


            //####################################################################################################################
            //UP時の処理
            end else begin

                LP := $80000000;    //UPの場合に31bit目=UP(1)  (DOWNの方は何もしなくておｋ)

                //keyInformation[vc]^.nextDownDisableFlg := 0;    【要注意！】ここで0に戻すと確定アンドゥ中に問題。

                //押してから離すまでの時間を測定（または前回upで違うキーのUP連続？）
                if  0 = keyInformation[vc]^.prevDownTime   then begin
                    //wkMs := 0    //前回DOWN時刻が保持されていないのに、UPが来ることはないはず。
                    wkMs := upDownThreshold;
                end else begin
                    wkMs := ms - keyInformation[vc]^.prevDownTime;      //何故かdown直後のupが同一msでやってくることがある
                end;


                keyInformation[vc]^.prevUpTime := ms;    //該当キーの押下時間を保存

                //一部PS/2=>USB変換器ではalt押下中のTABキーのUPが実際に離す前に送出されてくるのでチャタリングに誤判定する事があります。

                //[DOWN]-[UP] キーを押した時に起きるチャタリングの判定
                if chatteringCancel and keyUpchatter and            //キャンセル有効かつUP監視かつ
                   accuracy and (wkMs < upDownThreshold ) and       //高精度タイマ使用かつ、up-down閾値未満かつ
                   (keyInformation[vc]^.nextUpDisableFlg <> 1) and  //有効指定されていない場合かつ
                   (keyInformation[vc]^.whileRepeat = false) then   //リピート中じゃない場合（リピートで送出されたDOWNの後続はチャタじゃない）
                begin
                    LP := LP or $40000000;                          //チャタ通知bit(30)=ON
                    keyInformation[vc]^.prevChattering := true;     //チャタったフラグON
                    keyInformation[vc]^.nextDownDisableFlg := 2;    //次のDownを捨てる指定
                    Result := 1;                                    //キャンセル
                end else begin
                    Result := CallNextHookEx(pHookInfo(p)^.Keyhook, nCode, wParam, lParam);
                end;

                //前回の DOWN がリピートだったかどうかは UP を挟んでも覚えてないといけない。
                //keyInformation[vc]^.whileRepeat:= false;

                keyInformation[vc]^.nextUpDisableFlg := 0;
            end;
            //####################################################################################################################


            //LParamの31ビット目はそのまま(80000000)
            //LParamの30ビット目をチャタフラグに(40000000)
            //下位バイト?にintのミリ秒を設定(3FFFFFFF)

            //pHookInfo(p)^.prevSwitchTime := ms;
            LP := ( (LP AND ($C0000000)) or wkMs);  //ここまでに設定した31,30は上書きしないように。
                                                    //0〜29ビットあれば1073741823ms ≒300時間あるよね？

            //wParamにPKBDLLHOOKSTRUCTのアドレスを送ろうと思ったけど、exe側とはアドレス空間が違うので無理だった。　
            //仮想キーコードもスキャンコードも、DWORD(Longword：符号付なし32ビット)なので、WPARAM(Longint：符号付き32ビット)
            //を2個送るのは難しいっぽい。仮想キーコードなんて256種類しかないのにDWORD?

            WP := (vc AND $000000FF);
            WP := ((pkbdll.flags shl 8) AND $FFFFFF00) or WP;     //※もうnumenterだけ区別がつけばいい。


            //結果を送りつけて画面表示系の処理をさせる
            with pHookInfo(p)^ do
                PostMessage(HostWnd, hookMsg, WP, LP);
        end;
    end;
    //フック処理ここまで


    //MMFマッピング解除、MMFハンドルクローズ
    ReleaseFMObj(_hFMObject, p);

end;

//-----------------------------------------------------------------------------
function getUniqueName():PChar;stdcall;
begin
    //通知側で通知メッセージを作成して判定するために渡す。
    Result := uniqueName;
end;


//-----------------------------------------------------------------------------
//フック開始
function startHook(wnd:hWnd):BOOL;stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
    i:integer;
begin

    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    with pHookInfo(p)^ do begin

        HostWnd := wnd;

        //フックインストール
        Keyhook := SetWindowsHookEx(
                    WH_KEYBOARD_LL,
                    @HookProc,
                    hInstance,
                    0
                );

        //通知用メッセージコード生成
        hookMsg := RegisterWindowMessage(uniqueName);

        //初期化
        prevDownKey    := 0;                //0x00は未使用キーコードらしい
        for i:=0 to 255 do begin
            with keyInformation[i]^ do begin
            prevDownTime := 0;
            prevUpTime   := 0;
            //prevSwitchTime := 0;
            prevChattering   := false;
            nextUpDisableFlg   := 0;
            nextDownDisableFlg := 0;
            whileRepeat := false;
            end;
        end;


    end;

    //フック成功(フラグを立てておく)
    if pHookInfo(p)^.keyHook > 0 then begin
        whileHooking := true;
        Result := True;
    end;




    //共有メモリ使用終了処理
     ReleaseFMObj(_hFMObject, p);
end;


//-----------------------------------------------------------------------------
//フック終了
function endHook():bool;stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin

    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    //フックアンインストール
    if (whileHooking) then
        UnhookWindowsHookEx(pHookInfo(p)^.Keyhook);

    whileHooking := false;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;

//-----------------------------------------------------------------------------
procedure setChaterThresholds(i:integer);stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    pHookInfo(p)^.ChaterThreshold  := i;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;

//-----------------------------------------------------------------------------
procedure setRepeatThresholds(i:integer);stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    pHookInfo(p)^.repeatThreshold  := i;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;
//-----------------------------------------------------------------------------
procedure setUpDownThreshold(i:integer);stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    pHookInfo(p)^.upDownThreshold  := i;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;

//-----------------------------------------------------------------------------
procedure setIgnoreKeyRepert(b:boolean);stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    pHookInfo(p)^.ignoreKeyRepert := b;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;
//-----------------------------------------------------------------------------
procedure setignoreTenKey(b:boolean);stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    pHookInfo(p)^.ignoreTenKey := b;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;

//-----------------------------------------------------------------------------
procedure setChatteringCancel(b:boolean);stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    pHookInfo(p)^.chatteringCancel := b;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;

//-----------------------------------------------------------------------------
procedure setKeyUpchatter(b:boolean);stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    pHookInfo(p)^.keyUpchatter := b;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;


//-----------------------------------------------------------------------------

procedure setAccuracy(b:boolean);stdcall;
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    pHookInfo(p)^.accuracy := b;

    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;


//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
exports   startHook,endHook,getUniqueName
            ,setChaterThresholds,setRepeatThresholds,setUpDownThreshold
            ,setIgnoreKeyRepert
            ,setChatteringCancel,setAccuracy,setignoreTenKey,setKeyUpchatter;


//-----------------------------------------------------------------------------
//初期化
procedure initProc();
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;

    i:integer;
    keyInfo:PKeyInfo;
begin
    //値の初期化はstart時

    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    for i := 0 to 255 do begin
        new(keyInfo);           //割当
        pHookInfo(p)^.keyInformation[i] := keyInfo;
    end;


    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);

end;

//-----------------------------------------------------------------------------
procedure exitProc();
var
    _hFMObject:  THandle;
    p:pointer;
    RS:integer;

    i:integer;
    keyInfo:PKeyInfo;
begin
    //共有メモリ使用準備処理
    RS := GetFMObj(_hFMObject,p);
    if p = nil then begin
        _hFMObject := 0;
        Exit;
    end;

    for i := 0 to 255 do begin
        keyInfo := pHookInfo(p)^.keyInformation[i];
        Dispose(KeyInfo);       //解放
    end;


    //共有メモリ使用終了処理
    ReleaseFMObj(_hFMObject, p);
end;

//-----------------------------------------------------------------------------
procedure DLLEntry(ul_reason_for_call: DWORD);
begin
  case ul_reason_for_call of
    // これらの値の意味については、Win32SDK の
    // DLLEntryPoint の HELP を参照してください。
    //DLL_PROCESS_ATTACH:
    DLL_PROCESS_DETACH:
      begin
        exitProc;
        //MMF開放
        if hFileMapObj = 0 then Exit;
        CloseHandle(hFileMapObj);
      end;
    //DLL_THREAD_ATTACH:
    //DLL_THREAD_DETACH:
  end;





end;


//-----------------------------------------------------------------------------
//初期処理
begin
  whileHooking := false;
  //MMF作成
  hFileMapObj := CreateFileMapping($FFFFFFFF, nil, PAGE_READWRITE,
                                   0, SizeOf(THookInfo), uniqueName);
  if hFileMapObj = 0 then begin
    MessageBox(0 ,'Failed FileMapping!','KeyHookDLL',
               MB_OK or MB_ICONEXCLAMATION or MB_SETFOREGROUND) ;
    Exit;
  end;


  initProc;

  DllProc := @DLLEntry;
end.


