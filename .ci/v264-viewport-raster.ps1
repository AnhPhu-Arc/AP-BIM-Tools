param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}

$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'public List<ObjectId> Viewports; public int Entities;' 'public List<ObjectId> Viewports; public List<ViewportSnapshot> ViewportStates; public int Entities;'
$p=One $p 'var viewIds=new List<ObjectId>();var pairs=' 'var viewIds=new List<ObjectId>();var snapshots=new List<ViewportSnapshot>();var pairs='
$a=$p.IndexOf('   var cloned=(Viewport)dt.GetObject(clonedId,OpenMode.ForWrite);')
$b=$p.IndexOf('   var frozen=new ObjectIdCollection();',$a)
if($a -lt 0 -or $b -lt 0){throw 'Viewport clone source boundary missing'}
$replacement=@'
   var cloned=(Viewport)dt.GetObject(clonedId,OpenMode.ForWrite);
   var snapshot=new ViewportSnapshot(oldVp,shift,clonedId,name);
   if(snapshot.Clipped){
    if(!pairs.TryGetValue(oldVp.NonRectClipEntityId,out var clipId)||clipId.IsNull)
     throw new System.Exception("Cannot map viewport clipping boundary: "+name+" | "+oldVp.Handle);
    snapshot.ClipId=clipId;
   }
   snapshots.Add(snapshot);
   say("VP EXPECTED "+name+" | "+oldVp.Handle+" -> "+cloned.Handle+" | paper="+snapshot.Center+" | width="+snapshot.Width+" | height="+snapshot.Height+" | viewHeight="+snapshot.ViewHeight+" | target="+snapshot.Target);
'@
$p=$p.Substring(0,$a)+$replacement+[Environment]::NewLine+$p.Substring($b)
$p=One $p 'if(frozen.Count>0)cloned.FreezeLayersInViewport(frozen.GetEnumerator());}InDb(target,()=>RepairRasterMap' 'foreach(ObjectId layerId in frozen)snapshot.Frozen.Add(layerId);}InDb(target,()=>RepairRasterMap'
$p=One $p 'Viewports=viewIds,Entities=paperIds.Count' 'Viewports=viewIds,ViewportStates=snapshots,Entities=paperIds.Count'
# Only restore after all layouts and their overall viewport records have been created.
# Do not switch CTAB after the final restore pass.
$p=One $p 'if(freeze.Count>0)vp.FreezeLayersInViewport(freeze.GetEnumerator());vp.Locked=true;' @'
var snapshot=parts[i].ViewportStates.Single(x=>x.Id==id);
    InDb(target,()=>{
     snapshot.Apply(vp);
     var allFrozen=new ObjectIdCollection();
     foreach(ObjectId f in snapshot.Frozen)if(!allFrozen.Contains(f))allFrozen.Add(f);
     foreach(ObjectId f in freeze)if(!allFrozen.Contains(f))allFrozen.Add(f);
     if(allFrozen.Count>0)vp.FreezeLayersInViewport(allFrozen.GetEnumerator());
     vp.Locked=snapshot.Locked;
     snapshot.Assert(vp);
    });
    say("VP RESTORED "+l.LayoutName+" | "+vp.Handle+" | "+ViewportFlags(vp));
'@
# Retain expected snapshots across SaveAs and reopen; identify by persisted handle and layout.
$p=One $p 'string temp=path+".tmp.dwg";try{using(var target=new Database(true,true))' 'string temp=path+".tmp.dwg";var expectedViewports=new List<ViewportSnapshot>();try{using(var target=new Database(true,true))'
$p=One $p 'tr.Commit();}target.SaveAs(temp,v);}' 'tr.Commit();}expectedViewports.AddRange(parts.SelectMany(x=>x.ViewportStates));target.SaveAs(temp,v);}'
$p=One $p 'VerifyModelIsolation(verify);var found=Layouts(verify,true);' 'VerifyModelIsolation(verify);VerifyViewportSnapshots(verify,expectedViewports,say);var found=Layouts(verify,true);'
# In Mode A, after all layout manipulation, rebind and reload images in the staged DWG.
$p=One $p 'Say("CHECK LINKS "+s.Number);LinkPack.Check(final);' 'Say("CHECK LINKS "+s.Number);if(!j.Combine&&!j.Model)LinkPack.RefreshRaster(final,v,Say);LinkPack.Check(final);'
Write-Source 'Cad\Processor.cs' $p

$m=Read-Source 'Cad\ModelMerge.cs'
$anchor='  static string ViewportFlags(Viewport vp){'
$viewport=@'
  sealed class ViewportSnapshot {
   public readonly ObjectId Id; public readonly string LayoutName,HandleText;
   public readonly Point3d Center,Target;
   public readonly Point2d ViewCenter;
   public readonly Vector3d Direction;
   public readonly double Width,Height,ViewHeight,Twist;
   public readonly bool Enabled,Locked,Clipped;
   public ObjectId ClipId=ObjectId.Null;
   public readonly List<ObjectId> Frozen=new List<ObjectId>();
   public ViewportSnapshot(Viewport src,Vector3d shift,ObjectId id,string name){
    Id=id;LayoutName=name;HandleText=id.Handle.ToString();
    Center=src.CenterPoint;Width=src.Width;Height=src.Height;
    ViewCenter=src.ViewCenter;Target=src.ViewTarget+shift;Direction=src.ViewDirection;
    ViewHeight=src.ViewHeight;Twist=src.TwistAngle;
    Enabled=src.On;Locked=src.Locked;Clipped=src.NonRectClipOn;
    if(Width<=0||Height<=0||ViewHeight<=0)throw new System.Exception("Invalid source viewport dimensions: "+name+" | "+src.Handle);
   }
   public void Apply(Viewport dest){
    dest.Locked=false;
    // On and clipping can initialize default camera/size. Set them before the
    // final paper-space geometry and camera, never after.
    dest.On=Enabled;
    if(Clipped){dest.NonRectClipEntityId=ClipId;dest.NonRectClipOn=true;}else dest.NonRectClipOn=false;
    dest.CenterPoint=Center;dest.Width=Width;dest.Height=Height;
    dest.ViewDirection=Direction;dest.ViewTarget=Target;dest.TwistAngle=Twist;
    dest.ViewCenter=ViewCenter;dest.ViewHeight=ViewHeight;
    dest.Locked=Locked;
   }
   static bool Near(double a,double b){return Math.Abs(a-b)<=Math.Max(1e-6,Math.Max(Math.Abs(a),Math.Abs(b))*1e-9);}
   public void Assert(Viewport dest){
    bool size=Near(dest.CenterPoint.X,Center.X)&&Near(dest.CenterPoint.Y,Center.Y)&&Near(dest.CenterPoint.Z,Center.Z)&&Near(dest.Width,Width)&&Near(dest.Height,Height);
    bool camera=Near(dest.ViewTarget.X,Target.X)&&Near(dest.ViewTarget.Y,Target.Y)&&Near(dest.ViewTarget.Z,Target.Z)&&Near(dest.ViewCenter.X,ViewCenter.X)&&Near(dest.ViewCenter.Y,ViewCenter.Y)&&Near(dest.ViewHeight,ViewHeight)&&Near(dest.TwistAngle,Twist)&&dest.ViewDirection.IsEqualTo(Direction);
    bool scale=Near(dest.CustomScale,Height/ViewHeight);
    if(!size||!camera||!scale||dest.On!=Enabled||dest.NonRectClipOn!=Clipped||dest.Locked!=Locked)
     throw new System.Exception("Viewport geometry mismatch: "+LayoutName+" | "+HandleText+" | paper="+size+" | camera="+camera+" | scale="+scale+" | expected center="+Center+" size="+Width+"x"+Height+" | actual "+ViewportFlags(dest));
    if(Clipped&&dest.NonRectClipEntityId.IsNull)throw new System.Exception("Viewport lost clipping entity: "+LayoutName+" | "+HandleText);
   }
  }
  static void VerifyViewportSnapshots(Database db,List<ViewportSnapshot> expected,Action<string> say){
   using(var tr=db.TransactionManager.StartTransaction()){
    var ld=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
    foreach(var group in expected.GroupBy(x=>x.LayoutName,StringComparer.OrdinalIgnoreCase)){
     if(!ld.Contains(group.Key))throw new System.Exception("Layout missing on reopen: "+group.Key);
     var layout=(Layout)tr.GetObject(ld.GetAt(group.Key),OpenMode.ForRead);
     var paper=(BlockTableRecord)tr.GetObject(layout.BlockTableRecordId,OpenMode.ForRead);
     var found=new Dictionary<string,Viewport>(StringComparer.OrdinalIgnoreCase);
     foreach(ObjectId id in paper)if(tr.GetObject(id,OpenMode.ForRead) is Viewport vp)found[vp.Handle.ToString()]=vp;
     foreach(var snapshot in group){
      if(!found.TryGetValue(snapshot.HandleText,out var vp))throw new System.Exception("Viewport missing on reopen: "+group.Key+" | "+snapshot.HandleText);
      snapshot.Assert(vp);
      say("VP REOPEN OK "+group.Key+" | "+snapshot.HandleText+" | paper="+vp.CenterPoint+" | size="+vp.Width+"x"+vp.Height+" | scale="+vp.CustomScale);
     }
    }
   }
  }
'@
$m=One $m $anchor ($viewport+[Environment]::NewLine+$anchor)
# Mode A raster fixture: test the same pack-normalize-refresh route and a
# relocated output directory, without depending on Mode B/C geometry probes.
$m=One $m 'if(mode=="A"){File.AppendAllText(log,"PASS: Mode A DWG read, write and pack."+Environment.NewLine);File.WriteAllText(result,"PASS");return;}' 'if(mode=="A")File.AppendAllText(log,"PREFLIGHT: Mode A raster portability fixture."+Environment.NewLine);'
$m=One $m 'for(int i=0;i<3;i++){' 'for(int i=0;i<(mode=="A"?1:3);i++){'
$m=One $m 'Action<string> report=t=>File.AppendAllText(log,t+Environment.NewLine);' @'
    Action<string> report=t=>File.AppendAllText(log,t+Environment.NewLine);
    if(mode=="A"||mode=="ALL"){
     string stageA=Directory.CreateDirectory(Path.Combine(folder,"SeparateA")).FullName;
     string aDwg=Path.Combine(stageA,"A.dwg");
     new LinkPack(stageA,DwgVersion.AC1032,report).Publish(layoutTests[0].FinalDwg,aDwg,"A");
     Normalize(aDwg,layoutTests[0].Layout,DwgVersion.AC1032);
     LinkPack.RefreshRaster(aDwg,DwgVersion.AC1032,report);
     LinkPack.Check(aDwg);
     string moved=Directory.CreateDirectory(Path.Combine(folder,"MovedA")).FullName;
     CopyTree(stageA,moved);Directory.Delete(stageA,true);
     string movedDwg=Path.Combine(moved,"A.dwg");
     LinkPack.Check(movedDwg);
     LinkPack.AssertVisibleRaster(movedDwg,1);
     report("PASS: Mode A logo survives packing, normalization, refresh and relocation.");
     if(mode=="A"){File.WriteAllText(result,"PASS");return;}
    }
'@
Write-Source 'Cad\ModelMerge.cs' $m

$l=Read-Source 'Cad\LinkPack.cs'
# Refresh the actual raster definitions in the final staged file, using the
# already-resolved packed absolute path for the runtime loader while keeping a
# relative SourceFileName in the saved DWG. Preserve original visibility.
$anchor='   public void Publish(string source,string final,string stem)'
$raster=@'
   static string PortableRasterPath(string owner,string absolute){
    string rel=Relative(Path.GetDirectoryName(owner),absolute);
    return rel.StartsWith(".."+Path.DirectorySeparatorChar,StringComparison.Ordinal)||rel.StartsWith("."+Path.DirectorySeparatorChar,StringComparison.Ordinal)?rel:"."+Path.DirectorySeparatorChar+rel;
   }
   static void SetRasterDefinition(RasterImageDef def,string owner,string absolute){
    if(def.IsLoaded)def.Unload(false);
    def.SourceFileName=PortableRasterPath(owner,absolute);
    def.ActiveFileName=absolute;
    def.Load();
    if(!def.IsLoaded)throw new System.Exception("Raster load failed: "+absolute);
   }
   public static void RefreshRaster(string path,DwgVersion version,Action<string> say){
    string root=Path.GetDirectoryName(Path.GetFullPath(path));
    string temp=Path.Combine(root,"I"+Guid.NewGuid().ToString("N").Substring(0,8)+".dwg");
    bool changed=false;
    try{
     using(var db=Open(path)){
      InDb(db,()=>{using(var tr=db.TransactionManager.StartTransaction()){
       var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);
       var entities=new List<Tuple<ObjectId,bool>>();
       var definitions=new HashSet<ObjectId>();
       foreach(ObjectId bid in bt){
        var b=(BlockTableRecord)tr.GetObject(bid,OpenMode.ForRead);
        if(b.IsDependent||b.IsFromExternalReference||b.IsFromOverlayReference)continue;
        foreach(ObjectId id in b)if(tr.GetObject(id,OpenMode.ForRead) is RasterImage image){
         if(image.ImageDefId.IsNull)throw new System.Exception("Raster image has no definition: "+image.Handle);
         entities.Add(Tuple.Create(id,image.ShowImage));definitions.Add(image.ImageDefId);
        }
       }
       if(entities.Count==0){tr.Commit();return;}
       RasterImage.EnableReactors(true);
       foreach(var id in definitions){
        var def=(RasterImageDef)tr.GetObject(id,OpenMode.ForWrite);
        string absolute=CheckRef(path,def.SourceFileName,root);
        SetRasterDefinition(def,path,absolute);
        say("RASTER RELOAD "+def.Handle+" | saved="+def.SourceFileName+" | active="+def.ActiveFileName);
       }
       foreach(var item in entities){
        var image=(RasterImage)tr.GetObject(item.Item1,OpenMode.ForWrite);
        var def=(RasterImageDef)tr.GetObject(image.ImageDefId,OpenMode.ForWrite);
        if(image.ReactorId.IsNull)image.AssociateRasterDef(def);
        image.ShowImage=item.Item2;
        if(image.ReactorId.IsNull)throw new System.Exception("Raster reactor is missing after repair: "+image.Handle);
       }
       changed=true;tr.Commit();
      }});
      if(changed)db.SaveAs(temp,version);
     }
     if(changed)File.Replace(temp,path,null);
    }finally{if(File.Exists(temp))File.Delete(temp);}
   }
   public static void AssertVisibleRaster(string path,int count){
    using(var db=Open(path))using(var tr=db.TransactionManager.StartTransaction()){
     var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);int found=0;
     foreach(ObjectId bid in bt){
      var b=(BlockTableRecord)tr.GetObject(bid,OpenMode.ForRead);
      if(b.IsDependent||b.IsFromExternalReference||b.IsFromOverlayReference)continue;
      foreach(ObjectId id in b)if(tr.GetObject(id,OpenMode.ForRead) is RasterImage im){
       if(im.ImageDefId.IsNull||im.ReactorId.IsNull||!im.ShowImage)throw new System.Exception("Raster display association lost: "+im.Handle);
       var def=(RasterImageDef)tr.GetObject(im.ImageDefId,OpenMode.ForRead);
       if(Path.IsPathRooted(def.SourceFileName))throw new System.Exception("Raster path is not portable: "+def.SourceFileName);
       CheckRef(path,def.SourceFileName,Path.GetDirectoryName(path));found++;
      }
     }
     if(found!=count)throw new System.Exception("Raster fixture count mismatch: "+found+" / "+count);
    }
   }
'@
$l=One $l $anchor ($raster+[Environment]::NewLine+$anchor)
# Packing previously only changed SourceFileName; a failed/old active path
# could persist. Reload against the copied image, not the original Revit path.
$l=One $l 'def.SourceFileName=Link(source,final,def.SourceFileName,links,map);' 'string rel=Link(source,final,def.SourceFileName,links,map);string packed=Path.GetFullPath(Path.Combine(Path.GetDirectoryName(final),rel));SetRasterDefinition(def,final,packed);'
# Reopen check: verify the actual association and load state without saving.
# Keep the original stored path unchanged during validation.
$l=One $l 'foreach(var id in images)CheckRef(path,((RasterImageDef)tr.GetObject(id,OpenMode.ForRead)).SourceFileName,deliverable);' @'
foreach(var id in images){
     if(id.IsNull)throw new System.Exception("Raster definition missing: "+path);
     var def=(RasterImageDef)tr.GetObject(id,OpenMode.ForWrite);
     string absolute=CheckRef(path,def.SourceFileName,deliverable);
     InDb(db,()=>{def.ActiveFileName=absolute;if(!def.IsLoaded)def.Load();});
     if(!def.IsLoaded)throw new System.Exception("Raster could not be loaded from packed Links: "+absolute);
    }
'@
Write-Source 'Cad\LinkPack.cs' $l
Write-Host 'V2.6.4: persisted paper viewport geometry + camera validation, independent Mode A raster reload and moved-folder regression.'
