{*******************************************************************************
Dieser Sourcecode darf nicht ohne gültige Geheimhaltungsvereinbarung benutzt werden
und ohne gültigen Vertriebspartnervertrag weitergegeben oder kommerziell verwertet werden.
You have no permission to use this Source without valid NDA
and copy it without valid distribution partner agreement
Christian Ulrich
info@cu-tec.de
Created 28.02.2013
*******************************************************************************}
unit umeeting;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uBaseDbClasses, db, uBaseDbInterface,uIntfStrConsts,
  uBaseERPDBClasses,utask,LCLProc;
type
  TMeetings = class;
  TMeetingEntrys = class(TBaseDBDataSet)
  private
    FTempUsers : TUser;
    function GetownerName: string;
    function GetUserName: string;
  protected
    FMeeting : TMeetings;
  public
    constructor Create(aOwner: TComponent; DM: TComponent;
      aConnection: TComponent=nil; aMasterdata: TDataSet=nil); override;
    destructor Destroy; override;
    procedure Change; override;
    procedure SetDisplayLabels(aDataSet: TDataSet); override;
    procedure DefineFields(aDataSet : TDataSet);override;
    procedure FillDefaults(aDataSet: TDataSet); override;
    property OwnerName : string read GetownerName;
    property UserName : string read GetUserName;
  end;
  TMeetingUsers = class(TBaseDBDataSet)
  protected
    FMeeting : TMeetings;
  public
    procedure Change; override;
    procedure DefineFields(aDataSet : TDataSet);override;
    procedure SetDisplayLabels(aDataSet: TDataSet); override;
  end;
  TMeetingLinks = class(TLinks)
  public
    procedure FillDefaults(aDataSet : TDataSet);override;
  end;
  TMeetings = class(TBaseDbList,IPostableDataSet)
  private
    FEntrys: TMeetingEntrys;
    FLinks: TMeetingLinks;
    FUsers: TMeetingUsers;
  public
    constructor Create(aOwner: TComponent; DM: TComponent;
      aConnection: TComponent=nil; aMasterdata: TDataSet=nil); override;
    function CreateTable: Boolean; override;
    destructor Destroy; override;
    procedure CascadicPost; override;
    procedure CascadicCancel; override;
    function Post: TPostResult;
    procedure FillDefaults(aDataSet : TDataSet);override;
    function GetTextFieldName: string;override;
    function GetStatusFieldName : string;override;
    function GetNumberFieldName : string;override;
    procedure DefineFields(aDataSet : TDataSet);override;
    property Entrys : TMeetingEntrys read FEntrys;
    property Users : TMeetingUsers read FUsers;
    property Links : TMeetingLinks read FLinks;
  end;

implementation
uses uBaseApplication,uProjects,uData;
resourcestring
  strPresent                            = 'Anwesend';
procedure TMeetingLinks.FillDefaults(aDataSet: TDataSet);
begin
  inherited FillDefaults(aDataSet);
  aDataSet.FieldByName('RREF_ID').AsVariant:=(Parent as TMeetings).Id.AsVariant;
end;

procedure TMeetingUsers.Change;
begin
  inherited Change;
  if Assigned(FMeeting) then FMeeting.Change;
end;

procedure TMeetingUsers.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'MEETINGUSERS';
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('USER_ID',ftLargeint,0,False);
            Add('NAME',ftString,150,False);
            Add('IDCODE',ftString,4,False);
            Add('ACTIVE',ftString,1,False);
            Add('NOTE',ftString,200,False);
          end;
    end;
end;

procedure TMeetingUsers.SetDisplayLabels(aDataSet: TDataSet);
begin
  inherited SetDisplayLabels(aDataSet);
  SetDisplayLabelName(aDataSet,'ACTIVE',strPresent);
end;

constructor TMeetingEntrys.Create(aOwner: TComponent; DM: TComponent;
  aConnection: TComponent; aMasterdata: TDataSet);
begin
  inherited Create(aOwner, DM, aConnection, aMasterdata);
  with BaseApplication as IBaseDbInterface do
    begin
      with DataSet as IBaseDBFilter do
        begin
          Limit := 0;
          SortFields:='POSNO';
          SortDirection:=sdAscending;
        end;
    end;
  FTempUsers := TUser.Create(aOwner,DM);
end;

destructor TMeetingEntrys.Destroy;
begin
  FTempUsers.Destroy;
  inherited Destroy;
end;

procedure TMeetingEntrys.Change;
begin
  inherited Change;
  if Assigned(FMeeting) then FMeeting.Change;
end;

procedure TMeetingEntrys.SetDisplayLabels(aDataSet: TDataSet);
begin
  inherited SetDisplayLabels(aDataSet);
  SetDisplayLabelName(aDataSet,'USER',strWorker);
  SetDisplayLabelName(aDataSet,'OWNER',strResponsable);
end;

procedure TMeetingEntrys.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'MEETINGENTRYS';
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('POSNO',ftInteger,0,True);
            Add('DESC',ftMemo,0,False);
            Add('LINK',ftString,200,False);
            Add('OWNER',ftString,20,False);
            Add('USER',ftString,20,False);
            Add('DUEDATE',ftDateTime,0,False);
            Add('PARENT',ftLargeint,0,False);
            Add('HASCHILDS',ftString,1,False);
            Add('EXPANDED',ftString,1,False);
          end;
    end;
end;

procedure TMeetingEntrys.FillDefaults(aDataSet: TDataSet);
begin
  with aDataSet,BaseApplication as IBaseDBInterface do
    begin
      FieldByName('POSNO').AsInteger := (DataSet.RecordCount+1);
    end;
end;

function TMeetingEntrys.GetownerName: string;
begin
  Result := '';
  if FieldByName('OWNER').AsString='' then exit;
  if not FTempUsers.DataSet.Active then
    Data.SetFilter(FTempUsers,'',0);
  debugln(FieldByName('OWNER').AsString);
  if FTempUsers.DataSet.Locate('ACCOUNTNO',FieldByName('OWNER').AsString,[loCaseInsensitive]) then
    Result := FTempUsers.FieldByName('NAME').AsString;
end;

function TMeetingEntrys.GetUserName: string;
begin
  Result := '';
  if FieldByName('USER').AsString='' then exit;
  if not FTempUsers.DataSet.Active then
    Data.SetFilter(FTempUsers,'',0);
  debugln(FieldByName('USER').AsString);
  if FTempUsers.DataSet.Locate('ACCOUNTNO',FieldByName('USER').AsString,[loCaseInsensitive]) then
    Result := FTempUsers.FieldByName('NAME').AsString;
end;

constructor TMeetings.Create(aOwner: TComponent; DM: TComponent;
  aConnection: TComponent; aMasterdata: TDataSet);
begin
  inherited Create(aOwner, DM, aConnection, aMasterdata);
  FEntrys := TMeetingEntrys.Create(aOwner,DM,aConnection,DataSet);
  FEntrys.FMeeting := Self;
  FUsers := TMeetingUsers.Create(aOwner,DM,aConnection,DataSet);
  FUsers.FMeeting := Self;
  FLinks := TMeetingLinks.Create(Self,DM,aConnection);
end;

function TMeetings.CreateTable: Boolean;
begin
  Result:=inherited CreateTable;
  FEntrys.CreateTable;
  FUsers.CreateTable;
end;

destructor TMeetings.Destroy;
begin
  FreeAndNil(FEntrys);
  FreeAndNil(FUsers);
  inherited Destroy;
end;

procedure TMeetings.CascadicPost;
begin
  inherited CascadicPost;
  FEntrys.CascadicPost;
  FUsers.CascadicPost;
end;

procedure TMeetings.CascadicCancel;
begin
  inherited CascadicCancel;
  FEntrys.CascadicCancel;
  FUsers.CascadicCancel;
end;
function TMeetings.Post: TPostResult;
var
  ProjectLink: String = '';
  aProject: TProject;
  asl: TStringList;
  arec: LargeInt;
  Added : Boolean = False;
  aTasks: TTask;
begin
  Result := prFailed;
  if not Self.DataSet.FieldByName('DATE').IsNull then
    begin
      Result:=prAlreadyPosted;
      exit;
    end;
  with Entrys.DataSet do
    begin
      First;
      while not EOF do
        begin
          Added := False;
          if (copy(FieldByName('LINK').AsString,0,9) = 'PROJECTS@')
          or (copy(FieldByName('LINK').AsString,0,11) = 'PROJECTS.ID')
          then
            ProjectLink := FieldByName('LINK').AsString
          else if ProjectLink <> '' then
            begin
              aProject := TProject.Create(nil,DataModule,Connection);
              aProject.SelectFromLink(ProjectLink);
              aProject.Open;
              if aProject.Count>0 then
                begin
                  if FieldByName('OWNER').AsString <> '' then
                    begin //Task
                      aProject.Tasks.Open;
                      aProject.Tasks.Append;
                      asl := TStringList.Create;
                      asl.Text:=FieldByName('DESC').AsString;
                      if asl.Count>0 then
                        begin
                          aProject.Tasks.FieldByName('SUMMARY').AsString:=copy(asl[0],0,220);
                          if length(asl[0])>220 then
                            asl[0] := copy(asl[0],221,length(asl[0]))
                          else
                            asl.Delete(0);
                        end;
                      aProject.Tasks.FieldByName('DESC').AsString:=asl.Text;
                      asl.Free;
                      aProject.Tasks.FieldByName('OWNER').AsString:=FieldByName('OWNER').AsString;
                      aProject.Tasks.FieldByName('USER').AsVariant:=FieldByName('USER').AsVariant;
                      if FieldByName('USER').IsNull then
                        aProject.Tasks.FieldByName('USER').AsVariant:=FieldByName('OWNER').AsVariant;
                      if not FieldByName('DUEDATE').IsNull then
                        aProject.Tasks.FieldByName('DUEDATE').AsVariant:=FieldByName('DUEDATE').AsVariant;
                      aProject.Tasks.DataSet.Post;
                      arec := aProject.Tasks.GetBookmark;
                      aProject.Tasks.DataSet.Refresh;
                      aProject.Tasks.GotoBookmark(arec);
                      if not Entrys.CanEdit then
                        Entrys.DataSet.Edit;
                      Entrys.FieldByName('LINK').AsString:=Data.BuildLink(aProject.Tasks.DataSet);
                      if Entrys.CanEdit then
                        Entrys.DataSet.Post;
                      Added := True;
                    end
                  else //History
                    begin
                      aProject.History.AddItem(Data.Users.DataSet,FieldByName('DESC').AsString,Data.BuildLink(DataSet),Self.DataSet.FieldByName('NAME').AsString,nil,ACICON_USEREDITED,'',True,True);
                      Added := True;
                    end;
                end;
              aProject.Free;
              if (not Added) and (FieldByName('OWNER').AsString <> '') then
                begin //Task
                  aTasks := TTask.Create(nil,Data);
                  aTasks.Append;
                  asl := TStringList.Create;
                  asl.Text:=FieldByName('DESC').AsString;
                  if asl.Count>0 then
                    begin
                      aTasks.FieldByName('SUMMARY').AsString:=asl[0];
                      asl.Delete(0);
                    end;
                  aTasks.FieldByName('DESC').AsString:=asl.Text;
                  asl.Free;
                  aTasks.FieldByName('OWNER').AsString:=FieldByName('OWNER').AsString;
                  aTasks.FieldByName('USER').AsVariant:=FieldByName('USER').AsVariant;
                  if FieldByName('USER').IsNull then
                    aTasks.FieldByName('USER').AsVariant:=FieldByName('OWNER').AsVariant;
                  if not FieldByName('DUEDATE').IsNull then
                    aTasks.FieldByName('DUEDATE').AsVariant:=FieldByName('DUEDATE').AsVariant;
                  aTasks.DataSet.Post;
                  arec := aTasks.GetBookmark;
                  aTasks.DataSet.Refresh;
                  aTasks.GotoBookmark(arec);
                  if not Entrys.CanEdit then
                    Entrys.DataSet.Edit;
                  Entrys.FieldByName('LINK').AsString:=Data.BuildLink(aTasks.DataSet);
                  if Entrys.CanEdit then
                    Entrys.DataSet.Post;
                  Added := True;
                end
            end;
          Next;
        end;
      if not Self.CanEdit then
        Self.DataSet.Edit;
      Self.DataSet.FieldByName('DATE').AsDateTime:=Now();
      Self.CascadicPost;
      Result:=prSuccess;
    end;
end;
procedure TMeetings.FillDefaults(aDataSet: TDataSet);
begin
  with aDataSet,BaseApplication as IBaseDBInterface do
    begin
      FieldByName('STATUS').AsString := 'P';
      FieldByName('STARTTIME').AsDateTime:=Now();
    end;
end;

function TMeetings.GetTextFieldName: string;
begin
  Result := 'NAME';
end;

function TMeetings.GetStatusFieldName: string;
begin
  Result:='STATUS';
end;

function TMeetings.GetNumberFieldName: string;
begin
  Result := 'SQL_ID';
end;

procedure TMeetings.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'MEETINGS';
      TableCaption:=strMeetings;
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('NAME',ftString,200,False);
            Add('STATUS',ftString,4,True);
            Add('DESC',ftMemo,0,False);
            Add('DATE',ftDateTime,0,False);
            Add('STARTTIME',ftDateTime,0,False);
            Add('ENDTIME',ftDateTime,0,False);
            Add('CREATEDBY',ftString,4,False);
          end;
    end;
end;

end.

