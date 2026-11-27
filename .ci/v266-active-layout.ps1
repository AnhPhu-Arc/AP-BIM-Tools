param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}

$p=Read-Source 'Cad\Processor.cs'
# The destination is the actual editor database in a dedicated Core Console,
# not a side database assigned to HostApplicationServices.WorkingDatabase.
$p=One $p 'static void Merge(List<SheetItem> sheets,string path,DwgVersion v,Action<string> say=null){' 'static void MergeActive(List<SheetItem> sheets,string path,DwgVersion v,Action<string> say=null){'
$p=One $p 'var expectedViewports=new List<ViewportSnapshot>();try{using(var target=new Database(true,true)){' 'var expectedViewports=new List<ViewportSnapshot>();try{{var target=Acad.DocumentManager.MdiActiveDocument?.Database;if(target==null||!target.Filename.EndsWith("BOOT.dwg",StringComparison.OrdinalIgnoreCase))throw new System.Exception("Layout merge requires its own active bootstrap DWG.");'
# Restore in the actual current layout, with a newly appended Viewport, not an
# imported viewport with stale native viewport registration.
$p=One $p 'if(st.GetObject(id,OpenMode.ForRead) is Viewport&&!floatingSet.Contains(id))continue;' 'if(st.GetObject(id,OpenMode.ForRead) is Viewport)continue;'
$p=One $p 'var floatingSet=new HashSet<ObjectId>(floating);' ''
$p=One $p 'if(paperIds.Count==0)throw new System.Exception("Layout rỗng: "+name);' 'if(paperIds.Count==0&&floating.Count==0)throw new System.Exception("Layout rỗng: "+name);'
# No deferred translation is left pending if a layout contains only a viewport.
$p=One $p 'if(modelIds.Count>0)src.WblockCloneObjects(modelIds,modelBlock,map,DuplicateRecordCloning.MangleName,true);src.WblockCloneObjects(paperIds,pid,map,DuplicateRecordCloning.MangleName,false);' 'if(modelIds.Count>0)src.WblockCloneObjects(modelIds,modelBlock,map,DuplicateRecordCloning.MangleName,paperIds.Count>0);if(paperIds.Count>0)src.WblockCloneObjects(paperIds,pid,map,DuplicateRecordCloning.MangleName,false);'
$a=$p.IndexOf('if(!pairs.TryGetValue(oldVp.ObjectId,out var clonedId))')
$b=$p.IndexOf('   var snapshot=new ViewportSnapshot',$a)
if($a -lt 0 -or $b -lt 0){throw 'Viewport creation boundary missing'}
$create=@'
var destPaper=(BlockTableRecord)dt.GetObject(pid,OpenMode.ForWrite);
   var cloned=new Viewport();
   ObjectId clonedId=destPaper.AppendEntity(cloned);dt.AddNewlyCreatedDBObject(cloned,true);
   // Only ordinary entity properties cross the source/target database boundary.
   // Map symbol records explicitly; do not copy native viewport registration.
   cloned.LayerId=MapViewportSymbol(src,target.LayerTableId,oldVp.LayerId,pairs);
   cloned.LinetypeId=MapViewportSymbol(src,target.LinetypeTableId,oldVp.LinetypeId,pairs);
   cloned.Color=oldVp.Color;cloned.LineWeight=oldVp.LineWeight;cloned.LinetypeScale=oldVp.LinetypeScale;
   cloned.Transparency=oldVp.Transparency;cloned.Visible=oldVp.Visible;
   viewIds.Add(clonedId);
   if(cloned.OwnerId!=pid)throw new System.Exception("New viewport owner mismatch: "+name);
   say("FRESH VIEWPORT "+name+" | "+oldVp.Handle+" -> "+cloned.Handle);
'@
$p=$p.Substring(0,$a)+$create+[Environment]::NewLine+$p.Substring($b)
$p=One $p 'if(!pairs.TryGetValue(oldLayer,out var newLayer))throw new System.Exception("Không map được VP Freeze layer: "+name);frozen.Add(newLayer);' 'frozen.Add(MapViewportSymbol(src,target.LayerTableId,oldLayer,pairs));'
$p=One $p 'Viewports=viewIds,ViewportStates=snapshots,Entities=paperIds.Count+1' 'Viewports=viewIds,ViewportStates=snapshots,Entities=paperIds.Count+viewIds.Count+1'
# A fresh viewport may not be active until its own layout is current. Do not
# activate it before this point. Set On only on the actual editor database.
$p=One $p 'snapshot.Apply(vp);' 'say("ACTIVE VP APPLY "+l.LayoutName+" | "+vp.Handle+" | current="+LayoutManager.Current.CurrentLayout);snapshot.Apply(vp);'
# Set display mode back to Model after all viewport registrations are complete.
# Do not return to a paper tab until saved; the recipient may open any layout.
$p=One $p 'expectedViewports.AddRange(parts.SelectMany(x=>x.ViewportStates));target.SaveAs(temp,v);}' 'expectedViewports.AddRange(parts.SelectMany(x=>x.ViewportStates));InDb(target,()=>LayoutManager.Current.CurrentLayout="Model");target.SaveAs(temp,v);}'
$anchor='  static void MergeActive(List<SheetItem> sheets,string path,DwgVersion v,Action<string> say=null){'
$engine=@'
  static ObjectId MapViewportSymbol(Database src,ObjectId owner,ObjectId old,Dictionary<ObjectId,ObjectId> pairs){
   if(pairs.TryGetValue(old,out var mapped)&&!mapped.IsNull&&!mapped.IsErased)return mapped;
   var ids=new ObjectIdCollection();ids.Add(old);
   var map=new IdMapping();src.WblockCloneObjects(ids,owner,map,DuplicateRecordCloning.MangleName,false);
   foreach(IdPair pair in map)if(!pair.Value.IsNull)pairs[pair.Key]=pair.Value;
   if(!pairs.TryGetValue(old,out mapped)||mapped.IsNull||mapped.IsErased)throw new System.Exception("Cannot map viewport symbol: "+old.Handle);
   return mapped;
  }
  static void Merge(List<SheetItem> sheets,string path,DwgVersion v,Action<string> say=null){
   if(say==null)say=_=>{};
   if(sheets==null||sheets.Count==0)throw new System.Exception("No sheets to merge.");
   if(File.Exists(path))throw new System.Exception("Merged DWG already exists: "+path);
#if CSE_CORE
   string exe=System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
   if(!Path.GetFileName(exe).Equals("accoreconsole.exe",StringComparison.OrdinalIgnoreCase))throw new System.Exception("Active Layout worker requires Core Console.");
   string folder=Directory.CreateDirectory(Path.Combine(Path.GetDirectoryName(path),"B"+Guid.NewGuid().ToString("N").Substring(0,8))).FullName;
   string boot=Path.Combine(folder,"BOOT.dwg"),plan=Path.Combine(folder,"plan.xml"),script=Path.Combine(folder,"run.scr"),state=Path.Combine(folder,"state.txt"),trace=Path.Combine(folder,"active_merge.log"),console=Path.Combine(folder,"console.log");
   using(var db=new Database(true,true))db.SaveAs(boot,DwgVersion.AC1032);
   new Job{Combine=true,Silent=true,CreateDst=false,Version=v.ToString(),Output=Path.GetFullPath(path),Sheets=sheets}.Write(plan);
   string appRoot=Directory.GetParent(Directory.GetParent(Path.GetDirectoryName(typeof(Processor).Assembly.Location)).FullName).FullName;
   if(!Directory.Exists(Path.Combine(appRoot,"AP.CSE.Headless.bundle")))throw new System.Exception("Active worker AppBundle missing: "+appRoot);
   File.WriteAllText(script,"CSEHEADLESS\r\n_.QUIT\r\n_Y\r\n",System.Text.Encoding.ASCII);
   var psi=new System.Diagnostics.ProcessStartInfo(exe,"/i \""+boot+"\" /al \""+appRoot+"\" /s \""+script+"\""){UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(exe),CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=System.Text.Encoding.Unicode,StandardErrorEncoding=System.Text.Encoding.Unicode};
   psi.EnvironmentVariables["CSE_JOB"]=plan;psi.EnvironmentVariables["CSE_ACTIVE_LAYOUT_PLAN"]=plan;
   psi.EnvironmentVariables["CSE_ACTIVE_PARENT_PID"]=System.Diagnostics.Process.GetCurrentProcess().Id.ToString();
   say("ACTIVE LAYOUT WORKER START | "+folder);
   using(var child=System.Diagnostics.Process.Start(psi)){
    if(child==null)throw new System.Exception("Cannot start active Layout worker.");
    var gate=new object();
    System.Diagnostics.DataReceivedEventHandler receive=(sender,e)=>{if(e.Data!=null)lock(gate){try{File.AppendAllText(console,e.Data+Environment.NewLine);}catch(IOException){}}};
    child.OutputDataReceived+=receive;child.ErrorDataReceived+=receive;child.BeginOutputReadLine();child.BeginErrorReadLine();
    var clock=System.Diagnostics.Stopwatch.StartNew();long lastLength=0;var lastProgress=clock.Elapsed;TimeSpan? done=null;
    try{
     while(!child.WaitForExit(250)){
      string status="";try{if(File.Exists(state))status=File.ReadAllText(state);}catch(IOException){}
      if(File.Exists(trace)){
       long size=new FileInfo(trace).Length;
       if(size!=lastLength){lastLength=size;lastProgress=clock.Elapsed;say("ACTIVE LAYOUT PROGRESS | "+size+" bytes | "+folder);}
      }
      if(status.StartsWith("SUCCESS |",StringComparison.Ordinal)||status.StartsWith("FAILED",StringComparison.Ordinal)){
       if(!done.HasValue)done=clock.Elapsed;
       if(clock.Elapsed-done.Value>TimeSpan.FromSeconds(5)){child.Kill();child.WaitForExit(10000);break;}
      }else if(clock.Elapsed-lastProgress>TimeSpan.FromMinutes(2))throw new System.Exception("Active Layout worker stalled: "+folder);
     }
    }finally{if(!child.HasExited){try{child.Kill();child.WaitForExit(10000);}catch(System.Exception){}}}
   }
   string result=File.Exists(state)?File.ReadAllText(state):"FAILED | no active worker result";
   if(!result.StartsWith("SUCCESS |",StringComparison.Ordinal)||!File.Exists(path))throw new System.Exception("Active Layout merge: "+result+" | "+folder);
   // Reopen in the original worker only after the editor process has exited.
   using(var verify=Open(path)){
    VerifyModelIsolation(verify);
    var names=Layouts(verify,true);
    if(names.Count!=sheets.Count||sheets.Any(s=>!names.Contains(s.Layout,StringComparer.OrdinalIgnoreCase)))throw new System.Exception("Active Layout output count mismatch.");
   }
   say("ACTIVE LAYOUT WORKER PASS | "+path);
#else
   throw new System.Exception("Use the headless Layout worker for Mode B.");
#endif
  }
  public static void RunActiveLayout(string plan){
   string folder=Path.GetDirectoryName(Path.GetFullPath(plan)),state=Path.Combine(folder,"state.txt"),trace=Path.Combine(folder,"active_merge.log");
   Action<string> say=t=>File.AppendAllText(trace,DateTime.Now.ToString("o")+" "+t+Environment.NewLine);
   // If Revit cancels the parent worker, this owned child must not remain alive.
   System.Threading.Timer parentWatch=null;
   try{
    int parentPid;if(!int.TryParse(Environment.GetEnvironmentVariable("CSE_ACTIVE_PARENT_PID"),out parentPid))throw new System.Exception("Missing active worker parent");
    parentWatch=new System.Threading.Timer(_=>{
     try{using(var parent=System.Diagnostics.Process.GetProcessById(parentPid)){if(parent.HasExited)System.Diagnostics.Process.GetCurrentProcess().Kill();}}
     catch(ArgumentException){System.Diagnostics.Process.GetCurrentProcess().Kill();}
     catch(InvalidOperationException){}
    },null,1000,1000);
    var job=Job.Read(plan);
    if(job.Sheets.Count==0||job.Model||!job.Combine)throw new System.Exception("Invalid active Layout plan.");
    File.WriteAllText(state,"PROCESSING");say("ACTIVE DOCUMENT "+Acad.DocumentManager.MdiActiveDocument?.Database.Filename);
    MergeActive(job.Sheets,job.Output,(DwgVersion)Enum.Parse(typeof(DwgVersion),job.Version),say);
    File.WriteAllText(state,"SUCCESS | ACTIVE LAYOUT "+job.Sheets.Count+"/"+job.Sheets.Count);
   }catch(System.Exception ex){say(ex.ToString());File.WriteAllText(state,"FAILED | "+ex);}
   finally{if(parentWatch!=null)parentWatch.Dispose();}
  }
'@
$p=One $p $anchor ($engine+[Environment]::NewLine+$anchor)
Write-Source 'Cad\Processor.cs' $p

$m=Read-Source 'Cad\ModelMerge.cs'
# Explicit guard for uncommon 3D/viewport styles: do not silently downgrade.
# Standard Revit 2D views, including straight polygon clips, remain supported.
$m=One $m 'Id=id;LayoutName=name;HandleText=id.Handle.ToString();' 'Id=id;LayoutName=name;HandleText=id.Handle.ToString();if(src.PerspectiveOn||src.FrontClipOn||src.BackClipOn)throw new System.Exception("Mode B viewport camera not qualified: "+name+" | "+src.Handle);'
Write-Source 'Cad\ModelMerge.cs' $m

$l=Read-Source 'CoreLoader\Loader.cs'
$l=One $l 'type.GetMethod("RunHeadless",BindingFlags.Public|BindingFlags.Static).Invoke(null,new object[]{path});' 'string method=string.Equals(Environment.GetEnvironmentVariable("CSE_ACTIVE_LAYOUT_PLAN"),path,StringComparison.OrdinalIgnoreCase)?"RunActiveLayout":"RunHeadless";type.GetMethod(method,BindingFlags.Public|BindingFlags.Static).Invoke(null,new object[]{path});'
Write-Source 'CoreLoader\Loader.cs' $l
# Correct existing QUIT discard answer; no document is being saved by QUIT.
$c=Read-Source 'Revit\Command.cs'
$c=One $c 'CSEHEADLESS\r\n_.QUIT\r\n_N\r\n",System.Text.Encoding.ASCII);' 'CSEHEADLESS\r\n_.QUIT\r\n_Y\r\n",System.Text.Encoding.ASCII);'
Write-Source 'Revit\Command.cs' $c
Write-Host 'V2.6.6 Mode B: dedicated active Core Console drawing, fresh resident viewport entities, original snapshot validation, owned child lifecycle; A/C unchanged.'
