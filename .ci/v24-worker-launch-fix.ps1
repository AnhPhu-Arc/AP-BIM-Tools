# Apply only to the retrieved CAD Export V1.3.1 / BuildFix03 source.
# Source-stage changes; compile and test on Windows AutoCAD before release.
param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$encoding=New-Object System.Text.UTF8Encoding($true,$true)
function Replace-One([string]$text,[string]$old,[string]$new){
 if(([regex]::Matches($text,[regex]::Escape($old))).Count -ne 1){throw "Expected exactly one source match: $old"}
 return $text.Replace($old,$new)
}
$command=(Resolve-Path -LiteralPath (Join-Path $CadExportRoot 'Revit\Command.cs')).ProviderPath
$processor=(Resolve-Path -LiteralPath (Join-Path $CadExportRoot 'Cad\Processor.cs')).ProviderPath
$c=[IO.File]::ReadAllText($command,$encoding)
$p=[IO.File]::ReadAllText($processor,$encoding)
# Use the installed, absolute worker path directly in the Core Console script.
# Avoid the AutoLISP getenv startup dependency for ASCII install paths.
$old=@'
if(silent){engine=Path.Combine(Path.GetDirectoryName(exe),"accoreconsole.exe");File.WriteAllText(script,"(command \"_.NETLOAD\" (getenv \"CSE_CORE_DLL\"))\r\nCSECORE\r\n_.QUIT\r\n_N\r\n",System.Text.Encoding.ASCII);args="/i \""+starter+"\" /s \""+script+"\"";}
'@
$new=@'
if(silent){engine=Path.Combine(Path.GetDirectoryName(exe),"accoreconsole.exe");string coreDll=Path.Combine(MachineBundle(year),"Contents","Core","CadSheetExport.Core.dll");if(!File.Exists(coreDll))throw new FileNotFoundException("Missing Core DLL",coreDll);string load=coreDll.All(ch=>ch<128)?"_.NETLOAD\r\n\""+coreDll+"\"\r\n":"(command \"_.NETLOAD\" (getenv \"CSE_CORE_DLL\"))\r\n";File.WriteAllText(script,load+"CSECORE\r\n_.QUIT\r\n_N\r\n",System.Text.Encoding.ASCII);args="/i \""+starter+"\" /s \""+script+"\"";}
'@
$c=Replace-One $c $old $new
$c=Replace-One $c 'File.WriteAllText(state,"LAUNCHED");using(var proc=' 'File.WriteAllText(state,"LAUNCHED");string launchLog=Path.Combine(work,"worker_launch.log");File.WriteAllText(launchLog,DateTime.Now.ToString("o")+" | Engine="+engine+Environment.NewLine+"Args="+args+Environment.NewLine+"Job="+job+Environment.NewLine);using(var proc='
$c=Replace-One $c 'proc.WaitForExit();}string outcome=' 'proc.WaitForExit();File.AppendAllText(launchLog,"ExitCode="+proc.ExitCode+Environment.NewLine);}string outcome='
$c=Replace-One $c '"FAILED | Worker ended before completion: "+outcome;' '"FAILED | Worker ended before completion: "+outcome+" | See worker_launch.log and core_console.log";'
$old=@'
public void CoreRun(){var ed=Acad.DocumentManager.MdiActiveDocument?.Editor;string path=Environment.GetEnvironmentVariable("CSE_JOB");if(ed==null||string.IsNullOrWhiteSpace(path)||!File.Exists(path))return;string work=Path.GetDirectoryName(path);try{File.WriteAllText(Path.Combine(work,"state.txt"),"PROCESSING");if(Job.Read(path).Model)throw new System.Exception("Model requires desktop EXPORTLAYOUT");Run(path,ed,false).GetAwaiter().GetResult();}catch(System.Exception e){File.WriteAllText(Path.Combine(work,"state.txt"),"FAILED | "+e);ed.WriteMessage("\nCSE ERROR: "+e);}}
'@
$new=@'
public void CoreRun(){string path=Environment.GetEnvironmentVariable("CSE_JOB");if(string.IsNullOrWhiteSpace(path)||!File.Exists(path)){System.Console.WriteLine("CSECORE: job path missing or unreadable");return;}string work=Path.GetDirectoryName(path);Editor ed=null;try{File.WriteAllText(Path.Combine(work,"state.txt"),"PROCESSING");ed=Acad.DocumentManager.MdiActiveDocument?.Editor;if(ed==null)throw new System.InvalidOperationException("Core Console has no active drawing editor");if(Job.Read(path).Model)throw new System.Exception("Model requires desktop EXPORTLAYOUT");Run(path,ed,false).GetAwaiter().GetResult();}catch(System.Exception e){File.WriteAllText(Path.Combine(work,"state.txt"),"FAILED | "+e);System.Console.WriteLine("CSE ERROR: "+e);ed?.WriteMessage("\nCSE ERROR: "+e);}}
'@
$p=Replace-One $p $old $new
[IO.File]::WriteAllText($command,$c,$encoding)
[IO.File]::WriteAllText($processor,$p,$encoding)
Write-Host 'Worker launch source updated. No security variables changed. Windows runtime test required.'
