param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}
$c=Read-Source 'Revit\Command.cs'
$c=One $c 'Path.Combine(Path.GetTempPath(),"CADSheetExport",Guid.NewGuid().ToString("N"))' 'Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CSE","J"+Guid.NewGuid().ToString("N").Substring(0,12))'
$c=One $c 'Silent=mode.SelectedIndex!=2' 'Silent=true'
$c=One $c 'psi.EnvironmentVariables["CSE_JOB"]=job;' 'psi.EnvironmentVariables["CSE_ACAD_EXE"]=exe;psi.EnvironmentVariables["CSE_JOB"]=job;'
$c=One $c 'string starter=Path.Combine(Path.GetDirectoryName(seed),"_CSE_SEED_"+Guid.NewGuid().ToString("N")+".dwg");File.Copy(seed,starter);' 'string starter=Path.Combine(Path.GetDirectoryName(seed),"_BOOT.dwg");File.Copy(seed,starter,true);File.SetAttributes(starter,FileAttributes.Normal);'
$c=One $c 'Chế độ Model dùng EXPORTLAYOUT, cần AutoCAD Desktop chạy tạm thời và sẽ đóng khi xong. Tiếp tục?' 'Chế độ Model chuyển từng Sheet bằng phiên AutoCAD riêng, sau đó gộp nền. Có thể lâu hơn chế độ Layout. Tiếp tục?'
Write-Source 'Revit\Command.cs' $c
$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'if(Job.Read(path).Model)throw new System.Exception("Model requires desktop EXPORTLAYOUT");' ''
$p=One $p 'string runId="CSE_"+Guid.NewGuid().ToString("N").Substring(0,20);' 'string runId="CSE_"+Guid.NewGuid().ToString("N").Substring(0,16);'
$p=One $p 'Path.Combine(work,"stage_"+runId.Substring(4,8))' 'Path.Combine(work,"S")'
$p=One $p 'string stem=j.Combine||j.Model?"_CSE_SHEET_"+Guid.NewGuid().ToString("N"):Names.RequestedStem(s.FileName,".dwg");' 'string stem="S"+(success.Count+1).ToString("D4");'
$p=One $p 'pack.Publish(s.Source,final,Path.Combine(runId,Names.FileStem(s.Number)+"_"+success.Count.ToString("D4")));' 'Say("PACK SOURCE "+s.Number+" | "+s.Source+" -> "+final);pack.Publish(s.Source,final,Path.Combine(runId,"L"+(success.Count+1).ToString("D4")));'
$p=One $p 's.FinalDwg=Normalize(final,s.Layout,v);LinkPack.Check(final);' 'Say("NORMALIZE "+s.Number+" | "+final);s.FinalDwg=Normalize(final,s.Layout,v);Say("CHECK LINKS "+s.Number);LinkPack.Check(final);'
$p=One $p 's.Status="LAYOUT_ERROR";s.Detail=ex.ToString();throw;' 's.Status="LAYOUT_ERROR";s.Detail=ex.ToString();throw new System.Exception("Sheet "+s.Number+" | "+ex.Message,ex);'
$p=One $p 'string merged=Path.Combine(stage,Names.RequestedStem(j.CombinedName,".dwg")+".dwg");' 'string merged=Path.Combine(stage,"M.dwg");'
$old=@'
#if CSE_CORE
      throw new System.Exception("Model requires desktop EXPORTLAYOUT");
#else
      await MergeModel(success,merged,v,j.Columns,j.Gap,work,Say);
#endif
'@
$p=One $p $old 'MergeModelIsolated(success,merged,v,j.Columns,j.Gap,work,Say);'
$p=One $p 'LinkPack.Check(merged);' 'Say("CHECK MERGED LINKS "+merged);LinkPack.MakePortable(merged,v,Say);LinkPack.Check(merged);'
$p=One $p 'string src=group.Key,name=Path.GetFileName(src),dest=Path.Combine(output,name);' 'string src=group.Key,name=j.Combine||j.Model?Names.RequestedStem(j.CombinedName,".dwg")+".dwg":Names.RequestedStem(group.First().FileName,".dwg")+".dwg",dest=Path.Combine(output,name);'
$p=One $p 'string pending=Path.Combine(output,".cse_"+Guid.NewGuid().ToString("N")+".tmp");' 'string pending=Path.Combine(output,".cse_"+Guid.NewGuid().ToString("N").Substring(0,12)+".tmp");'
$p=One $p 'static Database Open(string p){var db=new Database(false,true);try{db.ReadDwgFile(p,FileOpenMode.OpenForReadAndAllShare,true,"");db.CloseInput(true);return db;}catch{db.Dispose();throw;}}' @'
static Database Open(string p){
   p=Path.GetFullPath(p);
   var db=new Database(false,true);
   try{
    if(!File.Exists(p))throw new FileNotFoundException("DWG not found",p);
    db.ReadDwgFile(p,FileOpenMode.OpenForReadAndAllShare,true,"");
    db.CloseInput(true);return db;
   }catch(System.Exception ex){db.Dispose();throw new System.Exception("READ DWG: "+p+" | "+ex.Message,ex);}
  }
'@
$p=One $p 'string temp=Path.Combine(Path.GetDirectoryName(path),"_cse_"+Guid.NewGuid().ToString("N")+".dwg");' 'string temp=Path.Combine(Path.GetDirectoryName(path),"N"+Guid.NewGuid().ToString("N").Substring(0,8)+".dwg");'
$p=One $p 'lm.CurrentLayout=newName;});db.SaveAs(temp,version);' 'lm.CurrentLayout=newName;});try{db.SaveAs(temp,version);}catch(System.Exception ex){throw new System.Exception("NORMALIZE SAVE: "+temp+" | "+ex.Message,ex);}'
Write-Source 'Cad\Processor.cs' $p
$l=Read-Source 'Cad\LinkPack.cs'
$l=One $l 'Directory.CreateDirectory(Path.GetDirectoryName(final));File.Copy(source,final,false);string temp=Path.Combine(Path.GetDirectoryName(final),"_CSE_SAVE_"+Guid.NewGuid().ToString("N")+".dwg");try{using(var db=Open(final))' 'Directory.CreateDirectory(Path.GetDirectoryName(final));string temp=Path.Combine(Path.GetDirectoryName(final),"P"+Guid.NewGuid().ToString("N").Substring(0,8)+".dwg");string step="READ SOURCE";try{say("PACK READ "+source);using(var db=Open(source))'
$l=One $l 'tr.Commit();}});db.SaveAs(temp,version);}File.Replace(temp,final,null);}finally{if(File.Exists(temp))File.Delete(temp);}' 'tr.Commit();}});step="SAVE STAGED";say("PACK SAVE "+temp);db.SaveAs(temp,version);}step="MOVE STAGED";File.Move(temp,final);}catch(System.Exception ex){throw new System.Exception(step+" | "+source+" -> "+final+" | "+ex.Message,ex);}finally{if(File.Exists(temp))File.Delete(temp);}'
# Canonicalize references after native EXPORTLAYOUT, before moving the output to another directory.
$anchor='   public void Publish(string source,string final,string stem)'
$helper=@'
   public static void MakePortable(string path,DwgVersion version,Action<string> say){
    string root=Path.GetDirectoryName(Path.GetFullPath(path));
    string tmp=Path.Combine(root,"R"+Guid.NewGuid().ToString("N").Substring(0,8)+".dwg");
    bool changed=false;
    try{
     using(var db=Open(path)){
      InDb(db,()=>{using(var tr=db.TransactionManager.StartTransaction()){
       var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);
       var images=new HashSet<ObjectId>();var underlays=new HashSet<ObjectId>();
       string ConvertRef(string value){
        string resolved=CheckRef(path,value,root);
        string rel=Relative(root,resolved);
        if(!string.Equals(value,rel,StringComparison.OrdinalIgnoreCase)){changed=true;say("REBASE "+value+" -> "+rel);}
        return rel;
       }
       foreach(ObjectId bid in bt){
        var b=(BlockTableRecord)tr.GetObject(bid,OpenMode.ForRead);if(b.IsDependent)continue;
        if(b.IsFromExternalReference||b.IsFromOverlayReference){string rel=ConvertRef(b.PathName);if(rel!=b.PathName){b.UpgradeOpen();b.PathName=rel;}continue;}
        foreach(ObjectId id in b){var obj=tr.GetObject(id,OpenMode.ForRead);if(obj is RasterImage im)images.Add(im.ImageDefId);if(obj is UnderlayReference u)underlays.Add(u.DefinitionId);}
       }
       foreach(var id in images){var def=(RasterImageDef)tr.GetObject(id,OpenMode.ForRead);string rel=ConvertRef(def.SourceFileName);if(rel!=def.SourceFileName){def.UpgradeOpen();def.SourceFileName=rel;}}
       foreach(var id in underlays){var def=(UnderlayDefinition)tr.GetObject(id,OpenMode.ForRead);string rel=ConvertRef(def.SourceFileName);if(rel!=def.SourceFileName){def.UpgradeOpen();var prop=def.GetType().GetProperty("SourceFileName");if(prop==null||!prop.CanWrite)throw new System.Exception("Underlay path cannot be rebased");prop.SetValue(def,rel);}}
       var nod=(DBDictionary)tr.GetObject(db.NamedObjectsDictionaryId,OpenMode.ForRead);
       if(nod.Contains("ACAD_DATALINK")){var dict=(DBDictionary)tr.GetObject(nod.GetAt("ACAD_DATALINK"),OpenMode.ForRead);foreach(DBDictionaryEntry e in dict){var obj=tr.GetObject(e.Value,OpenMode.ForRead);var prop=obj.GetType().GetProperty("ConnectionString");string val=(string)prop?.GetValue(obj);var m=Regex.Match(val??"",@"^(?<path>.+?\.(?:xlsx|xlsm|xls|xlsb|csv))(?<suffix>.*)$",RegexOptions.IgnoreCase);if(!m.Success)throw new System.Exception("Unverified data link "+e.Key);string rel=ConvertRef(m.Groups["path"].Value.Trim('"'))+m.Groups["suffix"].Value;if(rel!=val){obj.UpgradeOpen();prop.SetValue(obj,rel);}}}
       tr.Commit();
      }});
      if(changed)db.SaveAs(tmp,version);
     }
     if(changed)File.Replace(tmp,path,null);
    }finally{if(File.Exists(tmp))File.Delete(tmp);}
   }
'@
$l=One $l $anchor ($helper+[Environment]::NewLine+$anchor)
Write-Source 'Cad\LinkPack.cs' $l
# Replace queued MDI operations with an isolated desktop command process per sheet.
# The parent is Core Console. No document-context API is used by this merge path.
$m=Read-Source 'Cad\ModelMerge.cs'
$cloneStart=$m.IndexOf('   using(var target=new Database(true,true))')
$cloneEnd=$m.IndexOf('    complete=true;',$cloneStart)
if($cloneStart -lt 0 -or $cloneEnd -lt 0){throw 'Clone boundaries missing'}
$clone=$m.Substring($cloneStart,$cloneEnd-$cloneStart)
$clone=$clone.Replace('target.SaveAs(path,version);','target.SaveAs(path,version);')
$prefix=@'
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
namespace CadSheetExport {
 public partial class Processor {
  // Native startup script; input and output filenames are short and kept beside Links.
  // No nested document, Editor.Command, ExecuteInCommandContextAsync, or COM SendCommand.
  static void NativeExportIsolated(string exe,SheetItem sheet,string flat,string work,int index,Action<string> say){
   if(System.Diagnostics.Process.GetProcessesByName("acad").Length!=0)throw new System.Exception("AutoCAD desktop already running; isolated conversion refused.");
   string script=Path.Combine(work,"F"+index.ToString("D4")+".scr");
   string status=Path.Combine(work,"F"+index.ToString("D4")+".txt");
   string body=@"(progn (setq csefd (getvar ""FILEDIA"") csecd (getvar ""CMDDIA"")) (setvar ""FILEDIA"" 0) (setvar ""CMDDIA"" 0) (setq cser (vl-catch-all-apply '(lambda () (setvar ""CTAB"" (getenv ""CSE_FLAT_LAYOUT"")) (if (> (getvar ""CVPORT"") 1) (command ""_.PSPACE"")) (command ""_.EXPORTLAYOUT"" (strcat (getvar ""DWGPREFIX"") (getenv ""CSE_FLAT_NAME"")))))) (setq csef (open (getenv ""CSE_FLAT_STATUS"") ""w"")) (if csef (progn (write-line (if (vl-catch-all-error-p cser) (vl-catch-all-error-message cser) ""COMMAND_RETURNED"") csef) (close csef))) (setvar ""FILEDIA"" csefd) (setvar ""CMDDIA"" csecd) (princ))";
   File.WriteAllText(script,body+"\r\n",System.Text.Encoding.ASCII);
   var psi=new System.Diagnostics.ProcessStartInfo(exe,"\""+sheet.FinalDwg+"\" /nologo /b \""+script+"\""){UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(exe),WindowStyle=System.Diagnostics.ProcessWindowStyle.Minimized};
   psi.EnvironmentVariables.Remove("CSE_JOB");
   psi.EnvironmentVariables.Remove("CSE_OWN_WORKER");
   psi.EnvironmentVariables["CSE_FLAT_LAYOUT"]=sheet.Layout;
   psi.EnvironmentVariables["CSE_FLAT_NAME"]=Path.GetFileName(flat);
   psi.EnvironmentVariables["CSE_FLAT_STATUS"]=status;
   say("NATIVE EXPORT "+sheet.Number+" | "+sheet.FinalDwg+" -> "+flat);
   using(var proc=System.Diagnostics.Process.Start(psi)){
    if(proc==null)throw new System.Exception("Cannot start AutoCAD desktop");
    var clock=System.Diagnostics.Stopwatch.StartNew();
    bool completed=false;
    try{
     while(!proc.HasExited&&clock.Elapsed<TimeSpan.FromMinutes(5)){
      if(File.Exists(status)){
       string detail;try{detail=File.ReadAllText(status);}catch(IOException){System.Threading.Thread.Sleep(250);continue;}
       say("NATIVE RESULT "+sheet.Number+" | "+detail.Trim());
       if(!detail.Trim().Equals("COMMAND_RETURNED",StringComparison.Ordinal))throw new System.Exception("EXPORTLAYOUT native: "+detail);
       if(!File.Exists(flat)||new FileInfo(flat).Length==0)throw new System.Exception("EXPORTLAYOUT returned without DWG: "+flat);
       completed=true;break;
      }
      System.Threading.Thread.Sleep(250);
     }
     if(!completed)throw new System.Exception("Native EXPORTLAYOUT timed out or process exited before status: "+sheet.Number);
     // This process was launched solely for this staged sheet; do not save changes to it.
     // Try graceful close; then terminate only the owned process if a modal prompt remains.
     try{proc.CloseMainWindow();}catch(System.Exception){}
     if(!proc.WaitForExit(8000)){proc.Kill();if(!proc.WaitForExit(10000))throw new System.Exception("Owned AutoCAD did not close");}
    }finally{
     if(!proc.HasExited){try{proc.Kill();proc.WaitForExit(10000);}catch(System.Exception ex){say("Owned worker cleanup: "+ex.Message);}}
    }
   }
   using(var check=Open(flat))using(var tr=check.TransactionManager.StartTransaction()){
    var bt=(BlockTable)tr.GetObject(check.BlockTableId,OpenMode.ForRead);
    var model=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
    if(!model.Cast<ObjectId>().Any())throw new System.Exception("Empty flattened sheet: "+sheet.Number);
   }
   say("FLAT OK "+sheet.Number+" | bytes="+new FileInfo(flat).Length);
  }
  static void MergeModelIsolated(List<SheetItem> sheets,string path,DwgVersion version,int columns,double gap,string work,Action<string> say){
   if(columns<1||gap<0)throw new System.Exception("Invalid model grid");
   string exe=Environment.GetEnvironmentVariable("CSE_ACAD_EXE");
   if(string.IsNullOrWhiteSpace(exe)||!File.Exists(exe)||!Path.GetFileName(exe).Equals("acad.exe",StringComparison.OrdinalIgnoreCase))throw new System.Exception("Invalid selected AutoCAD desktop");
   string stage="START",root=Path.GetDirectoryName(path);
   var flats=new List<string>();
   try{
    for(int i=0;i<sheets.Count;i++){
     stage="FLATTEN "+sheets[i].Number;
     string flat=Path.Combine(root,"F"+(i+1).ToString("D4")+".dwg");flats.Add(flat);
     NativeExportIsolated(exe,sheets[i],flat,work,i+1,say);
     LinkPack.MakePortable(flat,version,say);
     LinkPack.Check(flat);
    }
    stage="CLONE";
'@
$tail=@'
    say("MODEL VERIFIED: "+sheets.Count+" sheets");
   }catch(System.Exception ex){say("MODEL FAILED AT "+stage+" | "+ex);throw new System.Exception(stage+": "+ex.Message,ex);}
  }
 }
}
'@
# Original clone algorithm retained: per-sheet block, MangleName, geometry bounds and count.
# Remove desktop-only file and replace it with isolated process implementation for both targets.
Write-Source 'Cad\ModelMerge.cs' ($prefix+[Environment]::NewLine+$clone+[Environment]::NewLine+$tail)
$core=Read-Source 'Core\Core.csproj'
$core=One $core '<Compile Include="../Cad/Processor.cs" Link="Processor.cs"/>' '<Compile Include="../Cad/Processor.cs" Link="Processor.cs"/><Compile Include="../Cad/ModelMerge.cs" Link="ModelMerge.cs"/>'
Write-Source 'Core\Core.csproj' $core
Write-Host 'V2.4.4 staged file hardening + isolated native Model conversion (runtime validation required).'
