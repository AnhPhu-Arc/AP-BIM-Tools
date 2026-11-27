param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}
# Explicit AppBundle startup, not NETLOAD. Preserve AutoCAD security policy.
$c=Read-Source 'Revit\Command.cs'
$c=One $c 'string loader=Path.Combine(MachineBundle(year),"Contents","Headless","CadSheetExport.HeadlessLoader.dll");' 'string appRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"AP-BIM Tools","CAD Engine",year,"HeadlessApp");string loader=Path.Combine(appRoot,"AP.CSE.Headless.bundle","Contents","CadSheetExport.HeadlessLoader.dll");'
$c=One $c 'File.WriteAllText(script,"(command \"_.NETLOAD\" (getenv \"CSE_HEADLESS_LOADER\"))\r\nCSEHEADLESS\r\n_.QUIT\r\n",System.Text.Encoding.ASCII);' 'File.WriteAllText(script,"(progn (princ \"\\nCSE host ACADVER=\") (princ (getvar \"ACADVER\")) (princ \" SECURELOAD=\") (princ (getvar \"SECURELOAD\")) (princ \" TRUSTEDPATHS=\") (princ (getvar \"TRUSTEDPATHS\")) (princ))\r\nCSEHEADLESS\r\n_.QUIT\r\n",System.Text.Encoding.ASCII);'
$c=One $c 'string args="/i \""+starter+"\" /s \""+script+"\"";' 'string args="/i \""+starter+"\" /al \""+appRoot+"\" /s \""+script+"\"";'
$c=One $c 'File.WriteAllText(state,"LAUNCHED");File.AppendAllText(log,DateTime.Now.ToString("o")+" | HEADLESS="+engine+" | LOADER="+loader+" | "+args+Environment.NewLine);' 'File.WriteAllText(state,"LAUNCHED");File.AppendAllText(log,DateTime.Now.ToString("o")+" | HEADLESS="+engine+" | APPBUNDLE="+appRoot+" | LOADER="+loader+" | "+args+Environment.NewLine);using(var sha=System.Security.Cryptography.SHA256.Create())using(var f=File.OpenRead(loader))File.AppendAllText(log,"LOADER SHA256="+BitConverter.ToString(sha.ComputeHash(f)).Replace("-","")+Environment.NewLine);'
# Runtime qualification, not final Mode C: never open desktop from this candidate.
$c=One $c 'Silent=mode.SelectedIndex!=2' 'Silent=true'
$c=One $c 'if(mode.SelectedIndex==2&&System.Diagnostics.Process.GetProcessesByName("acad").Length>0)throw new Exception("Chế độ Model cần AutoCAD Desktop riêng. Đóng AutoCAD hoặc chọn chế độ Layout chạy nền.");' ''
# Remove old UI-thread desktop flatten; processor will qualify DWG layout content.
$start=$c.IndexOf('   if(job.Model){')
$end=$c.IndexOf('   status.Text=job.Model?"Đang gộp Model...":',$start)
if($start -lt 0 -or $end -lt 0){throw 'Desktop flatten block missing'}
$c=$c.Substring(0,$start)+$c.Substring($end)
$c=One $c 'Mode C cần phiên AutoCAD Desktop tự động để chạy EXPORTLAYOUT, có thể hiển thị cửa sổ. Mode A/B chạy nền hoàn toàn. Tiếp tục Mode C?' 'Mode C thử nghiệm chạy nền: chỉ hỗ trợ Sheet không có viewport nổi. Sheet có viewport sẽ dừng an toàn, không mở AutoCAD Desktop. Tiếp tục?'
$c=One $c 'if(silent)return LaunchHeadless(exe,year,job,seed,pulse);' 'return LaunchHeadless(exe,year,job,seed,pulse);'
# Remove now-unreachable desktop launch body and unused native desktop flatten method.
$start=$c.IndexOf('  static string FlattenNative(')
$end=$c.IndexOf('  static string LaunchHeadless(',$start)
if($start -lt 0 -or $end -lt 0){throw 'Native desktop method boundary missing'}
$c=$c.Substring(0,$start)+$c.Substring($end)
$start=$c.IndexOf('  static string Launch(string exe,string year,string job,string seed,bool silent,Action pulse){')
if($start -lt 0){throw 'Launch method missing'}
$c=$c.Substring(0,$start)+@'
  static string Launch(string exe,string year,string job,string seed,bool silent,Action pulse){
   return LaunchHeadless(exe,year,job,seed,pulse);
  }
 }
}
'@
Write-Source 'Revit\Command.cs' $c
# Earliest possible managed startup acknowledgement.
$l=Read-Source 'CoreLoader\Loader.cs'
$l=One $l 'public class HeadlessLoader {' @'
 public class HeadlessLoader : IExtensionApplication {
  public void Initialize(){
   try{
    string path=Environment.GetEnvironmentVariable("CSE_JOB");
    if(string.IsNullOrWhiteSpace(path))return;
    string work=Path.GetDirectoryName(Path.GetFullPath(path));
    if(!Directory.Exists(work))return;
    File.AppendAllText(Path.Combine(work,"headless_loader.log"),DateTime.Now.ToString("o")+" | INIT | "+typeof(HeadlessLoader).Assembly.Location+" | CLR="+Environment.Version+Environment.NewLine);
   }catch(System.Exception ex){System.Console.WriteLine("CSE loader initialization log: "+ex.Message);}
  }
  public void Terminate(){}
'@
Write-Source 'CoreLoader\Loader.cs' $l
$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'if(Job.Read(path).Model)throw new System.Exception("Native EXPORTLAYOUT is not supported by this headless worker.");' 'InspectSourceLayouts(Job.Read(path),work);'
$p=One $p 's.FinalDwg=j.Model?final:Normalize(final,s.Layout,v);if(j.Model)ValidateFlattened(final,s.Number);' 's.FinalDwg=Normalize(final,s.Layout,v);'
$p=One $p 'MergeFlattened(success,merged,v,j.Columns,j.Gap,Say);' @'
foreach(var s in success){
       string flat=Path.Combine(stage,"F"+(success.IndexOf(s)+1).ToString("D4")+".dwg");
       FlattenPaperOnly(s.FinalDwg,s.Layout,flat,v,Say);
       s.FinalDwg=flat;
      }
      MergeFlattened(success,merged,v,j.Columns,j.Gap,Say);
'@
Write-Source 'Cad\Processor.cs' $p
$m=Read-Source 'Cad\ModelMerge.cs'
$anchor='  static void ValidateFlattened(string flat,string number){'
$code=@'
  static void InspectSourceLayouts(Job job,string work){
   string log=Path.Combine(work,"layout_inventory.log");
   foreach(var s in job.Sheets){
    try{
     using(var db=Open(s.Source))using(var tr=db.TransactionManager.StartTransaction()){
      var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);
      var model=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
      File.AppendAllText(log,s.Number+" | model="+model.Cast<ObjectId>().Count()+" | units="+db.Insunits+Environment.NewLine);
      var ld=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
      foreach(DBDictionaryEntry e in ld){
       var layout=(Layout)tr.GetObject(e.Value,OpenMode.ForRead);
       if(layout.ModelType)continue;
       var paper=(BlockTableRecord)tr.GetObject(layout.BlockTableRecordId,OpenMode.ForRead);
       var ids=layout.GetViewports();ObjectId overall=ids.Count>0?ids[0]:ObjectId.Null;
       File.AppendAllText(log," LAYOUT "+layout.LayoutName+" | objects="+paper.Cast<ObjectId>().Count()+Environment.NewLine);
       foreach(ObjectId id in paper){
        if(id==overall)continue;
        var obj=tr.GetObject(id,OpenMode.ForRead);
        if(obj is Viewport vp && vp.Number!=1)
         File.AppendAllText(log,"  VP "+vp.Handle+" | center="+vp.CenterPoint+" | direction="+vp.ViewDirection+" | target="+vp.ViewTarget+" | viewCenter="+vp.ViewCenter+" | viewHeight="+vp.ViewHeight+" | width="+vp.Width+" | height="+vp.Height+" | twist="+vp.TwistAngle+" | frozen="+vp.GetFrozenLayers().Count+Environment.NewLine);
       }
      }
     }
    }catch(System.Exception ex){File.AppendAllText(log,"INSPECT ERROR "+s.Number+" | "+ex+Environment.NewLine);throw;}
   }
  }
  // First qualification milestone: a paper-only Sheet can be losslessly
  // cloned at paper units. Refuse floating viewports rather than silently
  // omitting or distorting model geometry. General viewport projection is TBD.
  static void FlattenPaperOnly(string input,string layoutName,string output,DwgVersion version,Action<string> say){
   using(var src=Open(input))using(var st=src.TransactionManager.StartTransaction())using(var dest=new Database(true,true)){
    var ld=(DBDictionary)st.GetObject(src.LayoutDictionaryId,OpenMode.ForRead);
    if(!ld.Contains(layoutName))throw new System.Exception("Layout not found: "+layoutName);
    var layout=(Layout)st.GetObject(ld.GetAt(layoutName),OpenMode.ForRead);
    var paper=(BlockTableRecord)st.GetObject(layout.BlockTableRecordId,OpenMode.ForRead);
    var vpIds=layout.GetViewports();ObjectId overall=vpIds.Count>0?vpIds[0]:ObjectId.Null;
    var objects=new ObjectIdCollection();
    foreach(ObjectId id in paper){
     var entity=st.GetObject(id,OpenMode.ForRead) as Entity;
     if(entity==null)continue;
     if(entity is Viewport vp){
      if(id==overall||vp.Number==1)continue;
      throw new System.Exception("FULL HEADLESS MODE C NOT YET QUALIFIED FOR FLOATING VIEWPORT: "+layoutName+" | "+vp.Handle+" | see layout_inventory.log");
     }
     if(entity is ProxyEntity||entity is Ole2Frame||entity is UnderlayReference)throw new System.Exception("Unsupported paper entity "+entity.GetType().Name+" in "+layoutName);
     objects.Add(id);
    }
    if(objects.Count==0)throw new System.Exception("Empty paper layout: "+layoutName);
    dest.Insunits=src.Insunits;
    using(var dt=dest.TransactionManager.StartTransaction()){
     var bt=(BlockTable)dt.GetObject(dest.BlockTableId,OpenMode.ForRead);
     src.WblockCloneObjects(objects,bt[BlockTableRecord.ModelSpace],new IdMapping(),DuplicateRecordCloning.MangleName,false);
     dt.Commit();
    }
    dest.SaveAs(output,version);
   }
   ValidateFlattened(output,layoutName);say("PAPER-ONLY FLAT "+layoutName);
  }
'@
$m=One $m $anchor ($code+[Environment]::NewLine+$anchor)
Write-Source 'Cad\ModelMerge.cs' $m
Write-Host 'Qualification: explicit AppBundle, loader INIT, DWG inventory, paper-only Mode C; floating viewport conversion not qualified.'
