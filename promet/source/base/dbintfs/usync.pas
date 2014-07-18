{*******************************************************************************
  Copyright (C) Christian Ulrich info@cu-tec.de

  This source is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation; either version 2 of the License, or commercial alternative
  contact us for more information

  This code is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  A copy of the GNU General Public License is available on the World Wide Web
  at <http://www.gnu.org/copyleft/gpl.html>. You can also obtain it by writing
  to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
  MA 02111-1307, USA.

info@cu-tec.de
*******************************************************************************}
unit usync;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, uBaseDbClasses, db, uBaseDbInterface,uBaseApplication,
  fpjson,fpsqltree,LConvEncoding,synautil;
type
  TSyncTable = class(TBaseDBDataSet)
  public
    constructor Create(aOwner : TComponent;DM : TComponent;aConnection : TComponent = nil;aMasterdata : TDataSet = nil);override;
    procedure DefineFields(aDataSet : TDataSet);override;
  end;
  TSyncDB = class(TBaseDBDataSet)
  private
    FTables: TSyncTable;
  public
    constructor Create(aOwner : TComponent;DM : TComponent;aConnection : TComponent = nil;aMasterdata : TDataSet = nil);override;
    destructor Destroy;override;
    procedure DefineFields(aDataSet : TDataSet);override;
    function CreateTable : Boolean;override;
    property Tables : TSyncTable read FTables;
  end;

  { TSyncItems }

  TSyncItems = class(TBaseDBDataSet)
  private
    function GetLocalID: TField;
    function GetRemoteID: TField;
    function GetSyncTime: TField;
    function GetType: TField;
  public
    procedure DefineFields(aDataSet : TDataSet);override;
    property SyncTime : TField read GetSyncTime;
    property LocalID : TField read GetLocalID;
    property RemoteID : TField read GetRemoteID;
    property Typ : TField read GetType;
    procedure SelectByReference(aID : Variant);
    procedure SelectByRemoteReference(aID : Variant);
    //Routine to sync 2 Dataset with Json Data, must be called trice in first Step
    //the Routine get the Remote JSON data and return the New/Changed Data from internal DataSet
    //in Second Setp the Routine gets called with Notify=True and gets the same Data that it has Send with external_id set
    //To store the external_id and Changed Date
    function SyncDataSet(aInternal : TBaseDBDataset;aExternal : TJSONData;SyncType : string;Notify : Boolean = False) : TJSONArray;
    function GetField(aObject: TJSONData; aName: string): TJSONData;
    function LastSync(SyncType,SyncTable : string) : TDateTime;
  end;
  TSyncStamps = class(TBaseDbDataSet)
    procedure DefineFields(aDataSet: TDataSet); override;
  end;
procedure FieldsToJSON(AFields: TFields; AJSON: TJSONObject; const ADateAsString: Boolean; bFields: TSQLElementList = nil);
function JSONToFields(AJSON: TJSONObject; AFields: TFields; const ADateAsString: Boolean; const AddFields: Boolean = True) : Boolean;
resourcestring
  strSynchedOut                                      = 'Synchronisation ausgehend %s';
  strSynchedIn                                       = 'Synchronisation eingehend %s';
  strSyncNewRecord                                   = 'neuer Datensatz';
implementation
uses Variants;
procedure FieldsToJSON(AFields: TFields; AJSON: TJSONObject;
  const ADateAsString: Boolean; bFields: TSQLElementList);
var
  I: Integer;
  VField: TField;
  VFieldName: ShortString;
  function FindField(aName : string) : Boolean;
  var
    a: Integer;
    aFName: string;
    aF: TSQLElement;
  begin
    Result := False;
    if not Assigned(aFields) then
      begin
        Result := True;
        exit;
      end;
    if Assigned(bFields) then
      begin
        for a := 0 to bFields.Count-1 do
          begin
            aF := bFields[a];
            if af is TSQLSelectAsterisk then
              begin
                aFName:='*';
                Result := True;
                exit;
              end
            else if af is TSQLSelectField then
              aFName := aF.GetAsSQL([],0);
            if (UpperCase(aName) = Uppercase(aFName))
            then
              begin
                if aName <> '*' then
                  VFieldName:=aFName;
                Result := True;
                exit;
              end;
          end;
      end
    else
      begin
        Result := True;
        exit;
      end;
  end;
begin
  for I := 0 to Pred(AFields.Count) do
  begin
    VField := AFields[I];
    VFieldName := VField.FieldName;
    if (FindField(VFieldName) or (FindField('*')))
    and (not VField.IsNull)
    then
      begin
        if VField.DataType = ftBoolean then
          AJSON.Add(lowercase(VFieldName), VField.AsBoolean)
        else if VField.DataType = ftDateTime then
          begin
            if ADateAsString then
              AJSON.Add(lowercase(VFieldName), Rfc822DateTime(VField.AsDateTime))
            else
              AJSON.Add(lowercase(VFieldName), VField.AsFloat);
          end
        else if VField.DataType = ftFloat then
          AJSON.Add(lowercase(VFieldName), VField.AsFloat)
        else if (VField.DataType = ftInteger) or (VField.DataType = ftLargeint) then
          AJSON.Add(lowercase(VFieldName), VField.AsInteger)
        else
          AJSON.Add(lowercase(VFieldName), ConvertEncoding(VField.AsString,guessEncoding(VField.AsString),EncodingUTF8))
      end;
  end;
end;
function JSONToFields(AJSON: TJSONObject; AFields: TFields;
  const ADateAsString: Boolean; const AddFields: Boolean): Boolean;
var
  I: Integer;
  VName: string;
  VField: TField;
  VData: TJSONData;
  VdataStr: TJSONStringType;
begin
  Result := False;
  for I := 0 to Pred(AJSON.Count) do
  begin
    VName := AJSON.Names[I];
    VField := AFields.FindField(uppercase(VName));
    if not Assigned(VField) then
      Continue;
    VData := AJSON.Items[I];
    if VData is TJSONArray then Continue;
    if VData is TJSONObject then Continue;
    VField.Clear;
    if VData.IsNull then
      Exit;
    VdataStr := VData.AsString;
    if (VField is TStringField) or (VField is TBinaryField) or
      (VField is TBlobField) or (VField is TVariantField)
    then
      begin
        if VData.JSONType=jtBoolean then
          begin
            if VData.AsBoolean then
              begin
                if VField.AsString <> 'Y' then
                  begin
                    VField.AsString := 'Y';
                    Result := True;
                  end;
              end
            else
              begin
                if VField.AsString <> 'N' then
                  begin
                    VField.AsString := 'N';
                    Result := True;
                  end;
              end;
          end
        else if VField.AsString <> VdataStr then
          begin
            VField.AsString := VdataStr;
            Result := True;
          end;
      end
    else if (VField is TLongintField) or (VField is TLargeintField) then
      begin
        if VField.AsInteger <> VData.AsInteger then
          begin
            VField.AsInteger := VData.AsInteger;
            Result := True;
          end;
      end
    else if (VField is TFloatField) or (VField is TBCDField) or
      (VField is TFMTBCDField) then
        begin
          if VField.AsFloat <> VData.AsFloat then
            begin
              VField.AsFloat := VData.AsFloat;
              Result := True;
            end;
        end
    else if VField is TBooleanField then
      begin
        if VField.AsBoolean <> VData.AsBoolean then
          begin
            VField.AsBoolean := VData.AsBoolean;
            Result := True;
          end;
      end
    else if VField is TDateTimeField then
      begin
        if ADateAsString then
          begin
            if VField.AsDateTime <> DecodeRfcDateTime(VdataStr) then
              begin
                VField.AsDateTime := DecodeRfcDateTime(VdataStr);
                Result := True;
              end;
          end
        else
          begin
            if VField.AsDateTime <> VData.AsFloat then
              begin
                VField.AsDateTime := VData.AsFloat;
                Result := True;
              end;
          end;
      end;
  end;
end;

{ TSyncStamps }

procedure TSyncStamps.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'SYNCSTAMPS';
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('FROM',ftString,30,True);
            Add('NAME',ftString,30,True);
            Add('LTIMESTAMP',ftDateTime,0,False);
          end;
    end;
end;

function TSyncItems.GetLocalID: TField;
begin
  Result := FieldByName('LOCAL_ID');
end;

function TSyncItems.GetRemoteID: TField;
begin
  Result := FieldByName('REMOTE_ID');
end;

function TSyncItems.GetSyncTime: TField;
begin
  Result := FieldByName('SYNC_TIME');
end;

function TSyncItems.GetType: TField;
begin
  Result := FieldByName('SYNCTYPE');
end;

procedure TSyncItems.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'SYNCITEMS';
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('SYNCTYPE',ftString,100,True);
            Add('SYNCTABLE',ftString,100,False);
            Add('LOCAL_ID',ftLargeInt,0,True);
            Add('REMOTE_ID',ftString,200,True);
            Add('USER_ID',ftLargeint,0,False);
            Add('REMOTE_TIME',ftDateTime,0,False);
            Add('SYNC_TIME',ftDateTime,0,False);
            Add('ERROR',ftString,1,False);
          end;
    end;
end;

procedure TSyncItems.SelectByReference(aID: Variant);
var
  aField: String = '';
begin
  with BaseApplication as IBaseDBInterface do
    with DataSet as IBaseDBFilter do
      begin
        aField := 'LOCAL_ID';
        if (VarIsNumeric(aID) and (aID = 0))
        or (VarIsStr(aID) and (aID = ''))
        or (aID = Null)  then
          begin
            with DataSet as IBaseManageDb do
              Filter := Data.QuoteField(TableName)+'.'+Data.QuoteField(aField)+'='+Data.QuoteValue('0');
          end
        else
          begin
            with DataSet as IBaseManageDb do
              Filter := Data.QuoteField(TableName)+'.'+Data.QuoteField(aField)+'='+Data.QuoteValue(Format('%d',[Int64(aID)]));
          end;
      end;
end;

procedure TSyncItems.SelectByRemoteReference(aID: Variant);
var
  aField: String = '';
begin
  with BaseApplication as IBaseDBInterface do
    with DataSet as IBaseDBFilter do
      begin
        Filter := Data.QuoteField('REMOTE_ID')+'='+Data.QuoteValue(aID);
      end;
end;

function TSyncItems.GetField(aObject : TJSONData;aName : string) : TJSONData;
begin
  Result := nil;
  if aObject is TJSONObject then
    begin
      if (not Assigned(result)) and (TJSONObject(aObject).IndexOfName(aName,True) > -1) then
        Result := aObject.Items[TJSONObject(aObject).IndexOfName(aName,True)];
    end;
end;
{
You have to push an JSON List with Data in aExternal with EXTERNAL_ID,TIMESTAMPD or TIMESTAMP filled
and get an List with changed Data since Lastsync with EXTERNAL_ID and TIMESTAMPD
}
function TSyncItems.SyncDataSet(aInternal: TBaseDBDataset;
  aExternal: TJSONData; SyncType: string; Notify: Boolean): TJSONArray;
var
  aLastSync: TDateTime = 0;
  VJSON: TJSONObject;
  aObj: TJSONObject;
  aTime: TJSONData;
  DoSync: Boolean;
  i: Integer;
  aID: TJSONData;
  aSyncTime: TDateTime;
  tmp: TJSONStringType;
  Hist : IBaseHistory;
  aSQLID: TJSONData;
  aSyncFilter: String;
  aLastSyncedItemTime: TDateTime;
  tmp1: String;
  aIntFilter: String;
  aOtherUserItems: TSyncItems;
  function RoundToSecond(aDate : TDateTime) : TDateTime;
  begin
    Result := Round(aDate * SecsPerDay) / SecsPerDay;
  end;

begin
  //First Step, of sync
  if not Notify then
    begin
      Result := TJSONArray.Create;
      //Find Last Sync Time
      aSyncFilter := TBaseDBModule(DataModule).QuoteField('SYNCTYPE')+'='+TBaseDBModule(DataModule).QuoteValue(SyncType)+' AND '+TBaseDBModule(DataModule).QuoteField('USER_ID')+'='+TBaseDBModule(DataModule).QuoteValue(TBaseDBModule(DataModule).Users.ID.AsString)+' AND '+TBaseDBModule(DataModule).QuoteField('SYNCTABLE')+'='+TBaseDBModule(DataModule).QuoteValue(aInternal.TableName);
      Filter(aSyncFilter,0,'SYNC_TIME');
      Last;
      //add all items to aInternal that are synced ever
      aIntFilter := aInternal.ActualFilter;
      if TBaseDBModule(DataModule).IsSQLDB then
        aInternal.ActualFilter:='('+aIntFilter+') OR ('+TBaseDBModule(DataModule).QuoteField('SQL_ID')+' IN (SELECT '+TBaseDBModule(DataModule).QuoteField('LOCAL_ID')+' FROM '+TBaseDBModule(DataModule).QuoteField(TableName)+' where '+TBaseDBModule(DataModule).QuoteField('SYNCTYPE')+'='+TBaseDBModule(DataModule).QuoteValue(SyncType)+' AND '+TBaseDBModule(DataModule).QuoteField('USER_ID')+'='+TBaseDBModule(DataModule).QuoteValue(TBaseDBModule(DataModule).Users.ID.AsString)+'))';
      aInternal.Open;
      aLastSync := SyncTime.AsDateTime;
      //debugln('********** Sync started, '+DateTimeToStr(aLastSync)+' last sync, Filter:'+aSyncFilter);
      //Sync internal items that are newer than last sync out
      aInternal.First;
      while not aInternal.EOF do
        begin
          DoSync := True;
          //check if newer version of row is in aExternal
          aTime := nil;
          aID := nil;
          for i := 0 to aExternal.Count-1 do
            begin
              aObj := aExternal.Items[i] as TJSONObject;
              aID := GetField(aObj,'sql_id');
              aTime := GetField(aObj,'timestampd');
              if not Assigned(aTime) then
                aTime := GetField(aObj,'timestamp');
              if Assigned(aID) and Assigned(aTime)
              and (not aInternal.Id.IsNull)
              and (aID.AsString=IntToStr(Int64(aInternal.Id.AsVariant)))
              and (DecodeRfcDateTime(aTime.AsString)>aInternal.TimeStamp.AsDateTime)
              then
                DoSync := False;
            end;
          if DoSync then
            begin
              SelectByReference(aInternal.Id.AsVariant);
              Open;
              if Count = 0 then
                begin
                  Insert
                end
              else Edit;
              DoSync := (aInternal.TimeStamp.AsDateTime>SyncTime.AsDateTime) or (State=dsInsert); //sync only when Chnged ot New
              if DoSync then
                begin
                  VJSON := TJSONObject.Create;
                  FieldsToJSON(aInternal.DataSet.Fields, VJSON, True);
                  if RemoteID.AsString <> '' then
                    VJSON.Add('external_id',RemoteID.AsString)
                  else if State=dsInsert then
                    Cancel;  //wir warten bis der 2. sync aufruf kommt und erstellen dann unseren syncitem
                  Result.Add(VJSON);
                  //if BaseApplication.HasOption('debug') then
                  //  debugln('Changed Object:'+VJSON.AsJSON);
                end
              else Cancel;
            end;
          aInternal.Next;
        end;
      //Sync external Items that are newer than internal in
      for i := 0 to aExternal.Count-1 do
        begin
          aObj := aExternal.Items[i] as TJSONObject;
          aID := GetField(aObj,'external_id');
          aTime := GetField(aObj,'timestampd');
          if not Assigned(aTime) then
            aTime := GetField(aObj,'timestamp');
          tmp := aTime.AsString;
          aSyncTime :=  DecodeRfcDateTime(tmp);
          aLastSyncedItemTime := SyncTime.AsDateTime;
          tmp := DateTimeToStr(aSyncTime);
          tmp1 := DateTimeToStr(aLastSyncedItemTime);
          if Assigned(aID) and Assigned(aTime) then
            begin
              DoSync:=True;
              //Get our Sync Item or insert one
              SelectByRemoteReference(aID.AsString);
              Open;
              if Count = 0 then
                begin
                  aSQLID := GetField(aObj,'sql_id');
                  if Assigned(aSQLID) then
                    begin
                      SelectByReference(aSQLID.Value);
                      Open;
                      if Count = 0 then
                        begin
                          //check if same item has another user now ...
                          aOtherUserItems := TSyncItems.Create(nil,DataModule,Connection);
                          aOtherUserItems.SelectByRemoteReference(aID.AsString);
                          aOtherUserItems.Open;
                          //if not insert
                          if aOtherUserItems.Count=0 then
                            Insert
                          else DoSync:=False;
                          aOtherUserItems.Free;
                        end
                      else Edit;
                      if CanEdit then
                        LocalID.AsVariant:=aSQLID.Value;
                      if State = dsEdit then
                        Post;
                    end
                  else
                    Insert;
                end
              else Edit;
              //sync only when Chnged ot New
              if SyncTime.IsNull then
                DoSync := DoSync or ((aSyncTime>aLastSyncedItemTime) or (State=dsInsert))
              else
                DoSync := DoSync or ((aSyncTime>SyncTime.AsDateTime) or (State=dsInsert));
              if DoSync then
                begin
                  //if BaseApplication.HasOption('debug') then
                  //  debugln('Ext Changed Object:'+aObj.AsJSON);
                  aInternal.Select(LocalID.AsVariant);
                  aInternal.Open;
                  if aInternal.Count=0 then
                    aInternal.Insert
                  else aInternal.Edit;
                  if JSONToFields(aObj,aInternal.DataSet.Fields,True) then
                    begin
                      try
                        aInternal.Post;
                        if Supports(aInternal, IBaseHistory, Hist) then
                          begin
                            if aInternal.State=dsInsert then
                              begin //neuer externer Datensatz
                                Hist.History.AddItem(aInternal.DataSet,Format(strSynchedIn,[strSyncNewRecord]));
                                //debugln(aID.AsString+':'+Format(strSynchedIn,[strSyncNewRecord]));
                              end
                            else if (aSyncTime>SyncTime.AsDateTime) then
                              begin
                                if SyncTime.AsDateTime>0 then //geänderter Datensatz
                                  begin
                                    Hist.History.AddItem(aInternal.DataSet,Format(strSynchedIn,['Remote '+DateTimeToStr(RoundToSecond(aSyncTime))+' > Sync '+DateTimeToStr(RoundToSecond(SyncTime.AsDateTime))]));
                                    //debugln(aID.AsString+':'+Format(strSynchedIn,['Remote '+DateTimeToStr(RoundToSecond(aSyncTime))+' > Sync '+DateTimeToStr(RoundToSecond(SyncTime.AsDateTime))]));
                                  end
                                else
                                  begin
                                    Hist.History.AddItem(aInternal.DataSet,Format(strSynchedin,[strSyncNewRecord]));
                                    //debugln(aID.AsString+':'+Format(strSynchedOut,[strSyncNewRecord]));
                                  end;
                              end
                            else
                              begin
                                Hist.History.AddItem(aInternal.DataSet,Format(strSynchedIn,['Remote:'+DateTimeToStr(RoundToSecond(DecodeRfcDateTime(aTime.AsString)))+' Internal:'+DateTimeToStr(RoundToSecond(aInternal.TimeStamp.AsDateTime))+' Sync:'+DateTimeToStr(RoundToSecond(SyncTime.AsDateTime))]));
                                //debugln(aID.AsString+':'+Format(strSynchedIn,['Remote:'+DateTimeToStr(RoundToSecond(DecodeRfcDateTime(aTime.AsString)))+' Internal:'+DateTimeToStr(RoundToSecond(aInternal.TimeStamp.AsDateTime))+' Sync:'+DateTimeToStr(RoundToSecond(SyncTime.AsDateTime))]));
                              end;
                          end;
                      except
                        FieldByName('ERROR').AsString:='Y';
                      end;
                    end;
                  if LocalID.IsNull then
                    LocalID.AsVariant:=aInternal.Id.AsVariant;
                  if LocalID.AsString <> '' then
                    begin
                      if aObj.IndexOfName('sql_id')>-1 then
                        aObj.Elements['sql_id'].AsString:=LocalID.AsString
                      else
                        aObj.Add('sql_id',LocalID.AsString);
                    end;
                  if Assigned(aTime) then
                    FieldByName('REMOTE_TIME').AsDateTime:=DecodeRfcDateTime(aTime.AsString);
                  if FieldByName('SYNCTABLE').IsNull then
                    FieldByName('SYNCTABLE').AsString:=aInternal.TableName;
                  if FieldByName('USER_ID').IsNull then
                    FieldByName('USER_ID').AsString:=TBaseDBModule(DataModule).Users.ID.AsString;
                  RemoteID.AsVariant:=aID.AsString;
                  Typ.AsString:=SyncType;
                  if Canedit then
                    begin
                      SyncTime.AsDateTime:=Now();
                      Post;
                    end;
                end;
            end;
        end;
    end
  else
  //Second Step, of sync Notify about new ID´s and successful sync
    begin
      //debugln('********** Sync 2nd Step');
      for i := 0 to aExternal.Count-1 do
        begin
          DoSync:=True;
          aObj := aExternal.Items[i] as TJSONObject;
          //if BaseApplication.HasOption('debug') then
          //  debugln('Ext Notified Object:'+aObj.AsJSON);
          aID := GetField(aObj,'external_id');
          aTime := GetField(aObj,'timestampd');
          if not Assigned(aTime) then
            aTime := GetField(aObj,'timestamp');
          tmp := aTime.AsString;
          aSyncTime :=  DecodeRfcDateTime(tmp);
          aLastSyncedItemTime := SyncTime.AsDateTime;
          tmp := DateTimeToStr(aSyncTime);
          tmp1 := DateTimeToStr(aLastSyncedItemTime);
          if Assigned(aID) and Assigned(aTime) then
            begin
              aSQLID := GetField(aObj,'sql_id');
              if Assigned(aSQLID) then
                begin
                  SelectByReference(aSQLID.Value);
                  Open;
                end;
              //Get our Sync Item or insert one
              if Count = 0 then
                begin
                  SelectByRemoteReference(aID.AsString);
                  Open;
                  if Count = 0 then
                    begin
                      aSQLID := GetField(aObj,'sql_id');
                      if Assigned(aSQLID) then
                        begin
                          SelectByReference(aSQLID.Value);
                          Open;
                          if Count = 0 then
                            begin
                              //check if same item has another user now ...
                              aOtherUserItems := TSyncItems.Create(nil,DataModule,Connection);
                              aOtherUserItems.SelectByRemoteReference(aID.AsString);
                              aOtherUserItems.Open;
                              //if not insert
                              if aOtherUserItems.Count=0 then
                                Insert
                              else DoSync:=False;
                              aOtherUserItems.Free;
                            end
                          else Edit;
                          LocalID.AsVariant:=aSQLID.Value;
                          if State = dsEdit then
                            Post;
                        end
                      else
                        Insert;
                    end
                  else Edit;
                end
              else Edit;
              if DoSync then
                begin
                  RemoteID.AsVariant:=aID.AsString;
                  aInternal.Select(LocalID.AsVariant);
                  aInternal.Open;
                  if aInternal.Count>0 then
                    begin
                      if CanEdit then
                        begin
                          if Supports(aInternal, IBaseHistory, Hist) then
                            begin
                              if State=dsInsert then
                                begin
                                  Hist.History.AddItem(aInternal.DataSet,Format(strSynchedOut,[strSyncNewRecord]));
                                  //debugln(aInternal.Id.AsString+':'+Format(strSynchedOut,[strSyncNewRecord]));
                                end
                              else if (aInternal.TimeStamp.AsDateTime>SyncTime.AsDateTime) then
                                begin
                                  Hist.History.AddItem(aInternal.DataSet,Format(strSynchedOut,['Internal '+DateTimeToStr(RoundToSecond(aInternal.TimeStamp.AsDateTime))+' > Sync '+DateTimeToStr(RoundToSecond(SyncTime.AsDateTime))]));
                                  //debugln(aInternal.Id.AsString+':'+Format(strSynchedOut,['Internal '+DateTimeToStr(RoundToSecond(aInternal.TimeStamp.AsDateTime))+' > Sync '+DateTimeToStr(RoundToSecond(SyncTime.AsDateTime))]));
                                end
                              else
                                begin
                                  Hist.History.AddItem(aInternal.DataSet,Format(strSynchedOut,['Remote:'+DateTimeToStr(RoundToSecond(DecodeRfcDateTime(aTime.AsString)))+' Internal:'+DateTimeToStr(RoundToSecond(aInternal.TimeStamp.AsDateTime))+' Sync:'+DateTimeToStr(RoundToSecond(SyncTime.AsDateTime))]));
                                  //debugln(aInternal.Id.AsString+':'+Format(strSynchedOut,['Remote:'+DateTimeToStr(RoundToSecond(DecodeRfcDateTime(aTime.AsString)))+' Internal:'+DateTimeToStr(RoundToSecond(aInternal.TimeStamp.AsDateTime))+' Sync:'+DateTimeToStr(RoundToSecond(SyncTime.AsDateTime))]));
                                end;
                            end;
                          LocalID.AsVariant:=aInternal.Id.AsVariant;
                          Typ.AsString:=SyncType;
                          if FieldByName('SYNCTABLE').IsNull then
                            FieldByName('SYNCTABLE').AsString:=aInternal.TableName;
                          if FieldByName('USER_ID').IsNull then
                            FieldByName('USER_ID').AsString:=TBaseDBModule(DataModule).Users.ID.AsString;
                          SyncTime.AsDateTime:=Now();
                          Post;
                        end;
                    end;
                end; //else external item is changed to another user, should we delete it ????
            end;
        end;
    end;
end;

function TSyncItems.LastSync(SyncType, SyncTable: string): TDateTime;
begin
  Filter(TBaseDBModule(DataModule).QuoteField('SYNCTYPE')+'='+TBaseDBModule(DataModule).QuoteValue(SyncType)+' AND '+TBaseDBModule(DataModule).QuoteField('SYNCTABLE')+'='+TBaseDBModule(DataModule).QuoteValue(SyncTable),0,'SYNC_TIME');
  Last;
  Result := SyncTime.AsDateTime;
end;

constructor TSyncTable.Create(aOwner: TComponent; DM: TComponent;
  aConnection: TComponent; aMasterdata: TDataSet);
begin
  inherited Create(aOwner, DM, aConnection, aMasterdata);
  with BaseApplication as IBaseDbInterface do
    begin
      with DataSet as IBaseDBFilter do
        begin
          SortFields := 'SQL_ID';
          SortDirection := sdAscending;
        end;
    end;
end;
procedure TSyncTable.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'SYNCTABLE';
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('ACTIVE',ftString,1,False);
            Add('ACTIVEOUT',ftString,1,False);
            Add('NAME',ftString,30,True);
            Add('LTIMESTAMP',ftDateTime,0,False);
            Add('FILTERIN',ftMemo,0,False);
            Add('FILTEROUT',ftMemo,0,False);
          end;
    end;
end;
constructor TSyncDB.Create(aOwner: TComponent; DM: TComponent;
  aConnection: TComponent; aMasterdata: TDataSet);
begin
  inherited Create(aOwner, DM, aConnection, aMasterdata);
  FTables := TSyncTable.Create(Self,DM,aConnection,DataSet);
  with BaseApplication as IBaseDbInterface do
    begin
      with DataSet as IBaseDBFilter do
        begin
          BaseSortFields := 'SQL_ID';
          SortFields := 'SQL_ID';
          SortDirection := sdAscending;
        end;
    end;
end;
destructor TSyncDB.Destroy;
begin
  FTables.Destroy;
  inherited Destroy;
end;
procedure TSyncDB.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'SYNCDB';
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('NAME',ftString,30,True);
            Add('ACTIVE',ftString,1,False);
            Add('PROPERTIES',ftMemo,0,False);
            Add('SYNCOFFS',ftInteger,0,False);
            Add('INPROGRESS',ftString,1,False);
          end;
    end;
end;
function TSyncDB.CreateTable : Boolean;
begin
  Result := inherited CreateTable;
  FTables.CreateTable;
end;

end.

