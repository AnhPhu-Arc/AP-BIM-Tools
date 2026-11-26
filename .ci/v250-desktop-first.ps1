param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}
$c=Read-Source 'Revit\Command.cs'
$c=One $c 'Silent=true' 'Silent=false'
$c=One $c 'Path.Combine(bundle,"Contents","Core","CadSheetExport.Core.dll")' 'Path.Combine(bundle,"Contents","CadSheetExport.AutoCAD.dll")'
$c=One $c 'if(!File.Exists(core))throw new Exception("Không tìm thấy accoreconsole.exe: "+core);' ''
$c=One $c 'if(!File.Exists(exe)||!File.Exists(Path.Combine(Path.GetDirectoryName(exe),"accoreconsole.exe")))return false;' 'if(!File.Exists(exe))return false;'
$c=One $c 'if(mode.SelectedIndex==2&&System.Diagnostics.Process.GetProcessesByName("acad").Length>0)' 'if(System.Diagnostics.Process.GetProcessesByName("acad").Length>0)'
$c=One $c 'Đóng các phiên AutoCAD đang mở trước khi xuất Model để không ảnh hưởng bản vẽ đang làm.' 'Đóng AutoCAD trước khi xuất để không ảnh hưởng bản vẽ đang làm.'
$c=One $c 'Chế độ Model chuyển từng Sheet bằng phiên AutoCAD riêng, sau đó gộp nền. Có thể lâu hơn chế độ Layout. Tiếp tục?' 'Chế độ Model chuyển từng Sheet bằng AutoCAD Desktop, sau đó gộp vào một DWG. Tỷ lệ theo khổ giấy. Tiếp tục?'
$anchor='status.Text=job.Silent?"Đang xử lý DWG / DST trong nền...":"Đang xử lý Model bằng CAD Desktop...";'
$c=One $c $anchor @'
if(okCount!=job.Sheets.Count)throw new Exception("Một hoặc nhiều Sheet xuất DWG thất bại. Giữ nguyên hồ sơ cũ. Dữ liệu phục hồi: "+work);
   if(job.Model){
    cancel.Enabled=false;
    try{
     for(int i=0;i<job.Sheets.Count;i++){
      var item=job.Sheets[i];status.Text="Chuyển Model "+(i+1)+"/"+job.Sheets.Count+" - "+item.Number;WF.Application.DoEvents();
      item.Source=FlattenNative(host,item,work,i+1,()=>WF.Application.DoEvents());
      item.Detail="Native EXPORTLAYOUT completed; Model will be validated by DWG engine.";
      job.Write(jobPath);
     }
    }catch(Exception ex){status.Text="Chuyển Model thất bại.";WF.MessageBox.Show(ex.Message+"\nDữ liệu phục hồi: "+work,"Xuất chưa hoàn tất");return;}
   }
   status.Text="Đang gộp và kiểm tra DWG bằng AutoCAD Desktop...";
'@
# The only worker used by Revit is the full AutoCAD desktop plugin. Native flatten
# runs before it, not from a command callback or from Core Console.
$start=$c.IndexOf('  static string Launch(')
if($start -lt 0){throw 'Launch boundary missing'}
# Keep the original closing braces of ExportForm and namespace.
$c=$c.Substring(0,$start)+@'
  static string FlattenNative(string exe,SheetItem item,string work,int index,Action pulse){
   if(System.Diagnostics.Process.GetProcessesByName("acad").Length!=0)throw new Exception("AutoCAD vẫn đang mở; không thể chuyển Sheet an toàn.");
   string root=Path.GetDirectoryName(Path.GetFullPath(item.Source));
   string flat=Path.Combine(root,"F.dwg"),marker=Path.Combine(root,"F.done");
   string script=Path.Combine(work,"F"+index.ToString("D4")+".scr");
   string log=Path.Combine(work,"native_flatten.log");
   if(File.Exists(flat)||File.Exists(marker))throw new Exception("Native staging already exists: "+root);
   // Use a fresh startup drawing and native command stream, never Editor.CommandAsync.
   // Select the only populated paper layout (viewport-only sheets are supported).
   // No absolute user path is embedded in the script; use the active DWGPREFIX.
   string body=@"(progn (setq csefd (getvar ""FILEDIA"") csecd (getvar ""CMDDIA"") csep (getvar ""DWGPREFIX"")) (setvar ""FILEDIA"" 0) (setvar ""CMDDIA"" 0) (setq cser (vl-catch-all-apply '(lambda () (setq csel (vl-remove-if-not '(lambda (n) (or (ssget ""_X"" (list (cons 410 n) (cons 0 ""~VIEWPORT""))) (and (setq csev (ssget ""_X"" (list (cons 410 n) (cons 0 ""VIEWPORT"")))) (> (sslength csev) 1)))) (layoutlist))) (if (= (length csel) 1) (progn (setvar ""CTAB"" (car csel)) (if (> (getvar ""CVPORT"") 1) (command ""_.PSPACE"")) (command ""_.EXPORTLAYOUT"" (strcat csep ""F.dwg"")) (if (findfile (strcat csep ""F.dwg"")) ""OK"" ""NO_DWG"")) ""AMBIGUOUS_OR_EMPTY_LAYOUT"")))) (setvar ""FILEDIA"" csefd) (setvar ""CMDDIA"" csecd) (setq csef (open (strcat csep ""F.done"") ""w"")) (if csef (progn (write-line (if (vl-catch-all-error-p cser) (vl-catch-all-error-message cser) cser) csef) (close csef))) (princ))";
   File.WriteAllText(script,(index==1?"CSEPROBE\r\n":"")+body+"\r\n_.QUIT\r\n_N\r\n",System.Text.Encoding.ASCII);
   var psi=new System.Diagnostics.ProcessStartInfo(exe,"\""+item.Source+"\" /nologo /b \""+script+"\""){UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(exe),WindowStyle=System.Diagnostics.ProcessWindowStyle.Minimized};
   psi.EnvironmentVariables.Remove("CSE_JOB");psi.EnvironmentVariables.Remove("CSE_OWN_WORKER");if(index==1)psi.EnvironmentVariables["CSE_PROBE_DIR"]=work;else psi.EnvironmentVariables.Remove("CSE_PROBE_DIR");
   File.AppendAllText(log,DateTime.Now.ToString("o")+" | START "+item.Number+" | "+item.Source+Environment.NewLine);
   using(var proc=System.Diagnostics.Process.Start(psi)){
    if(proc==null)throw new Exception("Cannot start AutoCAD");
    var clock=System.Diagnostics.Stopwatch.StartNew();bool ok=false;
    try{
     while(clock.Elapsed<TimeSpan.FromMinutes(5)){
      pulse();
      if(File.Exists(marker)){
       string detail;try{detail=File.ReadAllText(marker).Trim();}catch(IOException){System.Threading.Thread.Sleep(200);continue;}
       if(detail.Length==0&&!proc.HasExited){System.Threading.Thread.Sleep(200);continue;}
       File.AppendAllText(log,"RESULT "+item.Number+" | "+detail+Environment.NewLine);
       if(detail!="OK")throw new Exception("EXPORTLAYOUT "+item.Number+" | "+detail);
       if(!File.Exists(flat)||new FileInfo(flat).Length==0)throw new Exception("EXPORTLAYOUT "+item.Number+" returned no DWG.");
       ok=true;break;
      }
      if(proc.HasExited)break;System.Threading.Thread.Sleep(200);
     }
     if(!ok)throw new Exception("EXPORTLAYOUT "+item.Number+" did not acknowledge completion. See native_flatten.log and "+script);
     if(!proc.WaitForExit(15000)){try{proc.CloseMainWindow();}catch(Exception){}}
     if(!proc.WaitForExit(8000)){proc.Kill();if(!proc.WaitForExit(10000))throw new Exception("Owned CAD session did not exit.");}
    }finally{if(!proc.HasExited){try{proc.Kill();proc.WaitForExit(10000);}catch(Exception){}}}
   }
   if(index==1){string probe=Path.Combine(work,"probe.result");if(!File.Exists(probe)||File.ReadAllText(probe)!="PASS")throw new Exception("AutoCAD DWG engine preflight failed: "+(File.Exists(probe)?File.ReadAllText(probe):"CSEPROBE was not loaded")+" | See probe.log");}
   using(var f=new FileStream(flat,FileMode.Open,FileAccess.Read,FileShare.Read)){if(f.Length<6)throw new Exception("Invalid DWG: "+flat);var b=new byte[6];if(f.Read(b,0,6)!=6||!System.Text.Encoding.ASCII.GetString(b).StartsWith("AC10",StringComparison.Ordinal))throw new Exception("Invalid DWG header: "+flat);}
   File.AppendAllText(log,"DWG READY "+item.Number+" | "+new FileInfo(flat).Length+" bytes"+Environment.NewLine);
   return flat;
  }
  static string Launch(string exe,string year,string job,string seed,bool silent,Action pulse){
   if(System.Diagnostics.Process.GetProcessesByName("acad").Length!=0)throw new Exception("Đóng AutoCAD trước khi chạy bộ gộp.");
   string work=Path.GetDirectoryName(job),script=Path.Combine(work,"run.scr"),starter=Path.Combine(Path.GetDirectoryName(seed),"_BOOT.dwg");
   string dll=Path.Combine(MachineBundle(year),"Contents","CadSheetExport.AutoCAD.dll");
   if(!File.Exists(dll))throw new FileNotFoundException("AutoCAD Desktop worker missing",dll);
   File.Copy(seed,starter,true);File.SetAttributes(starter,FileAttributes.Normal);
   // ApplicationPlugins bundle registers CSEAUTO at startup or on command invocation.
   File.WriteAllText(script,"CSEPROBE\r\nCSEAUTO\r\n",System.Text.Encoding.ASCII);
   string args="\""+starter+"\" /nologo /b \""+script+"\"";
   var psi=new System.Diagnostics.ProcessStartInfo(exe,args){UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(exe),WindowStyle=System.Diagnostics.ProcessWindowStyle.Minimized};
   psi.EnvironmentVariables["CSE_JOB"]=job;psi.EnvironmentVariables["CSE_OWN_WORKER"]="1";psi.EnvironmentVariables["CSE_PROBE_DIR"]=work;
   string state=Path.Combine(work,"state.txt"),log=Path.Combine(work,"worker_launch.log");string previousProbe=Path.Combine(work,"probe.result");if(File.Exists(previousProbe))File.Delete(previousProbe);
   File.WriteAllText(state,"LAUNCHED");File.AppendAllText(log,DateTime.Now.ToString("o")+" | DESKTOP="+exe+" | DLL="+dll+" | Args="+args+Environment.NewLine);
   using(var proc=System.Diagnostics.Process.Start(psi)){
    if(proc==null)throw new Exception("Không khởi động được AutoCAD Desktop.");
    var clock=System.Diagnostics.Stopwatch.StartNew();
    try{
     while(!proc.WaitForExit(250)){
      pulse();string phase;try{phase=File.ReadAllText(state);}catch(IOException){continue;}
      if(clock.Elapsed>TimeSpan.FromHours(2)||(clock.Elapsed>TimeSpan.FromMinutes(3)&&phase=="LAUNCHED"))throw new Exception("AutoCAD Desktop không xác nhận đã nạp worker. Kiểm tra bundle/CSEAUTO, worker_launch.log.");
     }
     File.AppendAllText(log,"ExitCode="+proc.ExitCode+Environment.NewLine);
    }finally{if(!proc.HasExited){try{proc.Kill();proc.WaitForExit(10000);}catch(Exception){}}}
   }
   string outcome=File.ReadAllText(state);
   return outcome.StartsWith("SUCCESS |",StringComparison.Ordinal)||outcome.StartsWith("FAILED",StringComparison.Ordinal)?outcome:"FAILED | Desktop worker did not complete: "+outcome+" | See worker_launch.log";
  }
 }
}
'@
Write-Source 'Revit\Command.cs' $c
$p=Read-Source 'Cad\Processor.cs'
$p=One $p 's.FinalDwg=Normalize(final,s.Layout,v);' 's.FinalDwg=j.Model?final:Normalize(final,s.Layout,v);if(j.Model)ValidateFlattened(final,s.Number);'
$p=One $p 'MergeModelIsolated(success,merged,v,j.Columns,j.Gap,work,Say);' 'MergeFlattened(success,merged,v,j.Columns,j.Gap,Say);'

# Gate every desktop worker job on a real in-host smoke test.
$p=One $p 'await SafeRun(path,ed,false);if(Environment.GetEnvironmentVariable("CSE_OWN_WORKER")=="1")' 'string probe=Path.Combine(Path.GetDirectoryName(path),"probe.result");if(Environment.GetEnvironmentVariable("CSE_OWN_WORKER")=="1"&&(!File.Exists(probe)||File.ReadAllText(probe)!="PASS")){File.WriteAllText(Path.Combine(Path.GetDirectoryName(path),"state.txt"),"FAILED | AutoCAD DWG engine preflight failed | "+(File.Exists(probe)?File.ReadAllText(probe):"CSEPROBE not loaded"));}else await SafeRun(path,ed,false);if(Environment.GetEnvironmentVariable("CSE_OWN_WORKER")=="1")'

Write-Source 'Cad\Processor.cs' $p
$m=Read-Source 'Cad\ModelMerge.cs'
$start=$m.IndexOf('   using(var target=new Database(true,true))')
$end=$m.IndexOf('    say("MODEL VERIFIED:', $start)
if($start -lt 0 -or $end -lt 0){throw 'Clone boundaries missing'}
$clone=$m.Substring($start,$end-$start)
$head=@'
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
namespace CadSheetExport {
 public partial class Processor {
  [Autodesk.AutoCAD.Runtime.CommandMethod("CSEPROBE",Autodesk.AutoCAD.Runtime.CommandFlags.Session)]
  public void Probe(){
   string work=Environment.GetEnvironmentVariable("CSE_PROBE_DIR");
   if(string.IsNullOrWhiteSpace(work)||!Directory.Exists(work))return;
   string result=Path.Combine(work,"probe.result"),log=Path.Combine(work,"probe.log");
   string folder=Directory.CreateDirectory(Path.Combine(work,"PROBE_"+Guid.NewGuid().ToString("N").Substring(0,8))).FullName;
   try{
    File.AppendAllText(log,DateTime.Now.ToString("o")+" | "+typeof(Processor).Assembly.Location+" | "+Environment.Version+Environment.NewLine);
    var test=new List<SheetItem>();
    for(int i=0;i<2;i++){
     string source=Path.Combine(folder,"P"+i+".dwg");
     using(var db=new Database(true,true)){
      using(var tr=db.TransactionManager.StartTransaction()){
       var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);
       var ms=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForWrite);
       var line=new Line(new Point3d(0,0,0),new Point3d(100+i,50+i,0));
       ms.AppendEntity(line);tr.AddNewlyCreatedDBObject(line,true);tr.Commit();
      }
      db.SaveAs(source,DwgVersion.AC1032);
     }
     string packed=Path.Combine(folder,"S"+i+".dwg");
     new LinkPack(folder,DwgVersion.AC1032,t=>File.AppendAllText(log,t+Environment.NewLine)).Publish(source,packed,"P"+i);
     ValidateFlattened(packed,"PROBE-"+i);
     test.Add(new SheetItem{Number="PROBE-"+i,FinalDwg=packed});
    }
    string target=Path.Combine(folder,"M.dwg");
    MergeFlattened(test,target,DwgVersion.AC1032,2,10,t=>File.AppendAllText(log,t+Environment.NewLine));
    LinkPack.Check(target);
    File.AppendAllText(log,"PASS: side DB save/read, pack, merge two models and reopen."+Environment.NewLine);
    File.WriteAllText(result,"PASS");
   }catch(System.Exception ex){File.AppendAllText(log,ex+Environment.NewLine);File.WriteAllText(result,"FAIL | "+ex.Message);}
  }
  static void ValidateFlattened(string flat,string number){
   using(var check=Open(flat))using(var tr=check.TransactionManager.StartTransaction()){
    var bt=(BlockTable)tr.GetObject(check.BlockTableId,OpenMode.ForRead);
    var model=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
    if(!model.Cast<ObjectId>().Any())throw new System.Exception("Empty flattened Model: "+number);
   }
  }
  static void MergeFlattened(List<SheetItem> sheets,string path,DwgVersion version,int columns,double gap,Action<string> say){
   if(columns<1||gap<0||sheets.Count==0)throw new System.Exception("Invalid model grid");
   string stage="CLONE";
   var flats=sheets.Select(s=>s.FinalDwg).ToList();
   try{
    foreach(var s in sheets)ValidateFlattened(s.FinalDwg,s.Number);
'@
$tail=@'
    say("MODEL VERIFIED: "+sheets.Count+" sheets");
   }catch(System.Exception ex){say("MODEL FAILED AT "+stage+" | "+ex);throw new System.Exception(stage+": "+ex.Message,ex);}
  }
 }
}
'@
Write-Source 'Cad\ModelMerge.cs' ($head+[Environment]::NewLine+$clone+[Environment]::NewLine+$tail)
Write-Host 'Desktop-first architecture: native flatten orchestrated by Revit, separate full CAD merge worker, no Core Console launch.'
