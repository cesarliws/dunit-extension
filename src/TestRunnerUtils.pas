unit TestRunnerUtils;

interface

{$DEFINE CUSTOM_REPORT_TARGET}

uses
{$IFDEF RELEASE}
  {$UNDEF TESTINSIGHT}
{$ELSE}
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnit,
  {$ENDIF}
{$ENDIF}
  TestFramework,
  GUITestRunner,
  CIXMLTestRunner,
  TextTestRunner,
  Forms,
  Classes,
  Windows;

{$IFDEF CUSTOM_REPORT_TARGET}
const
  SUREFIRE_OUTPUT_DIRECTORY = 'DUnitOutput\';
  SUREFIRE_TESTRESULT_PREFIX = '';
  SUREFIRE_TESTRESULT_SUFIX = '-DUnitTestReport.xml';
{$ELSE}
const
  SUREFIRE_OUTPUT_DIRECTORY = '..\target\surefire-reports\';
  SUREFIRE_TESTRESULT_PREFIX = 'TEST-';
  SUREFIRE_TESTRESULT_SUFIX = '-Out.xml';
{$ENDIF}

type
  TRunMode = (rmGUI, rmText, rmXML, rmTestInsight);

  TTestRunnerUtils = class
  private
    class function MustRunAsXml: Boolean; static;
    class function MustRunAsText: Boolean; static;

    class function RunGUIMode: TTestResult; static;
    class function RunTextMode: TTestResult; static;
    class function RunXmlMode: TTestResult; static;
{$IFDEF TESTINSIGHT}
    class function RunTestInsightMode: TTestResult; static;
{$ENDIF}

    class function GetTestOutputDirectory: string; static;
    class procedure PauseWhenConsoleInsideIDE; static; static;

    class procedure Sort(ATest: ITest); static;

    class procedure QuickSort(const AList: IInterfaceList; L, R: Integer); static;
  public
    class function GetRunMode: TRunMode; static;
    class function RunRegisteredTests(): Integer;overload; static;
    class function RunRegisteredTests(ARunMode: TRunMode): Integer;overload; static;
    class procedure SortTests; static;
  end;

  TFileUtils = class
  public
    class function BuildFileList(const Path, AExtension: string; const Attr: Integer; const List: TStrings; ARecursive: Boolean): Boolean; static;
    class procedure DeleteAllFiles(const Path, AExtension: string); static;
  end;

implementation

uses SysUtils, TypInfo;

{ TTestRunnerUtils }

class function TTestRunnerUtils.RunRegisteredTests: Integer;
var
  vRunMode: TRunMode;
begin
  vRunMode := GetRunMode;

  Result := TTestRunnerUtils.RunRegisteredTests(vRunMode);
end;

class function TTestRunnerUtils.RunGUIMode: TTestResult;
begin
  GuiTestRunner.RunRegisteredTests;

  Result := TTestResult.Create;
end;

class function TTestRunnerUtils.RunRegisteredTests(ARunMode: TRunMode): Integer;
var
  vTestResult: TTestResult;
begin
  case ARunMode of
    rmGUI:
      vTestResult := RunGUIMode;
    rmText:
      vTestResult := RunTextMode;
    rmXML:
      vTestResult := RunXmlMode;
{$IFDEF TESTINSIGHT}
    rmTestInsight:
      vTestResult := RunTestInsightMode;
{$ENDIF}
  else
    raise Exception.CreateFmt('RunMode "%s" n�o suportado.', [GetEnumName(TypeInfo(TRunMode), Ord(ARunMode))]);
  end;

  try
    Result := vTestResult.ErrorCount + vTestResult.FailureCount;
  finally
    vTestResult.Free;
  end;
end;

class procedure TTestRunnerUtils.PauseWhenConsoleInsideIDE;
begin
{$WARN  SYMBOL_PLATFORM OFF}
  if (DebugHook <> 0) and (TTestRunnerUtils.GetRunMode = rmText) then
  begin
    Readln;
  end;
end;

class function TTestRunnerUtils.RunTextMode: TTestResult;
begin
  if not IsConsole then
  begin
    AllocConsole;
  end;
  WriteLn('Running tests for: ' + ExtractFileName(GetModuleName(HInstance)));
  Result := TextTestRunner.RunRegisteredTests();
  TTestRunnerUtils.PauseWhenConsoleInsideIDE;
end;

class function TTestRunnerUtils.RunXmlMode: TTestResult;
var
  vXmlOutputPath: String;
begin
  vXmlOutputPath := ExtractFilePath(Application.ExeName) + GetTestOutputDirectory;

  TFileUtils.DeleteAllFiles(vXmlOutputPath + '*.xml', '.xml');

  if ForceDirectories(vXmlOutputPath) then
  begin
    vXmlOutputPath := vXmlOutputPath + SUREFIRE_TESTRESULT_PREFIX;

    Result := CIXMLTestRunner.RunRegisteredTests(vXmlOutputPath);
  end else
  begin
    raise Exception.CreateFmt('Falha ao criar outputdirectory "%s". Erro: %s', [vXmlOutputPath, SysErrorMessage(GetLastError)]);
  end;
end;

{$IFDEF TESTINSIGHT}
class function TTestRunnerUtils.RunTestInsightMode: TTestResult;
begin
  TestInsight.DUnit.RunRegisteredTests();
  // TODO : Implement result in DSharp
  Result := TTestResult.Create;
end;
{$ENDIF}

class procedure TTestRunnerUtils.Sort(ATest: ITest);
begin
  QuickSort(ATest.Tests, 0, ATest.Tests.Count-1);
end;

class procedure TTestRunnerUtils.SortTests;
begin
  Sort(TestFramework.RegisteredTests as ITest);
end;

class function TTestRunnerUtils.MustRunAsXml: Boolean;
begin
  Result := FindCmdLineSwitch('xml', ['-', '/'], True);
end;

class procedure TTestRunnerUtils.QuickSort(const AList: IInterfaceList; L, R: Integer);

  function Compare(const AList: IInterfaceList; L, R: Integer): Integer;
  var
    vLeft, vRigth: ITest;
  begin
    vLeft := AList[L] as ITest;
    vRigth := AList[R] as ITest;

    Result := CompareText(vLeft.Name, vRigth.Name);
  end;

var
  I, J, P: Integer;
begin
  repeat
    I := L;
    J := R;
    P := (L + R) shr 1;
    repeat
      while Compare(AList, I, P) < 0 do Inc(I);
      while Compare(AList, J, P) > 0 do Dec(J);
      if I <= J then
      begin
        if I <> J then
        begin
          AList.Exchange(I, J);
        end;
        if P = I then
          P := J
        else if P = J then
          P := I;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then QuickSort(AList, L, J);
    L := I;
  until I >= R;
end;

class function TTestRunnerUtils.GetRunMode: TRunMode;
begin
{$IFDEF DEBUG}
  {$IFDEF TESTINSIGHT}
  Result := rmTestInsight;
  Exit;
  {$ENDIF}
{$ENDIF}

  Result := rmGUI;
  if MustRunAsXml then
  begin
    Result := rmXML;
  end
  else if MustRunAsText then
  begin
    Result := rmText;
  end;
end;

class function TTestRunnerUtils.GetTestOutputDirectory: string;
var
  i: Integer;
begin
  Result := SUREFIRE_OUTPUT_DIRECTORY;
  for i := 1 to ParamCount do
  begin
    if SameText(Copy(ParamStr(i), 2, Maxint), 'output') and not (i = ParamCount) then
    begin
      Result := ParamStr(i+1);
      Break;
    end;
  end;

  Result := IncludeTrailingPathDelimiter(Result);
end;

class function TTestRunnerUtils.MustRunAsText: Boolean;
begin
  Result := FindCmdLineSwitch('text', ['-', '/'], True);
end;

{ TFileUtils }

class function TFileUtils.BuildFileList(const Path, AExtension: string;const Attr: Integer; const List: TStrings; ARecursive: Boolean): Boolean;
var
  SearchRec: TSearchRec;
  R: Integer;
  vRealFilePath: String;
begin
  vRealFilePath := ExtractFilePath(Path);
  
  Assert(List <> nil);
  R := FindFirst(Path, Attr, SearchRec);
  Result := R = 0;
  try
    if Result then
    begin
      while R = 0 do
      begin
        if (SearchRec.Name <> '.') and (SearchRec.Name <> '..') then
        begin
         if ((SearchRec.Attr and Attr) = (SearchRec.Attr and faDirectory)) and ARecursive then
           BuildFileList(vRealFilePath + SearchRec.Name + '\' + ExtractFileName(Path) , AExtension, Attr, List, ARecursive)
         else if (ExtractFileExt(SearchRec.Name) = AExtension) then 
          List.Add(vRealFilePath + SearchRec.Name);
        end;

        R := FindNext(SearchRec);
      end;
      Result := R = ERROR_NO_MORE_FILES;
    end;
  finally
    SysUtils.FindClose(SearchRec);
  end;
end;

class procedure TFileUtils.DeleteAllFiles(const Path, AExtension: string);
var
  vFileList: TStringList;
  i: Integer;
begin
  vFileList := TStringList.Create;
  try
    TFileUtils.BuildFileList(Path, AExtension, faAnyFile, vFileList, False);

    for i := 0 to vFileList.Count-1 do
    begin
      DeleteFile(PChar(vFileList[i]));
    end;
  finally
    vFileList.Free;
  end;

end;

end.
