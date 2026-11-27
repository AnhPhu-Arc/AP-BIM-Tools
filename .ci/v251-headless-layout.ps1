param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}
$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'static void Merge(List<SheetItem> sheets,string path,DwgVersion v){' 'static void Merge(List<SheetItem> sheets,string path,DwgVersion v,Action<string> say=null){if(say==null)say=_=>{};if(sheets==null||sheets.Count==0)throw new System.Exception("No sheets to merge.");'
$p=One $p 'parts.Add(CloneSheet(src,target,s.Layout,parts.Count+1));' 'say("CLONE LAYOUT "+s.Number+" | "+s.Layout);try{parts.Add(CloneSheet(src,target,s.Layout,parts.Count+1,say));}catch(System.Exception ex){throw new System.Exception("CLONE LAYOUT "+s.Number+" ["+s.Layout+"] | "+ex.Message,ex);}'
$p=One $p 'var freeze=new ObjectIdCollection(parts.Where((x,k)=>k!=i).Select(x=>x.Layer).ToArray());' 'var freeze=new ObjectIdCollection();for(int j=0;j<parts.Count;j++)if(j!=i&&!parts[j].Layer.IsNull)freeze.Add(parts[j].Layer);'
$p=One $p 'static LayerAndLayout CloneSheet(Database src,Database target,string name,int index){' 'static LayerAndLayout CloneSheet(Database src,Database target,string name,int index,Action<string> say){'
$p=One $p 'var modelIds=new ObjectIdCollection(sm.Cast<ObjectId>().ToArray());var paperIds=new ObjectIdCollection(sp.Cast<ObjectId>().ToArray());' 'var modelIds=new ObjectIdCollection();foreach(ObjectId id in sm)modelIds.Add(id);var paperIds=new ObjectIdCollection();foreach(ObjectId id in sp)paperIds.Add(id);say("CLONE INPUT "+name+" | MODEL="+modelIds.Count+" | PAPER="+paperIds.Count);'
$p=One $p 'var sourceVps=sl.GetViewports();if(sourceVps.Count!=paperIds.Cast<ObjectId>().Count(id=>st.GetObject(id,OpenMode.ForRead) is Viewport))throw new System.Exception("Không xác định đủ viewport: "+name);' 'var sourceVps=sl.GetViewports();ObjectId overall=sourceVps.Count>0?sourceVps[0]:ObjectId.Null;var floating=new List<ObjectId>();foreach(ObjectId id in paperIds){if(id!=overall&&st.GetObject(id,OpenMode.ForRead) is Viewport vp&&vp.Number!=1)floating.Add(id);}say("VIEWPORTS "+name+" | FLOATING="+floating.Count);'
$p=One $p 'for(int i=1;i<sourceVps.Count;i++){var oldVp=(Viewport)st.GetObject(sourceVps[i],OpenMode.ForRead);' 'foreach(ObjectId oldId in floating){var oldVp=(Viewport)st.GetObject(oldId,OpenMode.ForRead);'
$p=One $p '}else Merge(success,merged,v);' '}else Merge(success,merged,v,Say);'
$p=One $p 'ObjectId overall=vps.Count>0?vps[0]:ObjectId.Null;bool content=false;foreach(ObjectId id in b){if(id==overall)continue;content=true;break;}' 'ObjectId overall=vps.Count>0?vps[0]:ObjectId.Null;bool content=false;foreach(ObjectId id in b){if(id==overall)continue;if(tr.GetObject(id,OpenMode.ForRead) is Viewport vp&&vp.Number==1)continue;content=true;break;}'
# Core engine entry is reflected by a separate bootstrap with no SSO dependencies.
$start=$p.IndexOf('  [CommandMethod("CSECORE")]')
$end=$p.IndexOf('#else',$start)
if($start -lt 0 -or $end -lt 0){throw 'Core entry missing'}
$head=@'
  public static void RunHeadless(string path){
   string work=Path.GetDirectoryName(Path.GetFullPath(path));
   try{
    File.WriteAllText(Path.Combine(work,"state.txt"),"PROCESSING");
    if(Job.Read(path).Model)throw new System.Exception("Native EXPORTLAYOUT is not supported by this headless worker.");
    Environment.SetEnvironmentVariable("CSE_PROBE_DIR",work);
    new Processor().Probe();
    string probe=Path.Combine(work,"probe.result");
    if(!File.Exists(probe)||File.ReadAllText(probe)!="PASS")throw new System.Exception("Headless engine preflight failed: "+(File.Exists(probe)?File.ReadAllText(probe):"no probe result")+" | See probe.log");
    Run(path,null,false).GetAwaiter().GetResult();
   }catch(System.Exception ex){File.WriteAllText(Path.Combine(work,"state.txt"),"FAILED | "+ex);System.Console.WriteLine("CSE ERROR: "+ex);}
  }
'@
$p=$p.Substring(0,$start)+$head+[Environment]::NewLine+$p.Substring($end)
$p=One $p 'try{Acad.DocumentManager.MdiActiveDocument?.Editor.WriteMessage("\n"+t);}catch(System.Exception){}' 'try{if(ed!=null)ed.WriteMessage("\n"+t);else System.Console.WriteLine(t);}catch(System.Exception){}'
# Bootstrap only is NETLOAD'ed. Engine assembly does not expose command attributes in Core.
$p=One $p '[assembly: CommandClass(typeof(CadSheetExport.Processor))]' ("#if !CSE_CORE"+[Environment]::NewLine+'[assembly: CommandClass(typeof(CadSheetExport.Processor))]'+[Environment]::NewLine+"#endif")
Write-Source 'Cad\Processor.cs' $p
$m=Read-Source 'Cad\ModelMerge.cs'
$m=One $m '  [Autodesk.AutoCAD.Runtime.CommandMethod("CSEPROBE",Autodesk.AutoCAD.Runtime.CommandFlags.Session)]' @'
#if !CSE_CORE
  [Autodesk.AutoCAD.Runtime.CommandMethod("CSEPROBE",Autodesk.AutoCAD.Runtime.CommandFlags.Session)]
#endif
'@
$anchor='    File.AppendAllText(log,"PASS: side DB save/read, pack, merge two models and reopen."+Environment.NewLine);'
$m=One $m $anchor @'
    // Regression fixtures: one paper-only Sheet (empty Model), one Sheet with
    // Model geometry and a floating viewport. Also test single-sheet merge.
    var layoutTests=new List<SheetItem>();
    for(int i=0;i<2;i++){
     string name="TEST-LAYOUT-"+i,source=Path.Combine(folder,"LP"+i+".dwg");
     using(var db=new Database(true,true)){
      string old=Layouts(db,false).First();
      InDb(db,()=>{var lm=LayoutManager.Current;lm.RenameLayout(old,name);lm.CurrentLayout=name;});
      using(var tr=db.TransactionManager.StartTransaction()){
       var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
       var layout=(Layout)tr.GetObject(dict.GetAt(name),OpenMode.ForRead);
       var paper=(BlockTableRecord)tr.GetObject(layout.BlockTableRecordId,OpenMode.ForWrite);
       // Default floating viewports are removed so cover really has no model geometry.
       var overall=layout.GetViewports();ObjectId primary=overall.Count>0?overall[0]:ObjectId.Null;
       foreach(ObjectId id in paper.Cast<ObjectId>().ToList()){
        if(id!=primary&&tr.GetObject(id,OpenMode.ForRead) is Viewport vp&&vp.Number!=1){vp.UpgradeOpen();vp.Erase();}
       }
       var border=new Line(new Point3d(10,10,0),new Point3d(180,100,0));
       paper.AppendEntity(border);tr.AddNewlyCreatedDBObject(border,true);
       if(i==1){
        var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);
        var model=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForWrite);
        var line=new Line(new Point3d(0,0,0),new Point3d(50,70,0));model.AppendEntity(line);tr.AddNewlyCreatedDBObject(line,true);
        var floating=new Viewport{CenterPoint=new Point3d(90,60,0),Width=80,Height=60,ViewCenter=new Point2d(25,35),ViewHeight=100};
        paper.AppendEntity(floating);tr.AddNewlyCreatedDBObject(floating,true);
       }
       tr.Commit();
      }
      db.SaveAs(source,DwgVersion.AC1032);
     }
     layoutTests.Add(new SheetItem{Number=name,Layout=name,FinalDwg=source});
    }
    Action<string> report=t=>File.AppendAllText(log,t+Environment.NewLine);
    Merge(layoutTests.Take(1).ToList(),Path.Combine(folder,"Lsingle.dwg"),DwgVersion.AC1032,report);
    string mixed=Path.Combine(folder,"Lmixed.dwg");
    Merge(layoutTests,mixed,DwgVersion.AC1032,report);
    using(var verified=Open(mixed)){
     var names=Layouts(verified,true);
     if(names.Count!=2||layoutTests.Any(s=>!names.Contains(s.Layout,StringComparer.OrdinalIgnoreCase)))throw new System.Exception("Layout regression count mismatch");
    }
    LinkPack.Check(mixed);
    File.AppendAllText(log,"PASS: paper-only + mixed Model/Paper Layout merge, single-sheet merge, DWG reopen."+Environment.NewLine);
    File.AppendAllText(log,"PASS: side DB save/read, pack, merge two models and reopen."+Environment.NewLine);
'@
Write-Source 'Cad\ModelMerge.cs' $m
$core=Read-Source 'Core\Core.csproj'
$core=One $core '<AssemblyName>CadSheetExport.Core</AssemblyName>' '<AssemblyName>CadSheetExport.HeadlessEngine</AssemblyName>'
Write-Source 'Core\Core.csproj' $core
# A minimal Core-only loader makes failure stage and dependency binding visible.
New-Item -ItemType Directory -Path (Join-Path $CadExportRoot 'CoreLoader') -Force|Out-Null
Write-Source 'CoreLoader\CoreLoader.csproj' @'
<Project Sdk="Microsoft.NET.Sdk">
 <PropertyGroup><TargetFramework>net48</TargetFramework><LangVersion>latest</LangVersion><PlatformTarget>x64</PlatformTarget><AssemblyName>CadSheetExport.HeadlessLoader</AssemblyName><Deterministic>true</Deterministic></PropertyGroup>
 <ItemGroup><Reference Include="AcCoreMgd"><HintPath>$(CadPath)/accoremgd.dll</HintPath><Private>false</Private></Reference><Reference Include="AcDbMgd"><HintPath>$(CadPath)/acdbmgd.dll</HintPath><Private>false</Private></Reference></ItemGroup>
</Project>
'@
Write-Source 'CoreLoader\Loader.cs' @'
using System;
using System.IO;
using System.Reflection;
using Autodesk.AutoCAD.Runtime;
[assembly: CommandClass(typeof(CadSheetExport.HeadlessLoader))]
namespace CadSheetExport {
 public class HeadlessLoader {
  [CommandMethod("CSEHEADLESS")]
  public void Execute(){
   string path=Environment.GetEnvironmentVariable("CSE_JOB");
   if(string.IsNullOrWhiteSpace(path)||!File.Exists(path))return;
   string work=Path.GetDirectoryName(Path.GetFullPath(path)),state=Path.Combine(work,"state.txt"),log=Path.Combine(work,"headless_loader.log");
   string dir=Path.GetDirectoryName(typeof(HeadlessLoader).Assembly.Location);
   Action<string> say=s=>File.AppendAllText(log,DateTime.Now.ToString("o")+" | "+s+Environment.NewLine);
   ResolveEventHandler resolver=(sender,e)=>{
    var name=new AssemblyName(e.Name).Name;
    if(name!="CadSso"&&name!="AxDbInterop"&&name!="AcadActiveXInterop")return null;
    string file=Path.Combine(dir,name+".dll");say("RESOLVE "+e.Name+" | "+file);return File.Exists(file)?Assembly.LoadFrom(file):null;
   };
   try{
    File.WriteAllText(state,"LOADER_READY");say("Loader entered | CLR="+Environment.Version+" | "+dir);
    AppDomain.CurrentDomain.AssemblyResolve+=resolver;
    var engine=Assembly.LoadFrom(Path.Combine(dir,"CadSheetExport.HeadlessEngine.dll"));
    foreach(var r in engine.GetReferencedAssemblies())say("ENGINE REFERENCE "+r.FullName);
    var type=engine.GetType("CadSheetExport.Processor",true);
    type.GetMethod("RunHeadless",BindingFlags.Public|BindingFlags.Static).Invoke(null,new object[]{path});
   }catch(System.Exception ex){say(ex.ToString());File.WriteAllText(state,"FAILED | Headless loader: "+ex);}
   finally{AppDomain.CurrentDomain.AssemblyResolve-=resolver;}
  }
 }
}
'@
$c=Read-Source 'Revit\Command.cs'
$c=One $c 'dst.Checked=true;' 'dst.Checked=false;'
$c=One $c 'Silent=false' 'Silent=mode.SelectedIndex!=2'
$c=One $c 'if(System.Diagnostics.Process.GetProcessesByName("acad").Length>0)throw new Exception("Đóng AutoCAD trước khi xuất để không ảnh hưởng bản vẽ đang làm.");' 'if(mode.SelectedIndex==2&&System.Diagnostics.Process.GetProcessesByName("acad").Length>0)throw new Exception("Chế độ Model cần AutoCAD Desktop riêng. Đóng AutoCAD hoặc chọn chế độ Layout chạy nền.");'
$c=One $c 'status.Text="Đang gộp và kiểm tra DWG bằng AutoCAD Desktop...";' 'status.Text=job.Model?"Đang gộp Model...":"Đang xử lý DWG nền, không mở giao diện AutoCAD...";'
$c=One $c 'B - Một DWG / nhiều Layout (Beta)' 'B - Một DWG / nhiều Layout (chạy nền)'
$c=One $c 'A - DWG riêng / Layout' 'A - DWG riêng / Layout (chạy nền)'
$c=One $c 'Chế độ Model chuyển từng Sheet bằng AutoCAD Desktop, sau đó gộp vào một DWG. Tỷ lệ theo khổ giấy. Tiếp tục?' 'Mode C cần phiên AutoCAD Desktop tự động để chạy EXPORTLAYOUT, có thể hiển thị cửa sổ. Mode A/B chạy nền hoàn toàn. Tiếp tục Mode C?'
$c=One $c 'static string Launch(string exe,string year,string job,string seed,bool silent,Action pulse){' @'
  static string Launch(string exe,string year,string job,string seed,bool silent,Action pulse){
   if(silent)return LaunchHeadless(exe,year,job,seed,pulse);
'@
$anchor='  static string Launch(string exe,string year,string job,string seed,bool silent,Action pulse){'
$code=@'
  static string LaunchHeadless(string exe,string year,string job,string seed,Action pulse){
   string work=Path.GetDirectoryName(job),state=Path.Combine(work,"state.txt"),log=Path.Combine(work,"worker_launch.log"),console=Path.Combine(work,"core_console.log");
   string engine=Path.Combine(Path.GetDirectoryName(exe),"accoreconsole.exe");
   string loader=Path.Combine(MachineBundle(year),"Contents","Headless","CadSheetExport.HeadlessLoader.dll");
   if(!File.Exists(engine)||!File.Exists(loader))throw new Exception("Thiếu Core Console hoặc Headless Loader. Không tự mở AutoCAD Desktop.");
   string starter=Path.Combine(Path.GetDirectoryName(seed),"_COREBOOT.dwg");
   File.Copy(seed,starter,true);File.SetAttributes(starter,FileAttributes.Normal);
   string script=Path.Combine(work,"headless.scr");
   // Pass the loader path via environment, no user path embedded in AutoLISP.
   // Security settings are never disabled or changed.
   File.WriteAllText(script,"(command \"_.NETLOAD\" (getenv \"CSE_HEADLESS_LOADER\"))\r\nCSEHEADLESS\r\n_.QUIT\r\n",System.Text.Encoding.ASCII);
   string args="/i \""+starter+"\" /s \""+script+"\"";
   var psi=new System.Diagnostics.ProcessStartInfo(engine,args){UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(engine),CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=System.Text.Encoding.Unicode,StandardErrorEncoding=System.Text.Encoding.Unicode};
   psi.EnvironmentVariables["CSE_JOB"]=job;psi.EnvironmentVariables["CSE_HEADLESS_LOADER"]=loader;psi.EnvironmentVariables["CSE_OWN_WORKER"]="1";
   File.WriteAllText(state,"LAUNCHED");File.AppendAllText(log,DateTime.Now.ToString("o")+" | HEADLESS="+engine+" | LOADER="+loader+" | "+args+Environment.NewLine);
   using(var proc=System.Diagnostics.Process.Start(psi)){
    if(proc==null)throw new Exception("Không khởi động được Core Console.");
    var logLock=new object();
    System.Diagnostics.DataReceivedEventHandler capture=(sender,e)=>{if(e.Data!=null)lock(logLock){try{File.AppendAllText(console,e.Data+Environment.NewLine);}catch(IOException){}}};
    proc.OutputDataReceived+=capture;proc.ErrorDataReceived+=capture;proc.BeginOutputReadLine();proc.BeginErrorReadLine();
    var clock=System.Diagnostics.Stopwatch.StartNew();
    try{
     while(!proc.WaitForExit(250)){
      pulse();string phase;try{phase=File.ReadAllText(state);}catch(IOException){continue;}
      if(clock.Elapsed>TimeSpan.FromHours(2)||(clock.Elapsed>TimeSpan.FromMinutes(3)&&(phase=="LAUNCHED"||phase=="LOADER_READY")))throw new Exception("Headless worker timeout | "+phase+" | "+work);
     }
     proc.WaitForExit();File.AppendAllText(log,"ExitCode="+proc.ExitCode+Environment.NewLine);
    }finally{if(!proc.HasExited){try{proc.Kill();proc.WaitForExit(10000);}catch(Exception){}}}
   }
   string outcome=File.ReadAllText(state);
   if(outcome.StartsWith("SUCCESS |",StringComparison.Ordinal)||outcome.StartsWith("FAILED",StringComparison.Ordinal))return outcome;
   return "FAILED | Headless worker stopped: "+outcome+" | See core_console.log and headless_loader.log. No desktop fallback.";
  }
'@
$c=One $c $anchor ($code+[Environment]::NewLine+$anchor)
Write-Source 'Revit\Command.cs' $c
Write-Host 'V2.5.1: empty-safe ObjectIdCollection, mixed layout runtime regression, Core-only loader, strict headless Mode A/B.'
