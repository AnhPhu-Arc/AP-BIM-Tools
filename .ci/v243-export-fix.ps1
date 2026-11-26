param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}
$job=Read-Source 'Shared\Job.cs'
$job=One $job 'public List<SheetItem> Sheets' 'public List<string> ApprovedOverwrite {get;set;} = new List<string>(); public List<SheetItem> Sheets'
$job=One $job 'public static string FileStem(string s)' @'
public static string RequestedStem(string text,string extension) {
   string n=(text??"").Trim();
   if(n.EndsWith(extension,StringComparison.OrdinalIgnoreCase))n=n.Substring(0,n.Length-extension.Length);
   if(string.IsNullOrWhiteSpace(n)||!string.Equals(n,FileStem(n),StringComparison.Ordinal))throw new System.Exception("Tên file không hợp lệ: "+text);
   return n;
  }
  public static string FileStem(string s)
'@
Write-Source 'Shared\Job.cs' $job
$c=Read-Source 'Revit\Command.cs'
$c=One $c 'Thư mục đầu ra trực tiếp (không ghi đè)' 'Thư mục đầu ra (chỉ hỏi khi trùng tên)'
$c=One $c 'var root=Path.GetFullPath(folder.Text);if(Directory.GetFiles(root,"*.dwg").Length>0||Directory.GetFiles(root,"*.dst").Length>0)throw new Exception("Thư mục đã có DWG/DST. Chọn thư mục khác hoặc di chuyển hồ sơ cũ; không tự ghi đè.");' 'var root=Path.GetFullPath(folder.Text);'
$c=One $c 'var names=chosen.Select(sh=>Names.Unique(Render(sh,pattern),used)).ToList();' 'var names=chosen.Select(sh=>Render(sh,pattern)).ToList();if(mode.SelectedIndex==0&&names.Distinct(StringComparer.OrdinalIgnoreCase).Count()!=names.Count)throw new Exception("Quy tắc đặt tên tạo DWG trùng nhau. Hãy chọn thêm tham số phân biệt Sheet.");'
$c=One $c 'CombinedName=Names.FileStem(combined.Text),SetName=Names.FileStem(setName.Text)' 'CombinedName=mode.SelectedIndex==0?"Combined":Names.RequestedStem(combined.Text,".dwg"),SetName=dst.Checked&&mode.SelectedIndex!=2?Names.RequestedStem(setName.Text,".dst"):"Sheet Set"'
$c=One $c 'if((job.Combine||job.Model)&&names.Contains(job.CombinedName,StringComparer.OrdinalIgnoreCase))job.CombinedName+="_TOTAL";' @'
var planned=(job.Combine||job.Model?new[]{job.CombinedName+".dwg"}:names.Select(n=>n+".dwg").ToArray()).ToList();
   if(job.CreateDst)planned.Add(job.SetName+".dst");
   var conflicts=planned.Where(n=>File.Exists(Path.Combine(root,n))).ToList();
   if(conflicts.Count>0){
    string details=string.Join("\n",conflicts.Take(25));if(conflicts.Count>25)details+="\n... +"+(conflicts.Count-25)+" file";
    if(WF.MessageBox.Show("Các file sau đã tồn tại:\n"+details+"\n\nGhi đè đúng các file này sau khi xuất thành công?\nChọn Không để hủy; các file khác được giữ nguyên.","Xác nhận ghi đè",WF.MessageBoxButtons.YesNo,WF.MessageBoxIcon.Warning,WF.MessageBoxDefaultButton.Button2)!=WF.DialogResult.Yes){Directory.Delete(work,true);return;}
    foreach(string n in conflicts){using(var lockTest=new FileStream(Path.Combine(root,n),FileMode.Open,FileAccess.ReadWrite,FileShare.None)){}}
    job.ApprovedOverwrite=conflicts;
   }
'@
# Intermediate Revit export files live in separate folders; keep exact final names for Mode A.
$c=One $c 'bool ok=doc.Export(target,names[i]+".dwg",new List<ElementId>{sh.Id},opt);' 'bool ok=doc.Export(target,"CSE_SOURCE_"+(i+1).ToString("D4"),new List<ElementId>{sh.Id},opt);'
$c=One $c 'Path.GetFileNameWithoutExtension(p).Equals(names[i],StringComparison.OrdinalIgnoreCase)' 'Path.GetFileNameWithoutExtension(p).Equals("CSE_SOURCE_"+(i+1).ToString("D4"),StringComparison.OrdinalIgnoreCase)'
Write-Source 'Revit\Command.cs' $c
$p=Read-Source 'Cad\Processor.cs'
$start=$p.IndexOf('  static async System.Threading.Tasks.Task Run(')
$end=$p.IndexOf('  static DwgVersion Version(',$start)
if($start -lt 0 -or $end -lt 0){throw 'Run method boundaries missing'}
$run=@'
  static async System.Threading.Tasks.Task Run(string path,Editor ed,bool recovery){
   var j=Job.Read(path);string work=Path.GetDirectoryName(Path.GetFullPath(path));
   void Say(string t){
    File.AppendAllText(Path.Combine(work,"cad_process.log"),DateTime.Now.ToString("HH:mm:ss")+" "+t+Environment.NewLine);
    try{Acad.DocumentManager.MdiActiveDocument?.Editor.WriteMessage("\n"+t);}catch(System.Exception){}
   }
   string rawRoot=Path.GetFullPath(Path.Combine(work,"DWG"))+Path.DirectorySeparatorChar;
   if(j.Sheets==null||j.Sheets.Count==0)throw new System.Exception("Job không có Sheet.");
   if(j.Sheets.GroupBy(x=>x.Layout,StringComparer.OrdinalIgnoreCase).Any(g=>g.Count()>1))throw new System.Exception("Layout trùng trong job.");
   var ok=j.Sheets.Where(s=>s.Status=="EXPORTED"&&File.Exists(s.Source)).ToList();
   if(ok.Count!=j.Sheets.Count)throw new System.Exception("Thiếu DWG nguồn; không ghi đè hồ sơ hiện hữu.");
   if(ok.Any(s=>!Path.GetFullPath(s.Source).StartsWith(rawRoot,StringComparison.OrdinalIgnoreCase)))throw new System.Exception("Job có đường dẫn ngoài thư mục DWG.");
   string output=string.IsNullOrWhiteSpace(j.Output)?Directory.CreateDirectory(Path.Combine(work,"RECOVER_"+Guid.NewGuid().ToString("N").Substring(0,6))).FullName:Path.GetFullPath(j.Output);
   if(!Directory.Exists(output))throw new System.Exception("Output directory missing.");
   if(!j.DirectOutput&&!string.IsNullOrWhiteSpace(j.Output)&&!string.Equals(Path.GetDirectoryName(work),output,StringComparison.OrdinalIgnoreCase))throw new System.Exception("Invalid output root.");
   string runId="CSE_"+Guid.NewGuid().ToString("N");
   string stage=Directory.CreateDirectory(Path.Combine(work,"stage_"+runId)).FullName;
   var success=new List<SheetItem>();DwgVersion v=Version(j.Version);var used=new HashSet<string>(StringComparer.OrdinalIgnoreCase);var pack=new LinkPack(stage,v,Say);
   var planned=(j.Combine||j.Model?new[]{Names.RequestedStem(j.CombinedName,".dwg")+".dwg"}:j.Sheets.Select(s=>Names.RequestedStem(s.FileName,".dwg")+".dwg").ToArray()).ToList();
   if(j.CreateDst&&!j.Model)planned.Add(Names.RequestedStem(j.SetName,".dst")+".dst");
   if(planned.Distinct(StringComparer.OrdinalIgnoreCase).Count()!=planned.Count)throw new System.Exception("Duplicate output filenames.");
   var approvals=new HashSet<string>(j.ApprovedOverwrite??new List<string>(),StringComparer.OrdinalIgnoreCase);
   void CheckDestination(string name){
    if(!planned.Contains(name,StringComparer.OrdinalIgnoreCase))throw new System.Exception("Unplanned output: "+name);
    string dest=Path.Combine(output,name);
    if(File.Exists(dest)){
     if(!approvals.Contains(name))throw new System.Exception("File tồn tại nhưng chưa được xác nhận ghi đè: "+name);
     using(var probe=new FileStream(dest,FileMode.Open,FileAccess.ReadWrite,FileShare.None)){}
    }
   }
   foreach(string n in planned)CheckDestination(n);
   bool combined=false,dstOk=false,complete=false;
   var published=new List<KeyValuePair<string,string>>();
   string installedLinks=null;
   try{
    foreach(var s in ok){
     Say("Kiểm tra "+s.Number);
     string stem=j.Combine||j.Model?"_CSE_SHEET_"+Guid.NewGuid().ToString("N"):Names.RequestedStem(s.FileName,".dwg");
     if(!used.Add(stem))throw new System.Exception("Duplicate staged name: "+stem);
     string final=Path.Combine(stage,stem+".dwg");
     try{
      pack.Publish(s.Source,final,Path.Combine(runId,Names.FileStem(s.Number)+"_"+success.Count.ToString("D4")));
      s.FinalDwg=Normalize(final,s.Layout,v);LinkPack.Check(final);s.Status="LAYOUT_OK";success.Add(s);
     }catch(System.Exception ex){s.Status="LAYOUT_ERROR";s.Detail=ex.ToString();throw;}
    }
    if(j.Combine||j.Model){
     string merged=Path.Combine(stage,Names.RequestedStem(j.CombinedName,".dwg")+".dwg");
     if(j.Model){
#if CSE_CORE
      throw new System.Exception("Model requires desktop EXPORTLAYOUT");
#else
      await MergeModel(success,merged,v,j.Columns,j.Gap,work,Say);
#endif
     }else Merge(success,merged,v);
     LinkPack.Check(merged);
     foreach(var s in success){s.FinalDwg=merged;s.Status=j.Model?"MODEL_BETA":"MERGED_BETA";}
     combined=true;
    }
    // Assets use a unique per-run namespace. Existing asset folders are never overwritten.
    string stagedLinks=Path.Combine(stage,"Links",runId);
    if(Directory.Exists(stagedLinks)){
     installedLinks=Path.Combine(output,"Links",runId);
     if(Directory.Exists(installedLinks))throw new System.Exception("Unexpected Links namespace collision.");
     Directory.CreateDirectory(installedLinks);CopyTree(stagedLinks,installedLinks);
    }
    foreach(var group in success.GroupBy(x=>x.FinalDwg,StringComparer.OrdinalIgnoreCase)){
     string src=group.Key,name=Path.GetFileName(src),dest=Path.Combine(output,name);
     CheckDestination(name);
     string pending=Path.Combine(output,".cse_"+Guid.NewGuid().ToString("N")+".tmp");
     try{
      File.Copy(src,pending,false);
      if(File.Exists(dest)){
       if(!approvals.Contains(name))throw new System.Exception("Unapproved overwrite: "+name);
       string bak=Path.Combine(output,".cse_"+Guid.NewGuid().ToString("N")+".backup");
       File.Replace(pending,dest,bak);
       published.Add(new KeyValuePair<string,string>(dest,bak));
      }else{
       File.Move(pending,dest);published.Add(new KeyValuePair<string,string>(dest,null));
      }
     }finally{if(File.Exists(pending))File.Delete(pending);}
     LinkPack.Check(dest);
     foreach(var s in group)s.FinalDwg=dest;
    }
    if(j.CreateDst&&!j.Model){
     string name=Names.RequestedStem(j.SetName,".dst")+".dst",dest=Path.Combine(output,name);
     CheckDestination(name);
     string bak=null;
     if(File.Exists(dest)){
      if(!approvals.Contains(name))throw new System.Exception("Unapproved overwrite: "+name);
      bak=Path.Combine(output,".cse_"+Guid.NewGuid().ToString("N")+".backup");File.Move(dest,bak);
     }
     published.Add(new KeyValuePair<string,string>(dest,bak));
     MakeDst(dest,j.SetName,success);
     foreach(var group in success.GroupBy(s=>s.FinalDwg,StringComparer.OrdinalIgnoreCase)){
      StampAssociation(group.First(),dest,v);LinkPack.Check(group.Key);
     }
     dstOk=true;
    }
    complete=true;
   }catch(System.Exception ex){
    Say("EXPORT FAILED: "+ex);
    bool rollbackOk=true;
    foreach(var pair in published.AsEnumerable().Reverse()){
     try{
      if(pair.Value==null){if(File.Exists(pair.Key))File.Delete(pair.Key);}
      else if(File.Exists(pair.Value)){if(File.Exists(pair.Key))File.Replace(pair.Value,pair.Key,null);else File.Move(pair.Value,pair.Key);}
      else throw new System.Exception("Rollback backup missing: "+pair.Key);
     }catch(System.Exception rollback){rollbackOk=false;Say("ROLLBACK ERROR: "+rollback+" | backup="+pair.Value);}
    }
    if(rollbackOk&&installedLinks!=null&&Directory.Exists(installedLinks))try{Directory.Delete(installedLinks,true);}catch(System.Exception cleanup){Say("Links cleanup warning: "+cleanup.Message);}
    File.WriteAllText(Path.Combine(work,"merge_error.txt"),ex.ToString());
    string first=ex.Message;string state="FAILED | Layout "+success.Count+"/"+j.Sheets.Count+" | "+first+" | Recovery: "+stage;
    File.WriteAllText(Path.Combine(work,"state.txt"),state);
    Names.Csv(Path.Combine(work,"sheet_index.csv"),j.Sheets);return;
   }
   if(complete){
    foreach(var pair in published)if(pair.Value!=null)try{File.Delete(pair.Value);}catch(System.Exception ex){Say("Backup cleanup warning: "+pair.Value+" | "+ex.Message);}
    Names.Csv(Path.Combine(work,"sheet_index.csv"),j.Sheets);j.Write(Path.Combine(work,"processed_job.xml"));
    string result="SUCCESS | Layout "+success.Count+"/"+j.Sheets.Count+" | Merge="+(combined?"BETA_OK":"NOT_REQUESTED")+" | DST="+(dstOk?"OK":"NOT_REQUESTED")+" | Output: "+output;
    Say(result);File.WriteAllText(Path.Combine(work,"state.txt"),result);
   }
  }
'@
$p=$p.Substring(0,$start)+$run+[Environment]::NewLine+$p.Substring($end)
Write-Source 'Cad\Processor.cs' $p
$m=Read-Source 'Cad\ModelMerge.cs'
$start=$m.IndexOf('  static async Task MergeModel(')
$end=$m.IndexOf('   using(var target=new Database(true,true))',$start)
if($start -lt 0 -or $end -lt 0){throw 'Model method boundaries missing'}
$prefix=@'
  static Document flattenDocument;
  static bool flattenMarker;
  [Autodesk.AutoCAD.Runtime.CommandMethod("CSEFLATDONE")]
  public void FlattenDone(){if(Acad.DocumentManager.MdiActiveDocument==flattenDocument)flattenMarker=true;}
  static string LispString(string s){return "\""+s.Replace("\\","/").Replace("\"","\\\"")+"\"";}
  static Task NativeFlatten(Document d,string layout,string flat,Action<string> say){
   var docs=Acad.DocumentManager;
   if(flattenDocument!=null)throw new System.Exception("Another flatten command is pending");
   var done=new TaskCompletionSource<bool>();
   var watch=System.Diagnostics.Stopwatch.StartNew();
   object filedia=Acad.GetSystemVariable("FILEDIA"),cmddia=Acad.GetSystemVariable("CMDDIA");
   flattenDocument=d;flattenMarker=false;
   EventHandler idle=null;
   idle=(sender,e)=>{
    if(!flattenMarker&&watch.Elapsed<TimeSpan.FromMinutes(8))return;
    Acad.Idle-=idle;flattenDocument=null;
    try{
     if(docs.MdiActiveDocument==d){Acad.SetSystemVariable("FILEDIA",filedia);Acad.SetSystemVariable("CMDDIA",cmddia);}
    }catch(System.Exception restore){say("Restore variables warning: "+restore.Message);}
    if(!flattenMarker){done.TrySetException(new System.Exception("Native EXPORTLAYOUT completion timeout"));return;}
    if(!File.Exists(flat)||new FileInfo(flat).Length==0){done.TrySetException(new System.Exception("Native EXPORTLAYOUT did not create "+flat));return;}
    done.TrySetResult(true);
   };
   Acad.Idle+=idle;
   try{
    // The native input queue runs after the session command returns. Do not call
    // Editor.Command/CommandAsync or SwitchToPaperSpace across document contexts.
    string lisp="(progn (setvar \"FILEDIA\" 0) (setvar \"CMDDIA\" 0) (setvar \"CTAB\" "+LispString(layout)+") (if (> (getvar \"CVPORT\") 1) (command \"_.PSPACE\")) (command \"_.EXPORTLAYOUT\" "+LispString(flat)+") (princ))";
    say("Queue native EXPORTLAYOUT: "+layout+" -> "+flat);
    d.SendStringToExecute(lisp+"\nCSEFLATDONE\n",true,false,false);
   }catch(System.Exception ex){Acad.Idle-=idle;flattenDocument=null;done.TrySetException(ex);}
   return done.Task;
  }
  static async Task MergeModel(List<SheetItem> sheets,string path,DwgVersion version,int columns,double gap,string work,Action<string> say){
   if(columns<1||gap<0)throw new System.Exception("Invalid model grid");
   var docs=Acad.DocumentManager;var previous=docs.MdiActiveDocument;var flats=new List<string>();
   string root=Path.GetDirectoryName(path);string stage="START";bool complete=false;
   try{
    for(int i=0;i<sheets.Count;i++){
     var s=sheets[i];stage="NATIVE EXPORTLAYOUT "+s.Number+" ["+s.Layout+"]";say(stage);
     string flat=Path.Combine(root,"_CSE_FLAT_"+Guid.NewGuid().ToString("N")+".dwg");flats.Add(flat);
     var d=docs.Open(s.FinalDwg,false);
     try{
      docs.MdiActiveDocument=d;
      await NativeFlatten(d,s.Layout,flat,say);
      using(var db=Open(flat))using(var tr=db.TransactionManager.StartTransaction()){
       var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);
       var ms=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
       if(!ms.Cast<ObjectId>().Any())throw new System.Exception("Flattened Model is empty: "+s.Number);
      }
      say("FLAT OK "+s.Number+" | "+new FileInfo(flat).Length+" bytes");
     }finally{
      try{d.CloseAndDiscard();}finally{if(previous!=null)docs.MdiActiveDocument=previous;}
     }
    }
    stage="CLONE Model";
'@
$m=$m.Substring(0,$start)+$prefix+[Environment]::NewLine+$m.Substring($end)
$m=One $m 'for(int i=0;i<flats.Count;i++){using(var src=Open(flats[i]))' 'for(int i=0;i<flats.Count;i++){stage="CLONE "+sheets[i].Number;say(stage);using(var src=Open(flats[i]))'
$m=One $m 'InDb(target,()=>LayoutManager.Current.CurrentLayout="Model");target.SaveAs(path,version);' 'stage="SAVE merged Model";say(stage);target.SaveAs(path,version);'
$m=One $m '}catch{if(File.Exists(path))File.Delete(path);throw;}finally{foreach(var f in flats)try{if(File.Exists(f))File.Delete(f);}catch{}}}' @'
    complete=true;
   }catch(System.Exception ex){say("MODEL FAILED AT "+stage+" | "+ex);throw new System.Exception(stage+": "+ex.Message,ex);}
   finally{if(complete)foreach(var f in flats)try{if(File.Exists(f))File.Delete(f);}catch(System.Exception ex){say("Flat cleanup warning: "+ex.Message);}}
  }
'@
Write-Source 'Cad\ModelMerge.cs' $m
Write-Host 'V2.4.3: exact output names, explicit collision approvals, staged publish and rollback; queued native EXPORTLAYOUT.'
