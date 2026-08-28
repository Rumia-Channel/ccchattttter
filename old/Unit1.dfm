object Form1: TForm1
  Left = 587
  Top = 179
  Width = 523
  Height = 280
  Caption = 'ccchattttter'
  Color = clBtnFace
  Font.Charset = SHIFTJIS_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = #65325#65331' '#65328#12468#12471#12483#12463
  Font.Style = []
  Icon.Data = {
    0000010001002020100001000400E80200001600000028000000200000004000
    0000010004000000000000000000000000000000000000000000000000000000
    0000000080000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000001
    1111111111111111111111111100000111111111111111111111111111000001
    1111111100000000111111111100000111111111000000001111111111000001
    1111111100000000111111111100000111111111000000001111111111000001
    1100000000000000000000111100000111000000000000000000001111000001
    1100000000000000000000111100000111000000000000000000001111000001
    1100000000000000000000111100000111000000000000000000001111000001
    1100000000111100000000111100000111000000001111000000001111000001
    1100000000111100000000111100000111000000001111000000001111000000
    0000111111111111111100000000000000001111111111111111000000000000
    0000111111111111111100000000000000001111111111111111000000000000
    0000000000111100000000000000000000000000001111000000000000000000
    0000000000111100000000000000000000000000001111000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000FC00
    003FFC00003FFFF00FFFFFF00FFFFFF00FFFFFF00FFFFFFFFFFFFFFFFFFF}
  OldCreateOrder = False
  Scaled = False
  OnCanResize = FormCanResize
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 12
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 515
    Height = 65
    Align = alTop
    BevelOuter = bvNone
    Ctl3D = True
    ParentCtl3D = False
    TabOrder = 0
    object Label1: TLabel
      Left = 349
      Top = 6
      Width = 15
      Height = 12
      Caption = 'ms'
    end
    object Label2: TLabel
      Left = 349
      Top = 26
      Width = 15
      Height = 12
      Caption = 'ms'
    end
    object Label3: TLabel
      Left = 212
      Top = 6
      Width = 93
      Height = 12
      Alignment = taRightJustify
      Caption = 'DOWN-UP-DOWN'
    end
    object Label4: TLabel
      Left = 233
      Top = 26
      Width = 72
      Height = 12
      Alignment = taRightJustify
      Caption = 'DOWN-DOWN'
    end
    object Label9: TLabel
      Left = 349
      Top = 46
      Width = 15
      Height = 12
      Caption = 'ms'
    end
    object Label10: TLabel
      Left = 251
      Top = 46
      Width = 54
      Height = 12
      Alignment = taRightJustify
      Caption = 'UP-DOWN'
    end
    object Label6: TLabel
      Left = 201
      Top = 49
      Width = 34
      Height = 12
      Caption = #34892#12414#12391
    end
    object Bevel1: TBevel
      Left = 271
      Top = 3
      Width = 35
      Height = 17
    end
    object Bevel2: TBevel
      Left = 271
      Top = 24
      Width = 35
      Height = 17
    end
    object Bevel3: TBevel
      Left = 271
      Top = 44
      Width = 35
      Height = 17
    end
    object Bevel4: TBevel
      Left = 211
      Top = 3
      Width = 35
      Height = 17
    end
    object Bevel5: TBevel
      Left = 232
      Top = 24
      Width = 35
      Height = 17
    end
    object Bevel6: TBevel
      Left = 249
      Top = 44
      Width = 18
      Height = 17
    end
    object chkIgnoreTenKey: TCheckBox
      Left = 128
      Top = 26
      Width = 97
      Height = 17
      Caption = #12486#12531#12461#12540#28961#35222
      TabOrder = 10
      OnClick = chkIgnoreTenKeyClick
    end
    object chkIgnoreKeyRepert: TCheckBox
      Left = 376
      Top = 23
      Width = 113
      Height = 16
      Caption = #12461#12540#12522#12500#12540#12488#28961#35222
      Checked = True
      State = cbChecked
      TabOrder = 7
      OnClick = chkIgnoreKeyRepertClick
    end
    object btnStart: TButton
      Left = 0
      Top = 0
      Width = 41
      Height = 25
      Caption = 'start'
      TabOrder = 0
      OnClick = btnStartClick
    end
    object btnStop: TButton
      Left = 40
      Top = 0
      Width = 41
      Height = 25
      Caption = 'stop'
      TabOrder = 1
      OnClick = btnStopClick
    end
    object Edit1: TEdit
      Left = 312
      Top = 1
      Width = 33
      Height = 20
      Ctl3D = True
      MaxLength = 4
      ParentCtl3D = False
      TabOrder = 4
      Text = '50'
      OnChange = Edit1Change
    end
    object btnClear: TButton
      Left = 80
      Top = 0
      Width = 41
      Height = 25
      Caption = 'clear'
      TabOrder = 2
      OnClick = btnClearClick
    end
    object chkchatterCancel: TCheckBox
      Left = 376
      Top = 3
      Width = 137
      Height = 16
      Caption = #12481#12515#12479#12522#12531#12464#12461#12515#12531#12475#12523
      Checked = True
      State = cbChecked
      TabOrder = 5
      OnClick = chkchatterCancelClick
    end
    object Edit2: TEdit
      Left = 312
      Top = 21
      Width = 33
      Height = 20
      Ctl3D = True
      MaxLength = 4
      ParentCtl3D = False
      TabOrder = 6
      Text = '20'
      OnChange = Edit2Change
    end
    object btnSound: TButton
      Left = 128
      Top = 0
      Width = 41
      Height = 25
      Caption = 'sound'
      TabOrder = 3
      OnClick = btnSoundClick
    end
    object chkSound: TCheckBox
      Left = 64
      Top = 27
      Width = 57
      Height = 17
      Caption = #35686#21578#38899
      TabOrder = 9
    end
    object chkAccuracy: TCheckBox
      Left = 376
      Top = 43
      Width = 129
      Height = 17
      Caption = #39640#31934#24230#12479#12452#12510#12540#20351#29992
      TabOrder = 15
      OnClick = chkAccuracyClick
    end
    object chkViewUp: TCheckBox
      Left = 0
      Top = 27
      Width = 65
      Height = 17
      Caption = 'UP'#30435#35222
      TabOrder = 8
      OnClick = chkViewUpClick
    end
    object edtLogMax: TEdit
      Left = 156
      Top = 41
      Width = 41
      Height = 20
      Ctl3D = True
      ParentCtl3D = False
      TabOrder = 13
      Text = '1000'
      OnChange = edtLogMaxChange
    end
    object chkLoging: TCheckBox
      Left = 0
      Top = 45
      Width = 49
      Height = 17
      Caption = #12525#12464
      TabOrder = 11
      OnClick = chkLogingClick
    end
    object chkLogChatter: TCheckBox
      Left = 49
      Top = 45
      Width = 97
      Height = 17
      Caption = #12481#12515#12479#12398#12415#35352#37682
      TabOrder = 12
      OnClick = chkLogingClick
    end
    object Edit3: TEdit
      Left = 312
      Top = 41
      Width = 33
      Height = 20
      Ctl3D = True
      MaxLength = 4
      ParentCtl3D = False
      TabOrder = 14
      Text = '8'
      OnChange = Edit3Change
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 65
    Width = 515
    Height = 188
    Align = alClient
    AutoSize = True
    BevelOuter = bvNone
    TabOrder = 1
    object ListBox2: TListBox
      Left = 260
      Top = 0
      Width = 255
      Height = 188
      TabStop = False
      AutoComplete = False
      Align = alClient
      ItemHeight = 12
      MultiSelect = True
      PopupMenu = PopupMenu3
      TabOrder = 1
      TabWidth = 30
      OnKeyPress = ListBox1KeyPress
    end
    object ListBox1: TListBox
      Left = 0
      Top = 0
      Width = 260
      Height = 188
      TabStop = False
      AutoComplete = False
      Align = alLeft
      ItemHeight = 12
      MultiSelect = True
      PopupMenu = PopupMenu2
      TabOrder = 0
      TabWidth = 30
      OnKeyPress = ListBox1KeyPress
    end
  end
  object ApplicationEvents1: TApplicationEvents
    OnMinimize = ApplicationEvents1Minimize
    Left = 96
    Top = 88
  end
  object PopupMenu1: TPopupMenu
    Left = 136
    Top = 88
    object N1: TMenuItem
      Caption = #26377#21177
      OnClick = N1Click
    end
    object Exit1: TMenuItem
      Caption = #32066#20102
      OnClick = Exit1Click
    end
  end
  object OpenDialog1: TOpenDialog
    Filter = #12469#12454#12531#12489' '#12501#12449#12452#12523' (*.wav)|*.wav'
    Options = [ofHideReadOnly, ofPathMustExist, ofEnableSizing]
    Left = 176
    Top = 88
  end
  object PopupMenu2: TPopupMenu
    Left = 96
    Top = 136
    object A1: TMenuItem
      Caption = #20840#12390#36984#25246'(&A)'
      OnClick = A1Click
    end
    object Copy1: TMenuItem
      Caption = #12467#12500#12540'(&C)'
      OnClick = Copy1Click
    end
  end
  object PopupMenu3: TPopupMenu
    Left = 320
    Top = 136
    object A2: TMenuItem
      Caption = #20840#12390#36984#25246'(&A)'
      OnClick = A2Click
    end
    object Copy2: TMenuItem
      Caption = #12467#12500#12540'(&C)'
      OnClick = Copy2Click
    end
  end
end
