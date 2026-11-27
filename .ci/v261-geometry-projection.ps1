param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}

$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'var parts=new List<LayerAndLayout>();foreach(var s in sheets)' 'var parts=new List<LayerAndLayout>();double nextModelX=0;foreach(var s in sheets)'
$p=One $p 'CloneSheet(src,target,s.Layout,parts.Count+1,say)' 'CloneSheet(src,target,s.Layout,parts.Count+1,ref nextModelX,say)'
$p=One $p 'static LayerAndLayout CloneSheet(Database src,Database target,string name,int index,Action<string> say)' 'static LayerAndLayout CloneSheet(Database src,Database target,string name,int index,ref double nextModelX,Action<string> say)'
$p=One $p 'var br=new BlockReference(Point3d.Origin,modelBlock){LayerId=lid};destModel.AppendEntity(br);dt.AddNewlyCreatedDBObject(br,true);' @'
   Extents3d? modelBounds=EntityBounds(sm,st);
   Vector3d shift=Vector3d.Zero;
   if(modelBounds.HasValue){
    var e=modelBounds.Value;
    shift=new Vector3d(nextModelX-e.MinPoint.X,-e.MinPoint.Y,0);
    nextModelX+=Math.Max(1,e.MaxPoint.X-e.MinPoint.X)+1000;
    var br=new BlockReference(Point3d.Origin+shift,modelBlock){LayerId=lid};
    destModel.AppendEntity(br);dt.AddNewlyCreatedDBObject(br,true);
   }
   say("MODEL OFFSET "+name+" | "+shift);
'@
$p=One $p 'var modelIds=new ObjectIdCollection();foreach(ObjectId id in sm)modelIds.Add(id);var paperIds=new ObjectIdCollection();foreach(ObjectId id in sp)paperIds.Add(id);' @'
   var modelIds=new ObjectIdCollection();foreach(ObjectId id in sm)modelIds.Add(id);
   var floating=VisibleViewportIds(sl,sp,st,modelBounds,say);
   // Do not use the Number property to identify inactive viewports in side DBs.
   // Keep the original overall viewport in the cloned layout, but never freeze or
   // shift its paper-space camera. Restore the floating camera after clone.
   var paperIds=new ObjectIdCollection();foreach(ObjectId id in sp)paperIds.Add(id);
'@
$p=One $p 'var sourceVps=sl.GetViewports();ObjectId overall=sourceVps.Count>0?sourceVps[0]:ObjectId.Null;var floating=new List<ObjectId>();foreach(ObjectId id in paperIds){if(id!=overall&&st.GetObject(id,OpenMode.ForRead) is Viewport vp&&vp.Number!=1)floating.Add(id);}say("VIEWPORTS "+name+" | FLOATING="+floating.Count);' 'say("VIEWPORTS "+name+" | FLOATING="+floating.Count);'
$p=One $p 'var cloned=(Viewport)dt.GetObject(clonedId,OpenMode.ForWrite);var frozen=new ObjectIdCollection();' @'
   var cloned=(Viewport)dt.GetObject(clonedId,OpenMode.ForWrite);
   cloned.Locked=false;
   cloned.ViewDirection=oldVp.ViewDirection;
   cloned.ViewTarget=oldVp.ViewTarget+shift;
   cloned.ViewCenter=oldVp.ViewCenter;
   cloned.ViewHeight=oldVp.ViewHeight;
   cloned.TwistAngle=oldVp.TwistAngle;
   InDb(target,()=>cloned.On=true);
   say("VIEWPORT MAP "+name+" | "+oldVp.Handle+" -> "+cloned.Handle+" | target="+cloned.ViewTarget+" | center="+cloned.ViewCenter+" | scale="+cloned.CustomScale);
   var frozen=new ObjectIdCollection();
'@
$p=One $p 'var result=new LayerAndLayout{Layer=lid,Layout=layout.ObjectId,Viewports=viewIds,Entities=paperIds.Count};' 'InDb(target,()=>RepairRasterMap(src,target,st,dt,map,say));var result=new LayerAndLayout{Layer=lid,Layout=layout.ObjectId,Viewports=viewIds,Entities=paperIds.Count};'
# Check that independent source models occupy disjoint X ranges after reopen.
$p=One $p 'var found=Layouts(verify,true);' 'VerifyModelIsolation(verify);var found=Layouts(verify,true);'
$p=One $p 'FlattenPaperOnly(s.FinalDwg,s.Layout,flat,v,Say);' 'FlattenProjected(s.FinalDwg,s.Layout,flat,v,Say);'
Write-Source 'Cad\Processor.cs' $p

$m=Read-Source 'Cad\ModelMerge.cs'
$anchor='  static void InspectSourceLayouts(Job job,string work){'
$helpers=@'
  static Extents3d? EntityBounds(BlockTableRecord space,Transaction tr){
   Extents3d? result=null;
   foreach(ObjectId id in space){
    if(!(tr.GetObject(id,OpenMode.ForRead) is Entity e)||e is Viewport)continue;
    try{var ext=e.GeometricExtents;if(result.HasValue){var b=result.Value;b.AddExtents(ext);result=b;}else result=ext;}
    catch(Autodesk.AutoCAD.Runtime.Exception ex){throw new System.Exception("Cannot establish entity extents: "+e.Handle,ex);}
   }
   return result;
  }
  static void VerifyModelIsolation(Database db){
   using(var tr=db.TransactionManager.StartTransaction()){
    var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);
    var ms=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
    var ranges=new List<Tuple<double,double>>();
    foreach(ObjectId id in ms){
     var br=tr.GetObject(id,OpenMode.ForRead) as BlockReference;
     if(br==null)throw new System.Exception("Unexpected ungrouped Model entity after Layout merge");
     var e=br.GeometricExtents;ranges.Add(Tuple.Create(e.MinPoint.X,e.MaxPoint.X));
    }
    var sorted=ranges.OrderBy(x=>x.Item1).ToList();
    for(int i=1;i<sorted.Count;i++)if(sorted[i].Item1<sorted[i-1].Item2-1e-6)throw new System.Exception("Model blocks overlap after merge");
   }
  }
  static bool IsTop2D(Viewport vp){
   return vp.ViewDirection.GetNormal().IsEqualTo(Vector3d.ZAxis)&&Math.Abs(vp.TwistAngle)<1e-8&&!vp.PerspectiveOn;
  }
  static Point3d ViewWorldCenter(Viewport vp){
   // DCS origin is ViewTarget. For top orthographic views with zero twist,
   // the DCS horizontal axes coincide with WCS X/Y.
   return vp.ViewTarget+new Vector3d(vp.ViewCenter.X,vp.ViewCenter.Y,0);
  }
  static bool IntersectsView(Viewport vp,Extents3d b){
   if(!IsTop2D(vp))return true;
   if(vp.ViewHeight<=0||vp.Height<=0||vp.Width<=0)return false;
   var c=ViewWorldCenter(vp);double hy=vp.ViewHeight/2,hx=hy*vp.Width/vp.Height;
   return b.MaxPoint.X>=c.X-hx&&b.MinPoint.X<=c.X+hx&&b.MaxPoint.Y>=c.Y-hy&&b.MinPoint.Y<=c.Y+hy;
  }
  static List<ObjectId> VisibleViewportIds(Layout layout,BlockTableRecord paper,Transaction tr,Extents3d? modelBounds,Action<string> say){
   var all=new List<ObjectId>();
   foreach(ObjectId id in paper)if(tr.GetObject(id,OpenMode.ForRead) is Viewport)all.Add(id);
   var ids=layout.GetViewports();
   ObjectId overall=ids.Count>0?ids[0]:ObjectId.Null;
   // In inactive side databases Number may be -1. GetViewports identifies
   // the overall viewport. For an empty Model there is nothing to project.
   if(!modelBounds.HasValue){say("PAPER ONLY "+layout.LayoutName+" | VP="+all.Count);return new List<ObjectId>();}
   var selected=new List<ObjectId>();
   foreach(var id in all){
    var vp=(Viewport)tr.GetObject(id,OpenMode.ForRead);
    bool intersects=IntersectsView(vp,modelBounds.Value);
    say("VP SOURCE "+layout.LayoutName+" | "+vp.Handle+" | Number="+vp.Number+" | On="+vp.On+" | Overall="+(id==overall)+" | intersects="+intersects);
    if(id!=overall&&vp.Number!=1&&vp.On&&intersects)selected.Add(id);
   }
   // Do not silently output a blank drawing if the overall ID is unavailable
   // or the persisted view state cannot be interpreted.
   if(selected.Count==0){
    // Some side databases do not enumerate the paper-space viewport reliably.
    // Recover only an unambiguous, enabled, non-1:1 view intersecting the model.
    var candidates=all.Where(id=>{
     var vp=(Viewport)tr.GetObject(id,OpenMode.ForRead);
     return vp.On&&vp.Number!=1&&IsTop2D(vp)&&vp.Height>0&&vp.ViewHeight>0&&Math.Abs(vp.ViewHeight/vp.Height-1)>1e-6&&IntersectsView(vp,modelBounds.Value);
    }).ToList();
    if(candidates.Count==1){selected.Add(candidates[0]);say("VP RECOVERY: "+layout.LayoutName+" | "+candidates[0].Handle);}
    else throw new System.Exception("No qualified visible Model viewport: "+layout.LayoutName+" | see VP SOURCE log");
   }
   return selected;
  }
  static void RepairRasterMap(Database src,Database dest,Transaction st,Transaction dt,IdMapping map,Action<string> say){
   var repaired=new Dictionary<ObjectId,ObjectId>();
   string sourceRoot=Path.GetDirectoryName(Path.GetFullPath(src.Filename));
   RasterImage.EnableReactors(true);
   foreach(IdPair pair in map){
    if(!pair.IsCloned||pair.Key.IsNull||pair.Value.IsNull)continue;
    if(!(st.GetObject(pair.Key,OpenMode.ForRead) is RasterImage original))continue;
    var image=dt.GetObject(pair.Value,OpenMode.ForWrite) as RasterImage;
    if(image==null)throw new System.Exception("Raster clone missing: "+original.Handle);
    var originalDef=(RasterImageDef)st.GetObject(original.ImageDefId,OpenMode.ForRead);
    string reference=originalDef.SourceFileName;
    string absolute=Path.GetFullPath(Path.IsPathRooted(reference)?reference:Path.Combine(sourceRoot,reference));
    if(!File.Exists(absolute))throw new System.Exception("Raster source missing: "+absolute);
    ObjectId defId;
    // Reuse the correctly mapped definition and reactor if they survived
    // deep-clone. Rebuild only if the original association is missing/wrong.
    var current=image.ImageDefId.IsNull?null:dt.GetObject(image.ImageDefId,OpenMode.ForRead) as RasterImageDef;
    string mapped=current==null?"":current.SourceFileName;
    bool same=!string.IsNullOrWhiteSpace(mapped)&&string.Equals(Path.GetFullPath(Path.IsPathRooted(mapped)?mapped:Path.Combine(sourceRoot,mapped)),absolute,StringComparison.OrdinalIgnoreCase);
    if(same&&!image.ReactorId.IsNull){
     current.UpgradeOpen();current.SourceFileName=absolute;if(!current.IsLoaded)current.Load();
    }else{
     if(!repaired.TryGetValue(original.ImageDefId,out defId)){
      var dictionaryId=RasterImageDef.GetImageDictionary(dest);
      if(dictionaryId.IsNull)dictionaryId=RasterImageDef.CreateImageDictionary(dest);
      var dictionary=(DBDictionary)dt.GetObject(dictionaryId,OpenMode.ForWrite);
      var definition=new RasterImageDef{SourceFileName=absolute};
      definition.Load();
      defId=dictionary.SetAt("CSE_IMG_"+Guid.NewGuid().ToString("N"),definition);
      dt.AddNewlyCreatedDBObject(definition,true);
      repaired.Add(original.ImageDefId,defId);
     }
     image.ImageDefId=defId;
     image.AssociateRasterDef((RasterImageDef)dt.GetObject(defId,OpenMode.ForWrite));
    }
    image.ShowImage=original.ShowImage;
    if(image.ReactorId.IsNull)throw new System.Exception("Raster reactor missing: "+original.Handle);
    say("RASTER MAP "+original.Handle+" -> "+image.Handle+" | "+absolute+" | Show="+image.ShowImage);
   }
  }
  static void AddRectClip(BlockReference block,Transaction tr,Point3d center,double width,double height){
   // The clip coordinates belong to the unscaled model block definition.
   var points=new Point2dCollection();
   points.Add(new Point2d(center.X-width/2,center.Y-height/2));
   points.Add(new Point2d(center.X+width/2,center.Y+height/2));
   var filter=new Autodesk.AutoCAD.DatabaseServices.Filters.SpatialFilter();
   filter.Definition=new Autodesk.AutoCAD.DatabaseServices.Filters.SpatialFilterDefinition(points,Vector3d.ZAxis,0,0,0,true);
   block.CreateExtensionDictionary();
   var ext=(DBDictionary)tr.GetObject(block.ExtensionDictionary,OpenMode.ForWrite);
   var dictionary=new DBDictionary();ext.SetAt("ACAD_FILTER",dictionary);tr.AddNewlyCreatedDBObject(dictionary,true);
   dictionary.SetAt("SPATIAL",filter);tr.AddNewlyCreatedDBObject(filter,true);
  }
  static void FlattenProjected(string input,string layoutName,string output,DwgVersion version,Action<string> say){
   using(var src=Open(input))using(var st=src.TransactionManager.StartTransaction())using(var dest=new Database(true,true)){
    var ld=(DBDictionary)st.GetObject(src.LayoutDictionaryId,OpenMode.ForRead);
    var layout=(Layout)st.GetObject(ld.GetAt(layoutName),OpenMode.ForRead);
    var paper=(BlockTableRecord)st.GetObject(layout.BlockTableRecordId,OpenMode.ForRead);
    var sbt=(BlockTable)st.GetObject(src.BlockTableId,OpenMode.ForRead);
    var model=(BlockTableRecord)st.GetObject(sbt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
    var bounds=EntityBounds(model,st);
    var viewports=VisibleViewportIds(layout,paper,st,bounds,say);
    var paperIds=new ObjectIdCollection();var modelIds=new ObjectIdCollection();
    foreach(ObjectId id in paper){
     if(!(st.GetObject(id,OpenMode.ForRead) is Entity ent)||ent is Viewport)continue;
     if(ent is ProxyEntity||ent is Ole2Frame||ent is UnderlayReference)throw new System.Exception("Unsupported paper entity: "+ent.GetType().Name);
     paperIds.Add(id);
    }
    foreach(ObjectId id in model)modelIds.Add(id);
    dest.Insunits=src.Insunits;
    InDb(dest,()=>{using(var dt=dest.TransactionManager.StartTransaction()){
     var bt=(BlockTable)dt.GetObject(dest.BlockTableId,OpenMode.ForWrite);
     var ms=(BlockTableRecord)dt.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForWrite);
     // First paint the model projection, then the paper-space annotations.
     foreach(var id in viewports){
      var vp=(Viewport)st.GetObject(id,OpenMode.ForRead);
      if(!IsTop2D(vp)||vp.NonRectClipOn||vp.FrontClipOn||vp.BackClipOn||vp.GetFrozenLayers().Count!=0)
       throw new System.Exception("Unsupported viewport projection (only rectangular, top, zero twist, no VP freeze): "+layoutName+" | "+vp.Handle);
      if(vp.ViewHeight<=0||vp.Height<=0||vp.Width<=0)throw new System.Exception("Invalid viewport dimensions");
      double scale=vp.Height/vp.ViewHeight;
      var center=ViewWorldCenter(vp);
      var pos=vp.CenterPoint-new Vector3d(center.X*scale,center.Y*scale,0);
      var btr=new BlockTableRecord{Name="CSE_VP_"+Guid.NewGuid().ToString("N"),Origin=Point3d.Origin};
      ObjectId bid=bt.Add(btr);dt.AddNewlyCreatedDBObject(btr,true);
      var map=new IdMapping();src.WblockCloneObjects(modelIds,bid,map,DuplicateRecordCloning.MangleName,false);
      RepairRasterMap(src,dest,st,dt,map,say);
      var block=new BlockReference(pos,bid){ScaleFactors=new Scale3d(scale)};
      ms.AppendEntity(block);dt.AddNewlyCreatedDBObject(block,true);
      AddRectClip(block,dt,center,vp.Width/scale,vp.Height/scale);
      say("PROJECT "+layoutName+" | "+vp.Handle+" | scale="+scale+" | paper center="+vp.CenterPoint+" | model center="+center);
     }
     if(paperIds.Count>0){
      var map=new IdMapping();src.WblockCloneObjects(paperIds,ms.ObjectId,map,DuplicateRecordCloning.MangleName,false);
      RepairRasterMap(src,dest,st,dt,map,say);
     }
     if(paperIds.Count==0&&viewports.Count==0)throw new System.Exception("Empty projected sheet");
     dt.Commit();
    }});
    dest.SaveAs(output,version);
   }
   ValidateFlattened(output,layoutName);
   say("PROJECTED SHEET "+layoutName);
  }
'@
$m=One $m $anchor ($helpers+[Environment]::NewLine+$anchor)
# The 2.6.0 test expected projection to fail. Replace by a real projection test.
$a=$m.IndexOf('    bool refusedFloating=false;')
$b=$m.IndexOf('    string mixed=',$a)
if($a -lt 0 -or $b -lt 0){throw 'Probe projection boundary missing'}
$projectedProbe=@'
    string projected=Path.Combine(folder,"Fprojected.dwg");
    FlattenProjected(layoutTests[1].FinalDwg,layoutTests[1].Layout,projected,DwgVersion.AC1032,report);
    ValidateFlattened(projected,layoutTests[1].Number);
    using(var pd=Open(projected))using(var pt=pd.TransactionManager.StartTransaction()){
     var pbt=(BlockTable)pt.GetObject(pd.BlockTableId,OpenMode.ForRead);
     var pms=(BlockTableRecord)pt.GetObject(pbt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
     if(!pms.Cast<ObjectId>().Any(id=>pt.GetObject(id,OpenMode.ForRead) is BlockReference))throw new System.Exception("Projected viewport block missing");
    }
'@
$m=$m.Substring(0,$a)+$projectedProbe+[Environment]::NewLine+$m.Substring($b)
# Preserve the existing mixed Layout probe; remove temporary placeholder.
$m=One $m 'paper.AppendEntity(floating);tr.AddNewlyCreatedDBObject(floating,true);' 'paper.AppendEntity(floating);tr.AddNewlyCreatedDBObject(floating,true);InDb(db,()=>floating.On=true);'
# Paper-only test must no longer depend on Viewport.Number.
$m=One $m 'FlattenPaperOnly(layoutTests[0].FinalDwg,layoutTests[0].Layout,paperFlat,DwgVersion.AC1032,report);' 'FlattenProjected(layoutTests[0].FinalDwg,layoutTests[0].Layout,paperFlat,DwgVersion.AC1032,report);'
# Repair references on the final clone as well, not only the intermediate projection.
$m=One $m 'src.WblockCloneObjects(ids,bid,new IdMapping(),DuplicateRecordCloning.MangleName,false);' 'var cloneMap=new IdMapping();src.WblockCloneObjects(ids,bid,cloneMap,DuplicateRecordCloning.MangleName,false);InDb(target,()=>RepairRasterMap(src,target,st,dt,cloneMap,say));'
$m=One $m 'for(int i=0;i<2;i++){
     string name="TEST-LAYOUT-"+i' 'for(int i=0;i<3;i++){
     string name="TEST-LAYOUT-"+i'
$m=One $m 'if(i==1){
        var bt=(BlockTable)' 'if(i>0){
        var bt=(BlockTable)'
# Real raster fixture in a paper-only layout. The PNG is synthetic and public-safe.
$m=One $m 'var layoutTests=new List<SheetItem>();' @'
var layoutTests=new List<SheetItem>();
    string imagePath=Path.Combine(Directory.CreateDirectory(Path.Combine(folder,"Links")).FullName,"probe.png");
    File.WriteAllBytes(imagePath,Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP8z4AdMOEQH6QSAM1BAQ/oQeJvAAAAAElFTkSuQmCC"));
'@
$m=One $m 'paper.AppendEntity(border);tr.AddNewlyCreatedDBObject(border,true);' @'
paper.AppendEntity(border);tr.AddNewlyCreatedDBObject(border,true);
       if(i==0){
        InDb(db,()=>{
         var imageDictId=RasterImageDef.GetImageDictionary(db);
         if(imageDictId.IsNull)imageDictId=RasterImageDef.CreateImageDictionary(db);
         var imageDict=(DBDictionary)tr.GetObject(imageDictId,OpenMode.ForWrite);
         var definition=new RasterImageDef{SourceFileName=imagePath};
         definition.Load();
         var imageId=imageDict.SetAt("PROBE_LOGO",definition);tr.AddNewlyCreatedDBObject(definition,true);
         var image=new RasterImage{ImageDefId=imageId,Orientation=new CoordinateSystem3d(new Point3d(10,10,0),new Vector3d(15,0,0),new Vector3d(0,15,0)),ShowImage=true};
         paper.AppendEntity(image);tr.AddNewlyCreatedDBObject(image,true);
         RasterImage.EnableReactors(true);image.AssociateRasterDef(definition);
        });
       }
'@
$m=One $m 'LinkPack.Check(mixed);' @'
LinkPack.Check(mixed);
    using(var check=Open(mixed))using(var ct=check.TransactionManager.StartTransaction()){
     var bt=(BlockTable)ct.GetObject(check.BlockTableId,OpenMode.ForRead);
     int n=0;foreach(ObjectId bid in bt){
      var btr=(BlockTableRecord)ct.GetObject(bid,OpenMode.ForRead);
      foreach(ObjectId eid in btr){if(ct.GetObject(eid,OpenMode.ForRead) is RasterImage image){
       if(image.ImageDefId.IsNull||image.ReactorId.IsNull||!image.ShowImage)throw new System.Exception("Raster fixture lost its display association");
       n++;
      }}
     }
     if(n!=1)throw new System.Exception("Raster fixture count mismatch: "+n);
    }
    File.AppendAllText(log,"PASS: cloned raster image definition and reactor survive save/reopen."+Environment.NewLine);
'@
$m=One $m 'if(names.Count!=2||layoutTests.Any' 'if(names.Count!=layoutTests.Count||layoutTests.Any'
Write-Source 'Cad\ModelMerge.cs' $m
$c=Read-Source 'Revit\Command.cs'
$c=One $c 'Mode C thử nghiệm chạy nền: chỉ hỗ trợ Sheet không có viewport nổi. Sheet có viewport sẽ dừng an toàn, không mở AutoCAD Desktop. Tiếp tục?' 'Mode C chạy nền thử nghiệm: hỗ trợ viewport 2D trực giao hình chữ nhật, không mở AutoCAD Desktop. Kiểm tra bản vẽ đầu ra trước khi phát hành. Tiếp tục?'
Write-Source 'Revit\Command.cs' $c
Write-Host 'V2.6.1 candidate: separated Model blocks, camera translation, raster associations, rectangular top-view projection.'
