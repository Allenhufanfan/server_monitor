program server_monitor;

uses
  Forms,
  umonitor in 'umonitor.pas' {frm_monitor},
  FoxmailMsgFrm in 'FoxmailMsgFrm.pas' {MsgForm};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(Tfrm_monitor, frm_monitor);
  Application.Run;
end.
