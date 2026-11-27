param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}

$c=Read-Source 'Revit\Command.cs'
$c=One $c 'cancel.Enabled=false;string result=Launch(host,cadHost.SelectedItem.ToString().Substring("AutoCAD ".Length),jobPath,job.Sheets.First(x=>x.Status=="EXPORTED").Source,job.Silent,()=>{status.Text="Đang xử lý CAD... "+DateTime.Now.ToString("HH:mm:ss");WF.Application.DoEvents();});' @'
cancel.Enabled=true;cancel.Text="Dừng xử lý CAD";
   var uiClock=System.Diagnostics.Stopwatch.StartNew();
   var uiUpdate=TimeSpan.FromSeconds(-2);
   string result=Launch(host,cadHost.SelectedItem.ToString().Substring("AutoCAD ".Length),jobPath,job.Sheets.First(x=>x.Status=="EXPORTED").Source,job.Silent,()=>{
    if(uiClock.Elapsed-uiUpdate>=TimeSpan.FromSeconds(1)){
     uiUpdate=uiClock.Elapsed;
     bool publishing=File.Exists(Path.Combine(work,"publish.started"));
     cancel.Enabled=!publishing;cancel.Text=publishing?"Đang bàn giao...":"Dừng xử lý CAD";
     string phase=ReadWorkerProgress(work);
     status.Text=uiClock.Elapsed.ToString(@"hh\:mm\:ss")+" | "+(File.Exists(Path.Combine(work,"publish.wait"))?"Cảnh báo: bàn giao đang chờ; không tắt CAD. | ":"")+phase;
    }
    WF.Application.DoEvents();
    if(stop&&!File.Exists(Path.Combine(work,"publish.started"))){
     string request=Path.Combine(work,"cancel.request");
     if(!File.Exists(request))File.WriteAllText(request,"USER_CANCEL");
    }
   });
'@
$anchor='  static string LaunchHeadless(string exe,string year,string job,string seed,Action pulse){'
$helper=@'
  static string TailLine(string path){
   try{
    if(!File.Exists(path))return "";
    using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
     long n=Math.Min(f.Length,8192);if(n==0)return "";
     f.Seek(-n,SeekOrigin.End);var data=new byte[(int)n];int got=f.Read(data,0,data.Length);
     return System.Text.Encoding.UTF8.GetString(data,0,got).Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries).LastOrDefault()??"";
    }
   }catch(IOException){return "";}
  }
  static string ReadWorkerProgress(string work){
   string phase=TailLine(Path.Combine(work,"phase.txt"));
   string[] names=phase=="PREFLIGHT"?new[]{"probe.log","headless_loader.log"}:new[]{"cad_process.log","layout_inventory.log","headless_loader.log"};
   string detail="";
   foreach(string name in names){detail=TailLine(Path.Combine(work,name));if(!string.IsNullOrWhiteSpace(detail))break;}
   if(detail.Length>100)detail=detail.Substring(0,100)+"...";
   return (string.IsNullOrWhiteSpace(phase)?"Khởi động engine":phase)+(detail.Length>0?" | "+detail:"");
  }
  static bool HasTerminalState(string s){
   return s.StartsWith("SUCCESS |",StringComparison.Ordinal)||s.StartsWith("FAILED",StringComparison.Ordinal);
  }
  static bool StopBeforePublish(System.Diagnostics.Process proc,string work,string reason){
   // The worker holds this same exclusive lock from the publish boundary.
   // Never terminate while a destination file or its backup may be changing.
   FileStream gate;
   try{gate=new FileStream(Path.Combine(work,"publish.gate"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
   catch(IOException){return false;}
   using(gate){
    if(File.Exists(Path.Combine(work,"publish.started")))return false;
    File.WriteAllText(Path.Combine(work,"cancel.request"),reason);
    if(!proc.HasExited){proc.Kill();if(!proc.WaitForExit(10000))throw new Exception("Không đóng được tiến trình CAD nền. "+work);}
    File.WriteAllText(Path.Combine(work,"state.txt"),"FAILED | "+reason+" | "+ReadWorkerProgress(work)+" | Recovery: "+work);
    return true;
   }
  }
'@
$c=One $c $anchor ($helper+[Environment]::NewLine+$anchor)
$old=@'
    var clock=System.Diagnostics.Stopwatch.StartNew();
    try{
     while(!proc.WaitForExit(250)){
      pulse();string phase;try{phase=File.ReadAllText(state);}catch(IOException){continue;}
      if(clock.Elapsed>TimeSpan.FromHours(2)||(clock.Elapsed>TimeSpan.FromMinutes(3)&&(phase=="LAUNCHED"||phase=="LOADER_READY")))throw new Exception("Headless worker timeout | "+phase+" | "+work);
     }
     proc.WaitForExit();File.AppendAllText(log,"ExitCode="+proc.ExitCode+Environment.NewLine);
    }finally{if(!proc.HasExited){try{proc.Kill();proc.WaitForExit(10000);}catch(Exception){}}}
'@
$new=@'
    var clock=System.Diagnostics.Stopwatch.StartNew();
    var lastProgress=clock.Elapsed;var lastPoll=TimeSpan.FromSeconds(-2);
    string lastSignature="";TimeSpan? terminalAt=null;bool publishWarned=false;
    while(!proc.WaitForExit(250)){
     pulse();
     if(clock.Elapsed-lastPoll<TimeSpan.FromSeconds(1))continue;
     lastPoll=clock.Elapsed;
     string phase;try{phase=File.ReadAllText(state);}catch(IOException){continue;}
     if(HasTerminalState(phase)){
      if(!terminalAt.HasValue)terminalAt=clock.Elapsed;
      if(clock.Elapsed-terminalAt.Value>TimeSpan.FromSeconds(15)){
       File.AppendAllText(log,"Terminal state received; closing owned Core Console after shutdown timeout."+Environment.NewLine);
       if(!proc.HasExited){proc.Kill();if(!proc.WaitForExit(10000))throw new Exception("CAD engine returned a result but could not be closed. "+work);}break;
      }
      continue;
     }
     var signature=new System.Text.StringBuilder(phase);
     foreach(var name in new[]{"phase.txt","cad_process.log","probe.log","layout_inventory.log","headless_loader.log"}){
      var f=new FileInfo(Path.Combine(work,name));
      if(f.Exists)signature.Append('|').Append(f.Length).Append(':').Append(f.LastWriteTimeUtc.Ticks);
     }
     string current=signature.ToString();
     if(current!=lastSignature){lastSignature=current;lastProgress=clock.Elapsed;}
     bool cancelled=File.Exists(Path.Combine(work,"cancel.request"));
     bool idle=clock.Elapsed-lastProgress>TimeSpan.FromMinutes(3);
     bool startup=clock.Elapsed>TimeSpan.FromMinutes(3)&&(phase=="LAUNCHED"||phase=="LOADER_READY");
     if(cancelled||idle||startup){
      string reason=cancelled?"Đã dừng theo yêu cầu":startup?"Engine không xác nhận khởi động":"Không có tiến độ CAD trong 180 giây";
      if(StopBeforePublish(proc,work,reason))break;
      // Publishing has begun. Preserve the transaction and give an explicit
      // diagnostic rather than force-killing a process with live DWG/DST backups.
      if(!publishWarned){
       publishWarned=true;
       File.WriteAllText(Path.Combine(work,"publish.wait"),reason);
       File.AppendAllText(log,"PUBLISH WAIT: "+reason+"; automatic termination refused for file safety."+Environment.NewLine);
      }
     }
    }
    if(proc.HasExited)File.AppendAllText(log,"ExitCode="+proc.ExitCode+Environment.NewLine);
'@
$c=One $c $old $new
Write-Source 'Revit\Command.cs' $c
$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'InspectSourceLayouts(Job.Read(path),work);' 'File.WriteAllText(Path.Combine(work,"phase.txt"),"INVENTORY");InspectSourceLayouts(Job.Read(path),work);File.WriteAllText(Path.Combine(work,"phase.txt"),"PREFLIGHT");'
$p=One $p 'Run(path,null,false).GetAwaiter().GetResult();' 'File.WriteAllText(Path.Combine(work,"phase.txt"),"PACK / NORMALIZE");Run(path,null,false).GetAwaiter().GetResult();'
$p=One $p 'Say("Kiểm tra "+s.Number);' 'File.WriteAllText(Path.Combine(work,"phase.txt"),"PACK "+(success.Count+1)+"/"+ok.Count+" "+s.Number);Say("Kiểm tra "+s.Number);'
$p=One $p 'string merged=Path.Combine(stage,"M.dwg");' 'File.WriteAllText(Path.Combine(work,"phase.txt"),j.Model?"PROJECT / MERGE MODEL":"MERGE LAYOUTS");string merged=Path.Combine(stage,"M.dwg");'
$p=One $p 'string installedLinks=null;' 'string installedLinks=null;FileStream publishGate=null;'
$p=One $p 'string stagedLinks=Path.Combine(stage,"Links",runId);' @'
    // Acquire a gate shared with the Revit watchdog before any output mutation.
    publishGate=new FileStream(Path.Combine(work,"publish.gate"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
    if(File.Exists(Path.Combine(work,"cancel.request")))throw new System.OperationCanceledException("Cancelled before publishing");
    File.WriteAllText(Path.Combine(work,"publish.started"),DateTime.UtcNow.ToString("o"));
    File.WriteAllText(Path.Combine(work,"phase.txt"),"PUBLISH DWG / LINKS");
    Say("PUBLISH BEGIN");
    string stagedLinks=Path.Combine(stage,"Links",runId);
'@
$p=One $p 'MakeDst(pendingDst,j.SetName,success);' 'File.WriteAllText(Path.Combine(work,"phase.txt"),"CREATE DST / COM");Say("DST BEGIN "+pendingDst);MakeDst(pendingDst,j.SetName,success);Say("DST CREATE OK "+pendingDst);'
$p=One $p 'StampAssociation(group.First(),dest,v);LinkPack.Check(group.Key);' 'File.WriteAllText(Path.Combine(work,"phase.txt"),"STAMP DST ASSOCIATION");Say("DST STAMP "+group.Key);StampAssociation(group.First(),dest,v);LinkPack.Check(group.Key);'
$p=One $p '   if(complete){' ('   finally{if(publishGate!=null)publishGate.Dispose();}'+[Environment]::NewLine+'   if(complete){')
# Correct grouping of PowerShell string concatenation is handled below.
$p=One $p 'Say("EXPORT FAILED: "+ex);' 'File.WriteAllText(Path.Combine(work,"phase.txt"),"ROLLBACK");Say("EXPORT FAILED: "+ex);'
Write-Source 'Cad\Processor.cs' $p
$m=Read-Source 'Cad\ModelMerge.cs'
$m=One $m 'string imagePath=Path.Combine(Directory.CreateDirectory(Path.Combine(folder,"Links")).FullName,"probe.png");' 'File.AppendAllText(log,"PREFLIGHT: begin mixed-layout and raster fixtures."+Environment.NewLine);string imagePath=Path.Combine(Directory.CreateDirectory(Path.Combine(folder,"Links")).FullName,"probe.png");'
$m=One $m 'var definition=new RasterImageDef{SourceFileName=imagePath};' 'File.AppendAllText(log,"PREFLIGHT: loading fixture PNG."+Environment.NewLine);var definition=new RasterImageDef{SourceFileName=imagePath};'
$m=One $m 'var imageId=imageDict.SetAt("PROBE_LOGO",definition);' 'File.AppendAllText(log,"PREFLIGHT: fixture PNG loaded."+Environment.NewLine);var imageId=imageDict.SetAt("PROBE_LOGO",definition);'
$m=One $m '    string projected=Path.Combine(folder,"Fprojected.dwg");' '    report("PREFLIGHT: projected viewport fixture");string projected=Path.Combine(folder,"Fprojected.dwg");'
$m=One $m '    string mixed=Path.Combine(folder,"Lmixed.dwg");' '    report("PREFLIGHT: mixed layout merge");string mixed=Path.Combine(folder,"Lmixed.dwg");'
Write-Source 'Cad\ModelMerge.cs' $m
Write-Host 'V2.6.2 progress diagnostics, pre-publish inactivity watchdog, explicit DST traces and bounded terminal shutdown.'
