unit umonitor;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, IdBaseComponent, IdComponent, IdRawBase, IdRawClient, IdIcmpClient,
  StdCtrls, IdTelnet, ComCtrls, ExtCtrls, cxGraphics, cxControls, cxLookAndFeels,
  cxLookAndFeelPainters, cxContainer, cxEdit, cxListView, qjson, QWorker,
  dxBarBuiltInMenu, cxPC, dxBar, cxClasses,qlog, cxPCdxBarPopupMenu,
  SyncObjs,CommCtrl, Menus;

type
  Tfrm_monitor = class(TForm)
    btn_start: TButton;
    Panel1: TPanel;
    Button4: TButton;
    btn_stop: TButton;
    cxPageControl: TcxPageControl;
    dxBarManager: TdxBarManager;
    dxBarManager1Bar1: TdxBar;
    dxBarBtn_monitor: TdxBarLargeButton;
    dxBarBtn_log: TdxBarLargeButton;
    dxBarBtn_set: TdxBarLargeButton;
    dxBarSubItem1: TdxBarSubItem;
    cxTabMonitor: TcxTabSheet;
    cxTabLog: TcxTabSheet;
    cxTabSet: TcxTabSheet;
    edt_monitor: TEdit;
    lbl: TLabel;
    ListView2: TListView;
    Timer2: TTimer;
    Timer_monitor: TTimer;
    procedure btn_startClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btn_stopClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure dxBarBtn_setClick(Sender: TObject);
    procedure dxBarBtn_logClick(Sender: TObject);
    procedure dxBarBtn_monitorClick(Sender: TObject);
    procedure ListView2Data(Sender: TObject; Item: TListItem);
    procedure Timer2Timer(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Timer_monitorTimer(Sender: TObject);
  private
    { Private declarations }
    FLogs: TStrings;       // 存放日志内容
    FAutoScroll: Boolean;  // 是否自动滚动
    FLogsIsDel: Boolean;   // 是否已经删除日志
    FLogRef: Integer;      // 状态计数器
    FLocker: TCriticalSection;
    FStart: Boolean;       // 是否已启动了工作线程
  public
    { Public declarations }
    function PingOnLine(s_ip: string): Boolean;
    function CheckPort(s_ip, s_port: string): Boolean;
    procedure LoadSetting();
    procedure DoWorkerPostJob(AJob: PQJob);
    procedure UpdListviwer(Ajson: TQJson);
    procedure DrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure Log(const Text: string);
    procedure DoWriteLog(Sender: TObject; const Log: string);
    procedure UpdJson(Ajson: TQJson);
  end;

var
  frm_monitor: Tfrm_monitor;
  Monitor_json: TQJson;

implementation
uses FoxmailMsgFrm;

{$R *.dfm}
procedure Tfrm_monitor.btn_startClick(Sender: TObject);
var
  AJson_content: TQJson;
  i : Integer;
begin
  //建立监控线程
  if not FStart then
  begin
    AJson_content := Monitor_json.ItemByName('ips');
    for i := 0 to AJson_content.Count - 1 do
    begin
      //Workers.Post(DoWorkerPostJob, 5000,StrToInt(edt_monitor.Text) * Q1Second, AJson_content[i], False, jdfFreeAsObject);
      Workers.At(DoWorkerPostJob, 5*Q1MillSecond, StrToInt(edt_monitor.Text) * Q1Second, AJson_content[i], False, jdfFreeAsObject);
    end;
  end;
  //启动监控
  Workers.EnableWorkers;
  edt_monitor.Enabled := False;
  btn_stop.Enabled := True;
  btn_start.Enabled := False;
end;

procedure Tfrm_monitor.btn_stopClick(Sender: TObject);
begin
  Workers.DisableWorkers;
  edt_monitor.Enabled := True;
  btn_stop.Enabled := False;
  btn_start.Enabled := True;
end;

procedure Tfrm_monitor.Button4Click(Sender: TObject);
var
  path_json: string;
  Ajson: TQJson;
begin
  Ajson := TQJson.Create;
  path_json := ExtractFileDir(ParamStr(0)) + '\monitor_test.json';
  Ajson.LoadFromFile(path_json);
  //UpdListviwer(Ajson);
  UpdJson(Ajson);
end;

procedure Tfrm_monitor.DoWorkerPostJob(AJob: PQJob);
var
  Ajson: TQJson;
  i: Integer;
  AJson_ports: TQJson;
  s_iphost: string;
  s_port : string;
  s_msg : string;
  b_mod : Boolean;
begin
  b_mod := False;
  Ajson := TQJson(AJob.Data);
  AJson_ports := Ajson.ItemByName('ports');
  s_iphost := Ajson.ItemByName('iphost').AsString;
  //测试ping连接
  if PingOnLine(s_iphost) then
    //主机ping上，则状态为1；否则状态为0
  begin
    Ajson.ItemByName('status').AsString := '正常';
    //写后台日志
    PostLog(llMessage,s_iphost + ' ' + '连接正常');
  end
  else
  begin
    Ajson.ItemByName('status').AsString := '异常';
    b_mod := True;
    s_msg := s_iphost + '连接异常';
    //写界面日志
    Log(s_msg);
    Sleep(10);
    //写后台日志
    PostLog(llWarning,s_iphost + ' ' + '连接异常');
  end;

  for i := 0 to AJson_ports.Count - 1 do
  begin
    //测试端口是否正常
    s_port := AJson_ports[i].ItemByName('port').AsString;
    s_msg := s_iphost + ':' + s_port;
    //Memo1.Lines.Add(s_msg);
    if CheckPort(s_iphost,s_port) then
    begin
      AJson_ports[i].ItemByName('status').AsString := '正常';
      PostLog(llMessage,s_msg + ' ' + ' 端口正常');
    end
    else
    begin
      AJson_ports[i].ItemByName('status').AsString := '异常';
      b_mod := True;
      s_msg := s_msg + '端口异常';
      //写界面日志
      Log(s_msg);
      Sleep(10);
      //写后台日志
      PostLog(llWarning,s_msg);
    end;
  end;
  //更新对应的listview
  UpdListviwer(Ajson);
  if b_mod then
    UpdJson(Ajson);
end;

procedure Tfrm_monitor.DoWriteLog(Sender: TObject; const Log: string);
var
  I: Integer;
begin
  if Assigned(FLogs) and (Assigned(Self)) then begin
    FLocker.Enter;
    // 大于10万行时，删除前面的1万行
    if FLogs.Count > 100000 then begin
      FLogsIsDel := True;
      for I := 10000 downto 0 do
        FLogs.Delete(I);
    end;
    // 添加当前日志内容
    FLogs.Add('[' + FormatDateTime('yyyy-mm-dd hh:mm:ss.zzz', Now) + '] ' + Log);
    FLocker.Leave;
  end;
end;

procedure Tfrm_monitor.DrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  s_ip : string;
begin
  s_ip := '服务器:' + Item.SubItems.Strings[0];
  if (SubItem <> 1) then
  begin
    if (Item.SubItems.Strings[SubItem-1] = '正常') then
      Sender.Canvas.Font.Color := clBlue
    else if (Item.SubItems.Strings[SubItem-1] = '异常') then
    begin
      Sender.Canvas.Font.Color := clRed;
    end;
  end;
end;

procedure Tfrm_monitor.dxBarBtn_logClick(Sender: TObject);
begin
  cxPageControl.ActivePage := cxTabLog;
end;

procedure Tfrm_monitor.dxBarBtn_monitorClick(Sender: TObject);
begin
  cxPageControl.ActivePage := cxTabMonitor;
end;

procedure Tfrm_monitor.dxBarBtn_setClick(Sender: TObject);
begin
  cxPageControl.ActivePage := cxTabSet;
end;

procedure Tfrm_monitor.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Workers.Clear(Self);
end;

procedure Tfrm_monitor.FormCreate(Sender: TObject);
var
  i: Integer;
  path_json: string;
  s_logfile: string;
begin
  FLogsIsDel := False;
  FLogRef := 0;
  FLogs := TStringList.Create();
  FLocker := TCriticalSection.Create;
  FAutoScroll := True;
  FStart := False;

  //设置日志路径
  s_logfile :=  ExtractFilePath(Application.ExeName) +'log/' + FormatDateTime('yyyy-mm-dd',Now());
  SetDefaultLogFile(s_logfile + '.log',1024 * 1024, False, true);

  //加载配置
  Monitor_json := TQJson.Create;
  path_json := ExtractFileDir(ParamStr(0)) + '\monitor.json';
  Monitor_json.LoadFromFile(path_json);
  LoadSetting;
end;


procedure Tfrm_monitor.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FLogs);
  FreeAndNil(FLocker);
end;

procedure Tfrm_monitor.FormShow(Sender: TObject);
begin
 {不在任务栏显示}
  SetWindowLong(Application.Handle, GWL_EXSTYLE, WS_EX_TOOLWINDOW);

  btn_stop.Enabled := False;
  btn_start.Enabled := True;
  cxPageControl.ActivePage := cxTabMonitor;
  Workers.DisableWorkers;
end;

procedure Tfrm_monitor.ListView2Data(Sender: TObject; Item: TListItem);
begin
  FLocker.Enter;
  if Assigned(FLogs) and (Item.Index < FLogs.Count) then
    Item.Caption := FLogs[Item.Index];
  FLocker.Leave;
end;

procedure Tfrm_monitor.LoadSetting;
var
  AJson_content: TQJson;
  AJson_ports: TQJson;
  i, j, k: Integer;
  surl: string;
  s_iphost: string;
  Alistview: TcxListView;
  Titem:Tlistitem;
begin
  AJson_content := Monitor_json.ItemByName('ips');
  for i := 0 to AJson_content.Count - 1 do
  begin
    s_iphost := AJson_content[i].ValueByName('iphost', '');
    //创建listview
    AListView := TcxListView.Create(Self);
    with AListView do
    begin
      Name := 'monitor_lst' + AJson_content[i].ItemByName('tag').AsString;
      Parent := Panel1;
      Left := 24;
      Top := 70 * i + 20;
      Height := 60;
      Width := 720;
      ViewStyle := vsreport;
      GridLines := False;
      Style.Font.Size := 15 ;
      Style.LookAndFeel.NativeStyle := False;
      Style.LookAndFeel.Kind := lfOffice11;
      OnCustomDrawSubItem := DrawSubItem;
      //增加列头
      Columns.Add;
      Columns.Items[0].Caption := '';
      Columns.Items[0].Width := 0;
      Columns.Items[0].Alignment := taCenter;

      Columns.Add;
      Columns.Items[1].Caption := '主机地址';
      Columns.Items[1].Width := 180;
      Columns.Items[1].Alignment := taCenter;

      Columns.Add;
      Columns.Items[2].Caption := 'ping状态';
      Columns.Items[2].Width := 100;
      Columns.Items[2].Alignment := taCenter;

      //增加端口列
      AJson_ports := AJson_content[i].ItemByName('ports');
      for j := 0 to AJson_ports.Count - 1 do
      begin
        Columns.Add;
        Columns.Items[3 + j].Caption := AJson_ports[j].ValueByName('port', '');
        Columns.Items[3 + j].Width := 80;
        Columns.Items[3 + j].Alignment := taCenter;
      end;
    end;

    //增加列
    Titem := AListView.Items.add;
    for k:= 0 to AListView.Columns.Count - 1 do
    begin
      if k = 0 then
        Titem.SubItems.Add(s_iphost)
      else
        Titem.SubItems.Add('');
    end;
    //Workers.Post(DoWorkerPostJob, 50000, AJson_content[i], False, jdfFreeAsObject);
  end;
end;

procedure Tfrm_monitor.Log(const Text: string);
begin
  if Assigned(Self) then
    DoWriteLog(Self, Text);
end;


function Tfrm_monitor.PingOnLine(s_ip:string): Boolean;
var
  aIdICMPClient: TIdICMPClient;
  Rec: Integer;
begin
  Result := False;
  aIdICMPClient := TIdIcmpClient.Create(nil);
  try
    aIdICMPClient.ReceiveTimeout := 2000;
    aIdICMPClient.Host := s_ip;
    try
      aIdICMPClient.Ping();
      //if (aIdICMPClient.ReplyStatus.FromIpAddress <> '0.0.0.0')
      //  and (aIdICMPClient.ReplyStatus.FromIpAddress <> '') then
      //if (aIdICMPClient.ReplyStatus.FromIpAddress = s_ip) then
      //连接成功后状态为rsEcho
      Rec:= aIdICMPClient.ReplyStatus.BytesReceived;
      if Rec > 0 then
        Result:= True
      else
        Result:= False;
      //if aIdICMPClient.ReplyStatus.ReplyStatusType = rsEcho then
      //  Result := True;
    except
      Result := False;
    end;
  finally
    aIdICMPClient.Free;
  end;
end;

procedure Tfrm_monitor.Timer2Timer(Sender: TObject);
begin
  if Assigned(ListView2) and (ListView2.HandleAllocated = True) then
  begin
    ListView_SetItemCountEx(ListView2.Handle, FLogs.Count,
      LVSICF_NOINVALIDATEALL or LVSICF_NOSCROLL); // 修改列表项的数量，并不改变滚动条位置
    if FAutoScroll then
      SendMessage(ListView2.Handle, WM_VSCROLL, SB_BOTTOM, 0);
    if FLogsIsDel then
    begin
      FLogsIsDel := False;
      ListView2.Invalidate;
    end;
  end;
end;

procedure Tfrm_monitor.Timer_monitorTimer(Sender: TObject);
var
  Ajson_content: TQJson;
  Ajson_content_ports: TQJson;
  s_ip, s_port: string;
  i,j: Integer;
begin
  Ajson_content := Monitor_json.ItemByName('ips');
  for i := 0 to Ajson_content.Count -1 do
  begin
     s_ip := Ajson_content[i].ItemByName('iphost').AsString;
     if (Ajson_content[i].ItemByName('status').AsString = '异常') then
     begin
        ShowError(s_ip + '连接异常');
     end;

     Ajson_content_ports := Ajson_content[i].ItemByName('ports');
     for j := 0 to Ajson_content_ports.Count -1  do
     begin
        s_port := Ajson_content_ports[j].ItemByName('port').AsString;
        if (Ajson_content_ports[j].ItemByName('status').AsString = '异常') then
        begin
          ShowError(s_ip + ' '+ s_port + '端口异常');
        end;
     end;
  end;
end;

procedure Tfrm_monitor.UpdJson(Ajson: TQJson);
var
  i,j,k : Integer;
  Ajson_content: TQJson;
  Ajson_ports: TQJson;
  Ajson_content_ports: TQJson;
begin
  Ajson_content := Monitor_json.ItemByName('ips');
  for i := 0 to Ajson_content.Count -1 do
  begin
    if (Ajson_content[i].ItemByName('tag').AsString = Ajson.ItemByName('tag').AsString) then
    begin
      Ajson_content[i].ItemByName('status').AsString := Ajson.ItemByName('status').AsString;

      Ajson_ports := Ajson.ItemByName('ports');
      Ajson_content_ports := Ajson_content[i].ItemByName('ports');
      for j := 0 to Ajson_ports.Count -1  do
      begin
        for k := 0 to Ajson_content_ports.Count -1  do
        begin
           if Ajson_content_ports[k].ItemByName('port').AsString
                =  Ajson_ports[j].ItemByName('port').AsString then
           begin
              Ajson_content_ports[k].ItemByName('status').AsString := Ajson_ports[j].ItemByName('status').AsString;
              Break
           end;
        end;
      end;
    end;
  end;
end;

procedure Tfrm_monitor.UpdListviwer(Ajson: TQJson);
var
  aListView: TcxListView;
  s_name: string;
  i, j: Integer;
  AJson_ports : TQJson;
begin
  AJson_ports := Ajson.ItemByName('ports');
  s_name := 'monitor_lst' + Ajson.ItemByName('tag').AsString;
  aListView := TcxListView(FindComponent(s_name));

  aListView.Items.BeginUpdate;
  i:= aListView.Columns.Count;
  try
    with aListView do
    begin
      //ping状态
      Items.Item[0].SubItems.Strings[1] := Ajson.ItemByName('status').AsString;
      for j := 0 to AJson_ports.Count - 1 do
      begin
        for i := 1 to Columns.Count - 1 do
        begin
          if (Columns.Items[i].DisplayName = AJson_ports[j].ItemByName('port').AsString) then
          begin
            Items.Item[0].SubItems.Strings[i-1] := AJson_ports[j].ItemByName('status').AsString;
            Break;
          end;
        end;
      end;
    end;
  finally
    aListView.Items.EndUpdate;
  end;
end;

function Tfrm_monitor.CheckPort(s_ip, s_port: string): Boolean;
var
  aIdTelnet : TIdTelnet;
begin
  Result := False;
  aIdTelnet := TIdTelnet.Create(nil);
  try
    aIdTelnet.Host := s_ip;
    aIdTelnet.Port := StrToInt(s_port);
    try
      aIdTelnet.ConnectTimeout := 1000;
      aIdTelnet.Connect();
    except
      Result := False;
    end;
    if aIdTelnet.Connected then
    begin
      aIdTelnet.Disconnect;
      Result := True;
    end;
  finally
    aIdTelnet.Free;
  end;
end;
end.

