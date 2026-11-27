param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}

# Mode B only: use a real initialized Layout created by LayoutManager.
# Never deep-clone the source overall paper-space viewport into the new layout.
$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'static LayerAndLayout CloneSheet(Database src,Database target,string name,int index,ref double nextModelX,Action<string> say){using(var st=' @'
static LayerAndLayout CloneSheet(Database src,Database target,string name,int index,ref double nextModelX,Action<string> say){
   ObjectId layoutId=ObjectId.Null;
   InDb(target,()=>{layoutId=LayoutManager.Current.CreateLayout(name);});
   if(layoutId.IsNull)throw new System.Exception("LayoutManager did not create "+name);
   using(var st=
'@
$p=One $p 'int k=1;string bn;do{bn="*Paper_Space"+k++;}while(dbt.Has(bn));var paper=new BlockTableRecord{Name=bn};ObjectId pid=dbt.Add(paper);dt.AddNewlyCreatedDBObject(paper,true);' @'
   var layout=(Layout)dt.GetObject(layoutId,OpenMode.ForWrite);
   layout.CopyFrom(sl);
   layout.TabOrder=index+2;
   ObjectId overallId=ObjectId.Null;
   InDb(target,()=>{overallId=layout.Initialize();});
   ObjectId pid=layout.BlockTableRecordId;
   var targetPaper=(BlockTableRecord)dt.GetObject(pid,OpenMode.ForRead);
   if(overallId.IsNull){
    var primary=layout.GetViewports();
    if(primary.Count>0)overallId=primary[0];
   }
   if(overallId.IsNull||overallId.IsErased||!targetPaper.Cast<ObjectId>().Contains(overallId))
    throw new System.Exception("Missing initialized overall Paper Space viewport: "+name);
   // A profile may create an additional default floating viewport.
   // Remove only these default floating viewport entities, never the overall.
   foreach(ObjectId id in targetPaper.Cast<ObjectId>().ToList()){
    if(id==overallId)continue;
    var obj=dt.GetObject(id,OpenMode.ForRead);
    if(!(obj is Viewport))throw new System.Exception("New layout contains unexpected entity: "+name);
    obj.UpgradeOpen();obj.Erase();
   }
   say("LAYOUT INITIALIZED "+name+" | overall="+overallId.Handle+" | paper="+pid.Handle);
'@
$p=One $p 'var paperIds=new ObjectIdCollection();foreach(ObjectId id in sp)paperIds.Add(id);' @'
   var paperIds=new ObjectIdCollection();
   var floatingSet=new HashSet<ObjectId>(floating);
   foreach(ObjectId id in sp){
    if(st.GetObject(id,OpenMode.ForRead) is Viewport&&!floatingSet.Contains(id))continue;
    paperIds.Add(id);
   }
'@
$p=One $p 'var destLayouts=(DBDictionary)dt.GetObject(target.LayoutDictionaryId,OpenMode.ForWrite);if(destLayouts.Contains(name))throw new System.Exception("Tên Layout trùng: "+name);var layout=new Layout{LayoutName=name};layout.AddToLayoutDictionary(target,pid);dt.AddNewlyCreatedDBObject(layout,true);layout.CopyFrom(sl);layout.TabOrder=index+2;' ''
$p=One $p 'Viewports=viewIds,ViewportStates=snapshots,Entities=paperIds.Count' 'Viewports=viewIds,ViewportStates=snapshots,Entities=paperIds.Count+1'
$p=One $p 'var cloned=(Viewport)dt.GetObject(clonedId,OpenMode.ForWrite);' @'
   if(clonedId.IsErased)throw new System.Exception("Cloned floating viewport erased: "+name+" | "+oldVp.Handle);
   var cloned=(Viewport)dt.GetObject(clonedId,OpenMode.ForWrite);
   if(cloned.OwnerId!=pid||clonedId==overallId)throw new System.Exception("Floating viewport owner mismatch: "+name+" | "+cloned.Handle);
'@
# Make each owning layout current before restoring its viewports. Do this outside
# the restore transaction. Avoid touching the overall viewport in this pass.
$p=One $p 'using(var tr=target.TransactionManager.StartTransaction()){for(int i=0;i<parts.Count;i++){var l=(Layout)tr.GetObject(parts[i].Layout,OpenMode.ForWrite);' @'
   for(int i=0;i<parts.Count;i++){
    string sheetLayout=sheets[i].Layout;
    InDb(target,()=>LayoutManager.Current.CurrentLayout=sheetLayout);
    using(var tr=target.TransactionManager.StartTransaction()){
     var l=(Layout)tr.GetObject(parts[i].Layout,OpenMode.ForWrite);
'@
$p=One $p 'if(cnt!=parts[i].Viewports.Count||entities!=parts[i].Entities)throw new System.Exception("Sai số lượng entity/viewport: "+l.LayoutName);}tr.Commit();}expectedViewports.AddRange' @'
     if(cnt!=parts[i].Viewports.Count||entities!=parts[i].Entities)throw new System.Exception("Sai số lượng entity/viewport: "+l.LayoutName+" | "+entities+"/"+parts[i].Entities+" | floating="+cnt+"/"+parts[i].Viewports.Count);
     tr.Commit();
    }
   }
   expectedViewports.AddRange
'@
# Keep existing validation, add check that every mapped viewport is actually
# floating and the destination owns exactly one separate overall viewport.
Write-Source 'Cad\Processor.cs' $p

$m=Read-Source 'Cad\ModelMerge.cs'
$m=One $m 'dest.On=Enabled;' @'
    if(dest.IsErased||dest.ObjectId.IsErased)throw new System.Exception("Cannot restore erased floating viewport: "+LayoutName+" | "+HandleText);
    // Cloning retains the persisted On flag. Do not reinitialize an already
    // enabled viewport (which caused eWasErased in 2.6.4).
    if(dest.On!=Enabled)dest.On=Enabled;
'@
$m=One $m 'if(Clipped){dest.NonRectClipEntityId=ClipId;dest.NonRectClipOn=true;}else dest.NonRectClipOn=false;' @'
    if(Clipped){
     if(ClipId.IsNull||ClipId.IsErased)throw new System.Exception("Invalid viewport clipping entity: "+LayoutName+" | "+HandleText);
     if(dest.NonRectClipEntityId!=ClipId)dest.NonRectClipEntityId=ClipId;
     if(!dest.NonRectClipOn)dest.NonRectClipOn=true;
    }else if(dest.NonRectClipOn)dest.NonRectClipOn=false;
'@
$m=One $m 'foreach(var snapshot in group){' @'
     var ids=layout.GetViewports();
     if(ids.Count==0||ids[0].IsNull||ids[0].IsErased)throw new System.Exception("Overall viewport missing on reopen: "+group.Key);
     string overallHandle=ids[0].Handle.ToString();
     if(!found.ContainsKey(overallHandle)||group.Any(x=>string.Equals(x.HandleText,overallHandle,StringComparison.OrdinalIgnoreCase)))
      throw new System.Exception("Overall viewport conflicts with floating viewport: "+group.Key);
     if(found.Count!=group.Count()+1)throw new System.Exception("Unexpected floating viewport count on reopen: "+group.Key);
     foreach(var snapshot in group){
'@
Write-Source 'Cad\ModelMerge.cs' $m

$c=Read-Source 'Revit\Command.cs'
$c=One $c 'C - Một DWG / Model (cần CAD desktop)' 'C - Một DWG / Model (chạy nền)'
$c=One $c 'if(mode.SelectedIndex==2&&WF.MessageBox.Show("Mode C chạy nền thử nghiệm: hỗ trợ viewport 2D trực giao hình chữ nhật, không mở AutoCAD Desktop. Kiểm tra bản vẽ đầu ra trước khi phát hành. Tiếp tục?","Model",WF.MessageBoxButtons.YesNo)!=WF.DialogResult.Yes)return;' ''
Write-Source 'Revit\Command.cs' $c
Write-Host 'V2.6.5: initialized LayoutManager lifecycle, unique overall viewport, no redundant On mutation, per-owner restore, remove Mode C warning and desktop label.'
