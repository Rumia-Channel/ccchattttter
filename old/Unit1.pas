unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls,MMsystem, ExtCtrls,ShellAPI, AppEvnts, Menus,IniFiles,
  Buttons,Clipbrd;

  //ShellAPIはタスクトレイアイコン操作用（Shell_NotifyIcon）
  //MMSYSTEMは音鳴らし用（元々入ってた）

const
    WM_MY_TRAYICON = WM_USER + 100;

//Low level hook flags
    LLKHF_EXTENDED =      (KF_EXTENDED shr 8);
    LLKHF_INJECTED =      $10;
    LLKHF_ALTDOWN  =      (KF_ALTDOWN shr 8);
    LLKHF_UP       =      (KF_UP shr 8);

type
  TForm1 = class(TForm)
    ApplicationEvents1: TApplicationEvents;
    PopupMenu1: TPopupMenu;
    Exit1: TMenuItem;
    N1: TMenuItem;
    OpenDialog1: TOpenDialog;
    Panel1: TPanel;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    chkIgnoreKeyRepert: TCheckBox;
    btnStart: TButton;
    btnStop: TButton;
    Edit1: TEdit;
    btnClear: TButton;
    chkchatterCancel: TCheckBox;
    Edit2: TEdit;
    btnSound: TButton;
    chkSound: TCheckBox;
    chkAccuracy: TCheckBox;
    chkViewUp: TCheckBox;
    chkIgnoreTenKey: TCheckBox;
    Panel2: TPanel;
    ListBox2: TListBox;
    ListBox1: TListBox;
    PopupMenu2: TPopupMenu;
    A1: TMenuItem;
    Copy1: TMenuItem;
    PopupMenu3: TPopupMenu;
    A2: TMenuItem;
    Copy2: TMenuItem;
    Label9: TLabel;
    Label10: TLabel;
    Label6: TLabel;
    edtLogMax: TEdit;
    chkLogChatter: TCheckBox;
    chkLoging: TCheckBox;
    Bevel1: TBevel;
    Bevel2: TBevel;
    Bevel3: TBevel;
    Bevel4: TBevel;
    Bevel5: TBevel;
    Bevel6: TBevel;
    Edit3: TEdit;
    procedure btnStartClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnClearClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Edit1Change(Sender: TObject);
    procedure Edit2Change(Sender: TObject);
    procedure Edit3Change(Sender: TObject);
    //procedure WatchMessage(var Msg: TMsg; var Handled: Boolean);
    procedure CreateTaskBarIcon();
    procedure DeleteTaskBarIcon();
    procedure ApplicationEvents1Minimize(Sender: TObject);
    procedure Exit1Click(Sender: TObject);
    procedure FormCanResize(Sender: TObject; var NewWidth,
      NewHeight: Integer; var Resize: Boolean);
    procedure chkIgnoreKeyRepertClick(Sender: TObject);
    procedure chkchatterCancelClick(Sender: TObject);
    procedure N1Click(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure chkLogingClick(Sender: TObject);
    procedure btnSoundClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure chkAccuracyClick(Sender: TObject);
    procedure edtLogMaxChange(Sender: TObject);
    procedure A1Click(Sender: TObject);
    procedure A2Click(Sender: TObject);
    procedure Copy1Click(Sender: TObject);
    procedure Copy2Click(Sender: TObject);
    procedure ListBox1KeyPress(Sender: TObject; var Key: Char);
    procedure chkIgnoreTenKeyClick(Sender: TObject);
    procedure chkViewUpClick(Sender: TObject);
  private
    { Private 宣言 }
    procedure WndProc(var Message: TMessage);override;
    procedure changeBtnEnable();
    function getKeyName(vc:integer;fg:DWORD):string;
    //独自メッセージ受信
    procedure WMUSER(var Msg : TMsg); message WM_MY_TRAYICON;
    { ＜メモ＞
    複数のアプリケーションが共通のメッセージを処理する必要がある場合に限って、
    RegisterWindowMessage 関数を使ってください。
    1 つのウィンドウクラス内でプライベートメッセージを送信する場合、
    アプリケーションは WM_USER（0x0400）〜0x7FFF の範囲の任意の整数を使うことができます。
    （この範囲内のメッセージは、アプリケーションではなくウィンドウクラスにとって
    プライベートです。たとえば、BUTTON、EDIT、LISTBOX、COMBOBOX のようなあらかじめ
    定義されたコントロールが、この範囲内の値を使うことがあります。）
    メッセージの値の一覧については、MSDN ライブラリの「WM_USER」を参照してください。
    }

    //シャットダウンメッセージを処理するプロシージャ
    procedure WMEndSession(var Msg:TWMEndSession); message WM_ENDSESSION;
  public
    { Public 宣言 }
  end;



var
    Form1: TForm1;

    //フック関連
    MsgSeed : string;
    hookMsg  : integer;

    //タスクトレイ関連
    NID : TNotifyIconData;
    uTaskBarRecreate:integer;

    //sound関連
    waveFileName:string;
    MSwaveFile :TMemoryStream;

    logMaXLine:integer;

const
    NO_LOG_HEIGHT = 120;

    LOG_WIDTH = 257;
    LOG_HEIGHT = 314;

implementation

{$R *.dfm}

    function startHook(wnd : hWnd):bool;stdcall;      external 'hooookk.dll';
    function endHook():bool;stdcall;                  external 'hooookk.dll';
    function getUniqueName():PChar;stdcall;           external 'hooookk.dll';
    procedure setIgnoreKeyRepert(b:boolean);stdcall;  external 'hooookk.dll';
    procedure setignoreTenKey(b:boolean);stdcall;     external 'hooookk.dll';
    procedure setChaterThresholds(i:integer);stdcall; external 'hooookk.dll';
    procedure setRepeatThresholds(i:integer);stdcall; external 'hooookk.dll';
    procedure setChatteringCancel(b:boolean);stdcall; external 'hooookk.dll';
    procedure setAccuracy(b:boolean);stdcall;         external 'hooookk.dll';
    procedure setKeyUpchatter(b:boolean);stdcall;     external 'hooookk.dll';
    procedure setUpDownThreshold(i:integer);stdcall;  external 'hooookk.dll';

//-----------------------------------------------------------------------------
procedure TForm1.WndProc(var Message: TMessage);
var
    wk:string;
    i:integer;
    cpKeyRepeat:Longint; //コンパネキーリピート
    p:pchar;
    b:bool;
    vc:integer;
    fg:DWORD;

begin

    //フックDLLからメッセージがやってきた場合の処理をここに書く
    if (Message.Msg = hookMsg) then begin
        //ここで行うのは、ログ描画のみなので、キー入力処理自体を優先させる。
        Application.HandleMessage;

        //wParamには仮想キーコードやその他識別。
        //lParamのビット31にキーの遷移状態、それ以外のビットは経過時間


        //キー名称取得
        vc := (Message.WParam and $000000FF);
        fg := (Message.WParam and $FFFFFF00) shr 8;
        wk := getKeyName(vc,fg) + #9;

        //up down判定
        if (Message.LParam and $80000000) = 0 then begin
            //押下時--------------------------
            wk := wk + 'DOWN';

            wk := wk + #9 + IntToStr(Message.LParam and $3FFFFFFF) + 'ms';

            //チャタ表示
            if (Message.LParam and $40000000) <> 0 then begin
                wk := wk + #9 + 'chattering!?';
                if chkSound.checked then
                    PlaySound(PChar(waveFileName),0,SND_FILENAME or SND_ASYNC or SND_ASYNC);

            end;

            //キー押下一覧追加
            if chkLoging.Checked  then begin
                ListBox1.ItemIndex := ListBox1.items.Add(wk);
                if (logMaxLine<>0) and (ListBox1.Count > logMaxLine) then begin
                    ListBox1.Items.Delete(0);
                end;

            end;

            //チャタ一覧追加
            if (chkLoging.Checked or chkLogChatter.Checked)and
               ((Message.LParam and $40000000) <> 0) then
            begin
                ListBox2.ItemIndex := ListBox2.Items.Add(wk);
                if (logMaxLine<>0) and (ListBox2.Count > logMaxLine) then begin
                    ListBox2.Items.Delete(0);
                end;
            end;


        end
        else
        begin
            //開放時--------------------------
            wk := wk + 'UP';


            i := Message.LParam and $3FFFFFFF;
            //if i =0 then
                wk := wk + #9 + IntToStr(i) + 'ms';
            //}

            //チャタ表示
            if (Message.LParam and $40000000) <> 0 then
                wk := wk + #9 + 'chattering!?';

            //キー押下一覧追加
            if chkLoging.Checked and chkViewUp.Checked then begin
                ListBox1.ItemIndex := ListBox1.Items.Add(wk);
                if (logMaxLine<>0) and (ListBox1.Count > logMaxLine) then begin
                    ListBox1.Items.Delete(0);
                end;
            end;

            //チャタ一覧追加
            if (chkLoging.Checked or chkLogChatter.Checked)and
               ((Message.LParam and $40000000) <> 0) and
               chkViewUp.Checked then
            begin
                ListBox2.ItemIndex := ListBox2.Items.Add(wk);
                if (logMaxLine<>0) and (ListBox2.Count > logMaxLine) then begin
                    ListBox2.Items.Delete(0);
                end;
            end;

        end;
    end else if (Message.Msg = WM_SETTINGCHANGE) then begin

        //if Message.WParam = SPI_SETKEYBOARDSPEED then begin
        if  Message.WParam = SPI_SETKEYBOARDDELAY    //何で0x17? 0xBじゃなくて？
        then begin
            //リピート間隔の取得()
            {
                SystemParametersInfo(
                    uiAction:Cardinal,    SPI_GETKEYBOARDSPEED キーボード「表示の間隔」取得
                    uiParam:Cardinal,     使用しない
                    pvParam:Pointer,      32ビット長整数型変数のポインタ(0〜31が返却される)
                    fWinIni:Cardinal      レジストリを更新しないので0
                    );
            }

            SystemParametersInfo(SPI_GETKEYBOARDSPEED,0,@cpKeyRepeat,0);
            ListBox1.Items.Add('====================================');
            ListBox1.Items.Add('キーボードのプロパティが変更されました');
            ListBox1.Items.Add('文字の入力速度：表示の間隔 = [' + IntToStr(cpKeyRepeat) + ']');
            ListBox1.Items.Add('====================================');
            ListBox1.ItemIndex := ListBox1.Count-1;

            ListBox1.Items.BeginUpdate;
            while (logMaxLine<>0) and (ListBox1.Count > logMaxLine) do begin
                ListBox1.Items.Delete(0);
            end;
            ListBox1.Items.EndUpdate;
        end;

    end;
    //--------------------------------------------------------

    //デフォルトの処理
    inherited WndProc(Message);
end;

//-----------------------------------------------------------------------------
procedure TForm1.FormCreate(Sender: TObject);
var
    ini:TIniFile;
    bl:boolean;
begin

    hookMsg := RegisterWindowMessage(getUniqueName());  //メッセージ登録
    if hookMsg = 0 then begin
        raise Exception.Create('Can''t Regist Message');
        Application.Terminate;
    end;
    uTaskBarRecreate := RegisterWindowMessage('TaskbarCreated');

    //iniファイル読み込み
    try
        ini := TIniFile.Create(ChangeFileExt(Application.ExeName,'.ini'));

        Form1.Top    := ini.ReadInteger('form','top',Form1.Top);
        Form1.Left   := ini.ReadInteger('form','left',Form1.Left);
        Form1.Height := ini.ReadInteger('form','height',Form1.Height);
        Form1.Width  := ini.ReadInteger('form','width',Form1.Width);

        if ini.ReadBool('form','Minimized',false) then
            form1.WindowState := wsMinimized;

        Edit1.Text := IntToStr(ini.ReadInteger('setting','chattering-Threshold',50));
        Edit2.Text := IntToStr(ini.ReadInteger('setting','KeyRepeat-Threshold' ,0));
        Edit3.Text := IntToStr(ini.ReadInteger('setting','KeyUpDown-Threshold' ,8));

        chkIgnoreKeyRepert.Checked := ini.ReadBool('setting','IgnoreKeyRepert',true);
        chkchatterCancel.Checked :=   ini.ReadBool('setting','chatterCancel'  ,true);
        chkViewUp.Checked :=          ini.ReadBool('setting','ViewUp'         ,false);
        chkLoging.Checked :=          ini.ReadBool('setting','Loging'         ,false);
        chkAccuracy.Checked :=        ini.ReadBool('setting','accuracy'       ,false);
        chkLogChatter.Checked :=      ini.ReadBool('setting','LogChatter'     ,false);
        edtLogMax.Text        :=      IntToStr(ini.ReadInteger('setting','LogMax',1000));
        chkIgnoreTenKey.Checked :=    ini.ReadBool('setting','IgnoreTenKey',false);

        chkSound.Checked := ini.ReadBool('sound','on',false);
        waveFileName := ini.ReadString('sound','waveFileName','');

    finally
        ini.Free;
    end;


    //DLL設定値初期化
    //setChaterThresholds(StrToInt(Edit1.Text));
    //setRepeatThresholds(StrToInt(Edit2.Text));
    Edit1Change(Edit1);
    Edit2Change(Edit2);
    setIgnoreKeyRepert(chkIgnoreKeyRepert.Checked);
    setChatteringCancel(chkchatterCancel.Checked);

    ListBox1.DoubleBuffered := true;
    ListBox2.DoubleBuffered := true;

    btnStart.Enabled := true;
    btnStop.Enabled := false;

    chkLogingClick(chkLoging);
    chkViewUpClick(chkViewUp);

    //有効状態で開始
    btnStartClick(Sender);

    if waveFileName = '' then
        chkSound.Enabled := false
    else begin
        chkSound.Enabled := true;
        MSwaveFile := TMemoryStream.Create;
        MSwaveFile.LoadFromFile(waveFileName);
    end;


end;

//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
var
    ini:TIniFile;
begin
    btnStopClick(Sender);

    //タスクトレイアイコンを削除
    Shell_NotifyIcon(NIM_DELETE, @NID);

    try
        ini := TIniFile.Create(ChangeFileExt(Application.ExeName,'.ini'));

        ini.WriteInteger('setting','chattering-Threshold',StrToInt(Edit1.Text));
        ini.WriteInteger('setting','KeyRepeat-Threshold' ,StrToInt(Edit2.Text));
        ini.WriteInteger('setting','KeyUpDown-Threshold' ,StrToInt(Edit3.Text));

        ini.WriteBool('setting','IgnoreKeyRepert',chkIgnoreKeyRepert.Checked);
        ini.WriteBool('setting','chatterCancel'  ,chkchatterCancel.Checked);
        ini.WriteBool('setting','ViewUp'         ,chkViewUp.Checked);
        ini.WriteBool('setting','Loging'         ,chkLoging.Checked);
        ini.WriteBool('setting','accuracy'       ,chkAccuracy.Checked);
        ini.WriteBool('setting','LogChatter'     ,chkLogChatter.Checked);
        ini.WriteInteger('setting','LogMax',StrToInt(edtLogMax.Text));
        ini.WriteBool('setting','IgnoreTenKey',chkIgnoreTenKey.Checked);

        ini.WriteInteger('form','top'   ,Form1.Top);
        ini.WriteInteger('form','left'  ,Form1.Left);
        ini.WriteInteger('form','height',Form1.Height);
        ini.WriteInteger('form','width' ,Form1.Width);

        ini.WriteBool('sound','on',chkSound.Checked);
        ini.WriteString('sound','waveFileName' ,waveFileName);

        ini.WriteBool('form','Minimized',not(Form1.Visible));


    finally
        ini.Free;
    end;

end;


//-----------------------------------------------------------------------------
procedure TForm1.changeBtnEnable();
begin
    btnStart.Enabled := not(btnStart.Enabled);
    btnStop.Enabled := not(btnStop.Enabled);

    n1.Checked := btnStop.Enabled;

end;

//-----------------------------------------------------------------------------
procedure TForm1.btnStartClick(Sender: TObject);
begin


    startHook(Form1.Handle);

    changeBtnEnable;

end;

//-----------------------------------------------------------------------------
procedure TForm1.btnStopClick(Sender: TObject);
begin

    endHook();
    changeBtnEnable;

end;

//-----------------------------------------------------------------------------
procedure TForm1.btnClearClick(Sender: TObject);
begin
    if (ListBox1.Count = 0) or (ListBox1.Width = 0) then begin
        ListBox2.Clear;
    end;

    ListBox1.Clear;

end;


//-----------------------------------------------------------------------------
procedure TForm1.Edit1Change(Sender: TObject);
var
    i:integer;
const
    org:string='';
begin
    i := StrToIntDef (TEdit(Sender).Text,0);
    if (i = 0) then
        TEdit(Sender).Text := org
    else
        org := TEdit(Sender).Text;

    setChaterThresholds(StrToInt(Edit1.Text))

end;
//-----------------------------------------------------------------------------
procedure TForm1.Edit2Change(Sender: TObject);
var
    i:integer;
const
    org:string='';
begin
    i := StrToIntDef (TEdit(Sender).Text,-1);
    if (i = -1) then
        TEdit(Sender).Text := org
    else
        org := TEdit(Sender).Text;

    setRepeatThresholds(StrToInt(Edit2.Text))

end;

//-----------------------------------------------------------------------------
procedure TForm1.Edit3Change(Sender: TObject);
var
    i:integer;
const
    org:string='';
begin
    i := StrToIntDef (TEdit(Sender).Text,-1);
    if (i = -1) then
        TEdit(Sender).Text := org
    else
        org := TEdit(Sender).Text;

    setUpDownThreshold(StrToInt(Edit3.Text))

end;


//-----------------------------------------------------------------------------
function TForm1.getKeyName(vc:integer;fg:DWORD):string;
begin

    case vc of   //Virtual Key Code
		VK_LBUTTON    :       Result := 'LBUTTON';
		VK_RBUTTON    :       Result := 'RBUTTON';
		VK_CANCEL     :       Result := 'CANCEL';
		VK_MBUTTON    :       Result := 'MBUTTON';	// NOT contiguous with L & RBUTTON
		VK_BACK       :       Result := 'BS';
		VK_TAB        :       Result := 'TAB';
		VK_CLEAR      :       Result := 'CLEAR';
		//VK_RETURN     :       Result := 'RETURN';
        VK_RETURN     :       
            if (fg and LLKHF_EXTENDED = 1) then
                Result := 'NumEnter'
            else
                Result := 'Enter';
		VK_SHIFT      :       Result := 'SHIFT';
		VK_CONTROL    :       Result := 'CONTROL';
		VK_MENU       :       Result := 'MENU';
		VK_PAUSE      :       Result := 'PAUSE';
		VK_CAPITAL    :       Result := 'CAPITAL';
		VK_KANA       :       Result := 'KANA';
		//VK_HANGUL     :       Result := 'HANGUL';
		VK_JUNJA      :       Result := 'JUNJA';
		VK_FINAL      :       Result := 'FINAL';
		//VK_HANJA      :       Result := 'HANJA';
		VK_KANJI      :       Result := 'KANJI';
		VK_CONVERT    :       Result := '変換';
		VK_NONCONVERT :       Result := '無変換';
		VK_ACCEPT     :       Result := 'ACCEPT';
		VK_MODECHANGE :       Result := 'MODECHANGE';
		VK_ESCAPE     :       Result := 'ESC';
		VK_SPACE      :       Result := 'SPACE';
		VK_PRIOR      :       Result := 'PageDown';
		VK_NEXT       :       Result := 'PageUp';
		VK_END        :       Result := 'END';
		VK_HOME       :       Result := 'HOME';
		VK_LEFT       :       Result := '←';
		VK_UP         :       Result := '↑';
		VK_RIGHT      :       Result := '→';
		VK_DOWN       :       Result := '↓';
		VK_SELECT     :       Result := 'SELECT';
		VK_PRINT      :       Result := 'PRINT';
		VK_EXECUTE    :       Result := 'EXECUTE';
		VK_SNAPSHOT   :       Result := 'PrintSc';
		VK_INSERT     :       Result := 'INSERT';
		VK_DELETE     :       Result := 'DELETE';
		VK_HELP       :       Result := 'HELP';
		//VK_A          :       Result := 'A';thru VK_Z are the same as ASCII 'A' thru 'Z' ($41 - $5A)
        ord('A')..ord('Z')    :       Result := chr(vc);
		VK_LWIN       :       Result := 'LWIN';
		VK_RWIN       :       Result := 'RWIN';
		VK_APPS       :       Result := 'APPS';
		VK_NUMPAD0    :       Result := 'Num0';
		VK_NUMPAD1    :       Result := 'Num1';
		VK_NUMPAD2    :       Result := 'Num2';
		VK_NUMPAD3    :       Result := 'Num3';
		VK_NUMPAD4    :       Result := 'Num4';
		VK_NUMPAD5    :       Result := 'Num5';
		VK_NUMPAD6    :       Result := 'Num6';
		VK_NUMPAD7    :       Result := 'Num7';
		VK_NUMPAD8    :       Result := 'Num8';
		VK_NUMPAD9    :       Result := 'Num9';
		VK_MULTIPLY   :       Result := 'Num*';
		VK_ADD        :       Result := 'Num+';
		VK_SEPARATOR  :       Result := 'SEPARATOR';
		VK_SUBTRACT   :       Result := 'Num-';
		VK_DECIMAL    :       Result := 'Num.';
		VK_DIVIDE     :       Result := 'Num/';
		VK_F1         :       Result := 'F1';
		VK_F2         :       Result := 'F2';
		VK_F3         :       Result := 'F3';
		VK_F4         :       Result := 'F4';
		VK_F5         :       Result := 'F5';
		VK_F6         :       Result := 'F6';
		VK_F7         :       Result := 'F7';
		VK_F8         :       Result := 'F8';
		VK_F9         :       Result := 'F9';
		VK_F10        :       Result := 'F10';
		VK_F11        :       Result := 'F11';
		VK_F12        :       Result := 'F12';
		VK_F13        :       Result := 'F13';
		VK_F14        :       Result := 'F14';
		VK_F15        :       Result := 'F15';
		VK_F16        :       Result := 'F16';
		VK_F17        :       Result := 'F17';
		VK_F18        :       Result := 'F18';
		VK_F19        :       Result := 'F19';
		VK_F20        :       Result := 'F20';
		VK_F21        :       Result := 'F21';
		VK_F22        :       Result := 'F22';
		VK_F23        :       Result := 'F23';
		VK_F24        :       Result := 'F24';
		VK_NUMLOCK    :       Result := 'NumLock';
		VK_SCROLL     :       Result := 'SCROLL';
		VK_LSHIFT     :       Result := 'LSHIFT';
		VK_RSHIFT     :       Result := 'RSHIFT';
		VK_LCONTROL   :       Result := 'LCTRL';
		VK_RCONTROL   :       Result := 'RCTRL';
		VK_LMENU      :       Result := 'LAlt';
		VK_RMENU      :       Result := 'RAlt';
		VK_PROCESSKEY :       Result := 'PROCESSKEY';
		VK_ATTN       :       Result := 'ATTN';
		VK_CRSEL      :       Result := 'CRSEL';
		VK_EXSEL      :       Result := 'EXSEL';
		VK_EREOF      :       Result := 'EREOF';
		VK_PLAY       :       Result := 'PLAY';
		VK_ZOOM       :       Result := 'ZOOM';
		VK_NONAME     :       Result := 'NONAME';
		VK_PA1        :       Result := 'PA1';
		VK_OEM_CLEAR  :       Result := 'OEM_CLEAR';
        48: Result := '0';
        49: Result := '1';
        50: Result := '2';
        51: Result := '3';
        52: Result := '4';
        53: Result := '5';
        54: Result := '6';
        55: Result := '7';
        56: Result := '8';
        57: Result := '9';
        242: Result := 'カタひら';
        188: Result := 'COMMA';
        190: Result := 'PERIOD';
        191: Result := '/';
        //220: Result := '\';
        //226: Result := '\';
        222: Result := '^';
        189: Result := '-';
        221: Result := ']';
        186: Result := 'ｺﾛﾝ';
        187: Result := 'ｾﾐｺﾛﾝ';
        219: Result := '[';
        192: Result := '@';
//        : Result := '';
        else
            Result := 'VK(' + IntToStr(vc) + ')';
    end;


end;

//-----------------------------------------------------------------------------
procedure TForm1.WMUSER(var Msg: TMsg);
var
  ps: TPoint;
begin
  Case Msg.wParam  of
    WM_LBUTTONDBLCLK:   //左(通常)ダブルクリック
      begin
        Form1.WindowState := wsNormal;
        ShowWindow(Application.Handle,SW_SHOW);
        ShowWindow(Application.Handle,SW_RESTORE);
        ListBox1.ItemIndex := ListBox1.Count-1;
        ListBox2.ItemIndex := ListBox2.Count-1;
        Form1.Visible := true;
        DeleteTaskBarIcon;


      end;
    WM_RBUTTONUP:
      begin
        GetCursorPos(ps);
        SetForegroundWindow(Handle);
        // フォームにポップアップメニューがあるとする
        PopupMenu1.Popup(ps.x,ps.y);
        PostMessage(Handle, WM_NULL, 0,0);
      end;
    else
      // タスクバーが移動・再構築された場合に消えたアイコンを再生成
      if (Msg.LParam = LongInt(uTaskBarRecreate)) then
        CreateTaskBarIcon;
  end;

end;

//-----------------------------------------------------------------------------
procedure TForm1.CreateTaskBarIcon();
begin

    with NID do begin
        cbSize :=Sizeof(NID);
        hIcon  := Application.Icon.Handle;
        //hIcon := Image1.Picture.Icon.Handle;
        Wnd    :=Form1.Handle;
        szTip  :='ccchattttter';
        uCallbackMessage := WM_MY_TRAYICON;
        uFlags := NIF_MESSAGE or NIF_ICON or NIF_TIP ;
    end;

    //タスクトレイアイコンを追加
    Shell_NotifyIcon(NIM_ADD, @NID);
end;

//-----------------------------------------------------------------------------
// アイコンを削除
procedure TForm1.DeleteTaskBarIcon;
var
  NotifyData: TNotifyIconData;
begin
  with NotifyData do
  begin
    cbSize := SizeOf(TNotifyIconData);
    Wnd    := Form1.Handle;
    uID    := 0;
  end;
  Shell_NotifyIcon( NIM_DELETE, @NotifyData );
end;

//-----------------------------------------------------------------------------
procedure TForm1.ApplicationEvents1Minimize(Sender: TObject);
begin
    CreateTaskBarIcon;

    form1.Visible := false;

    //タスクバー非表示
    ShowWindow(Application.Handle,SW_HIDE);
end;

//-----------------------------------------------------------------------------
procedure TForm1.Exit1Click(Sender: TObject);
begin
    form1.Close;
end;

//-----------------------------------------------------------------------------
procedure TForm1.FormCanResize(Sender: TObject; var NewWidth,
  NewHeight: Integer; var Resize: Boolean);
begin
    if (NewWidth <523) then
        NewWidth := 523;

    if chkLoging.Checked then begin
        if  (NewHeight <LOG_HEIGHT ) then NewHeight :=LOG_HEIGHT;
    end else begin
        if (NewHeight < Panel1.ClientHeight+ (Form1.Height -Form1.ClientHeight)) then
            NewHeight :=Panel1.ClientHeight+ (Form1.Height -Form1.ClientHeight);
    end;

end;

//-----------------------------------------------------------------------------
procedure TForm1.chkLogingClick(Sender: TObject);
begin
    //chkViewUp.Enabled := chkLoging.Checked;
    chkLogChatter.Enabled := not(chkLoging.Checked);


    if chkLoging.Checked or chkLogChatter.Checked  then begin
        edtLogMax.Enabled := true;
        edtLogMax.Color := clWindow;
    end else begin
        edtLogMax.Enabled := false;
        edtLogMax.Color := clBtnFace;
    end;

    //if (form1.WindowState = wsnormal) then

    if chkLoging.Checked or (chkLogChatter.Checked and chkLogChatter.Enabled) then begin
        if (form1.Height < LOG_HEIGHT) then form1.Height := LOG_HEIGHT;
    end else begin
        form1.Height := Panel1.ClientHeight + (Form1.Height -Form1.ClientHeight);
    end;

    if (chkLoging.Checked = false) and chkLogChatter.Checked then begin
        //ListBox1.Visible := false;   //ウィンドウ作成前に呼ばれると落ちるのでwideを変更するように
        ListBox1.Width := 0;
        ListBox2.Left := 0;
        ListBox2.Width := Form1.ClientWidth;
    end else begin
        //ListBox1.Visible := true;
        ListBox1.Width := LOG_WIDTH;
        ListBox2.Left := LOG_WIDTH;

        ListBox2.Width := Form1.ClientWidth - LOG_WIDTH;
    end;

end;

//-----------------------------------------------------------------------------
procedure TForm1.chkIgnoreKeyRepertClick(Sender: TObject);
begin
    setIgnoreKeyRepert(chkIgnoreKeyRepert.Checked);

    if chkIgnoreKeyRepert.Checked then begin
        edit2.Enabled := true;
        edit2.Color := clWindow;
    end else begin
        edit2.Enabled := false;
        edit2.Color := clBtnFace;
    end;
end;

//-----------------------------------------------------------------------------
procedure TForm1.chkchatterCancelClick(Sender: TObject);
begin
    setChatteringCancel(chkchatterCancel.Checked);
end;

//-----------------------------------------------------------------------------
procedure TForm1.N1Click(Sender: TObject);
begin
    //
    if n1.Checked then
        btnStopClick(Sender)
    else
        btnStartClick(Sender);
end;

//-----------------------------------------------------------------------------
procedure TForm1.FormShow(Sender: TObject);
begin
   // Memo1.SetFocus;
   // chkLogingClick(Sender);
end;

//-----------------------------------------------------------------------------
procedure TForm1.btnSoundClick(Sender: TObject);
begin
    if waveFileName = '' then
        OpenDialog1.InitialDir := ExtractFileDir (Application.ExeName)
    else
        OpenDialog1.FileName := waveFileName;

    if OpenDialog1.Execute then begin
        waveFileName := OpenDialog1.FileName;
        chkSound.Enabled := true;

        if MSwaveFile <> nil then
            MSwaveFile.Free;

        MSwaveFile :=TMemoryStream.Create;
        MSwaveFile.LoadFromFile(waveFileName);

    end;

end;

//-----------------------------------------------------------------------------
procedure TForm1.FormDestroy(Sender: TObject);
begin

    if MSwaveFile <> nil then
        MSwaveFile.Free;

end;

//-----------------------------------------------------------------------------
procedure TForm1.chkAccuracyClick(Sender: TObject);
begin
    setAccuracy(chkAccuracy.Checked);
end;


//-----------------------------------------------------------------------------
procedure TForm1.edtLogMaxChange(Sender: TObject);
var
    i:integer;
const
    org:string='';
begin
    i := StrToIntDef (TEdit(Sender).Text,-1);
    if (i = -1) then
        TEdit(Sender).Text := org
    else
        org := TEdit(Sender).Text;

    logMaxLine := StrToInt(TEdit(Sender).Text);

    if logMaXLine = 0 then exit;

    //ListBoxの最大長まで切りつめ
    ListBox1.Items.BeginUpdate;
    while (logMaxLine<>0) and (ListBox1.Count > logMaxLine) do begin
        ListBox1.Items.Delete(0);
    end;
    ListBox1.Items.EndUpdate;

    ListBox2.Items.BeginUpdate;
    while (logMaxLine<>0) and (ListBox2.Count > logMaxLine) do begin
        ListBox2.Items.Delete(0);
    end;
    ListBox2.Items.EndUpdate;

end;

//-----------------------------------------------------------------------------
procedure TForm1.A1Click(Sender: TObject);
begin
    ListBox1.Items.BeginUpdate;
    ListBox1.SelectAll;
    ListBox1.Items.EndUpdate;

end;

//-----------------------------------------------------------------------------
procedure TForm1.A2Click(Sender: TObject);
begin
    ListBox2.Items.BeginUpdate;
    ListBox2.SelectAll;
    ListBox2.Items.EndUpdate;
end;

//-----------------------------------------------------------------------------
procedure TForm1.Copy1Click(Sender: TObject);
var
    i:integer;
    s:string;
begin
    //Senderを使って何とか上手く出来ない物か？
    for i:=0 to ListBox1.Count-1 do begin
        if ListBox1.Selected[i] then begin
            s := s + ListBox1.Items.Strings[i];
            if i <> ListBox1.Count-1 then
                s := s + #13#10;
        end;
    end;
    Clipboard.SetTextBuf(PChar(s));
end;

//-----------------------------------------------------------------------------
procedure TForm1.Copy2Click(Sender: TObject);
var
    i:integer;
    s:string;
begin
    for i:=0 to ListBox2.Count-1 do begin
        if ListBox2.Selected[i] then begin
            s := s + ListBox2.Items.Strings[i];
            if i <> ListBox2.Count-1 then
                s := s + #13#10;
        end;
    end;
    Clipboard.SetTextBuf(PChar(s));
end;

//-----------------------------------------------------------------------------
procedure TForm1.ListBox1KeyPress(Sender: TObject; var Key: Char);
begin
    //フォーカスがある時に自動的に選択されないように。
    key := #0;


    //AutoCompleteをOFFにするだけでは意味がない。
    //AutoCompleteがOFFの場合、押したキーが先頭文字に一致するIndexにジャンプするが、
    //AutoCompleteはONだと複数キーを押した文字列で検索してIndexを指定できるようになる
    //
    //例：aaa,bb,bc,cdと入っている時にbを押すと2個目が選択される、
    //    続けてcを押した時に、OFFだとcdの4個目が選択されるが、
    //    ONだとbcの3個目が選択される。

end;

//-----------------------------------------------------------------------------
procedure TForm1.chkIgnoreTenKeyClick(Sender: TObject);
begin
    setignoreTenKey(chkIgnoreTenKey.Checked);
end;

procedure TForm1.WMEndSession(var Msg: TWMEndSession);
begin
    Form1.Close;
    inherited;
end;

//-----------------------------------------------------------------------------
procedure TForm1.chkViewUpClick(Sender: TObject);
begin
    setKeyUpchatter(chkViewUp.Checked);

    if chkViewUp.Checked  then begin
        Edit3.Enabled := true;
        Edit3.Color := clWindow;
    end else begin
        Edit3.Enabled := false;
        Edit3.Color := clBtnFace;
    end;
end;

end.
