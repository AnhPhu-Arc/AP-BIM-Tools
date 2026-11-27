param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "2.6.8 source mismatch: $a"};return $s.Replace($a,$b)}
$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'static string Normalize(string path,string newName,DwgVersion version)' 'static string Normalize(string path,string newName,DwgVersion version,Action<string> report=null,bool fitPlot=false)'
$p=One $p 'lm.CurrentLayout=newName;});try{db.SaveAs(temp,version);}' 'lm.CurrentLayout=newName;});if(fitPlot)InDb(db,()=>FitSheetPlot(db,newName,report));try{db.SaveAs(temp,version);}'
$p=One $p 's.FinalDwg=Normalize(final,s.Layout,v);' 's.FinalDwg=Normalize(final,s.Layout,v,Say,!j.Model);'
$p=One $p 'foreach(var s in success){
       string flat=Path.Combine(stage,"F"+(success.IndexOf(s)+1).ToString("D4")+".dwg");' 'var sheetFrames=new Dictionary<string,Extents3d>(StringComparer.OrdinalIgnoreCase);
      foreach(var s in success){
       string flat=Path.Combine(stage,"F"+(success.IndexOf(s)+1).ToString("D4")+".dwg");
       sheetFrames.Add(flat,ReadPaperFrame(s.FinalDwg,s.Layout,Say));'
$p=One $p 'MergeFlattened(success,merged,v,j.Columns,j.Gap,Say);' 'MergeFlattened(success,merged,v,j.Columns,j.Gap,Say,sheetFrames);'
Write-Source 'Cad\Processor.cs' $p

$m=Read-Source 'Cad\ModelMerge.cs'
$anchor='  static void MergeFlattened(List<SheetItem> sheets,string path,DwgVersion version,int columns,double gap,Action<string> say){'
$helpers=@'
  // Frame geometry is read in the original paper coordinate system, before
  // projecting viewports. A clipped model block's extents must never set a grid cell.
  sealed class FrameEdge {
   public double X1,Y1,X2,Y2;
   public double Length{get{return Math.Max(Math.Abs(X2-X1),Math.Abs(Y2-Y1));}}
  }
  static void CollectFrameEdge(Point3d a,Point3d b,Matrix3d xf,List<FrameEdge> hs,List<FrameEdge> vs){
   a=a.TransformBy(xf);b=b.TransformBy(xf);
   double dx=Math.Abs(a.X-b.X),dy=Math.Abs(a.Y-b.Y),tol=Math.Max(1e-7,Math.Max(dx,dy)*1e-6);
   if(dx>tol&&dy<=tol)hs.Add(new FrameEdge{X1=Math.Min(a.X,b.X),X2=Math.Max(a.X,b.X),Y1=(a.Y+b.Y)/2,Y2=(a.Y+b.Y)/2});
   else if(dy>tol&&dx<=tol)vs.Add(new FrameEdge{Y1=Math.Min(a.Y,b.Y),Y2=Math.Max(a.Y,b.Y),X1=(a.X+b.X)/2,X2=(a.X+b.X)/2});
  }
  static void CollectFrameEdges(BlockTableRecord b,Transaction tr,Matrix3d xf,List<FrameEdge> hs,List<FrameEdge> vs,HashSet<ObjectId> chain,int depth,ref int budget){
   if(depth>12||!chain.Add(b.ObjectId))return;
   try{
    foreach(ObjectId id in b){
     if(--budget<0)return;
     if(!(tr.GetObject(id,OpenMode.ForRead) is Entity e)||!e.Visible||e is Viewport)continue;
     if(e is Line line)CollectFrameEdge(line.StartPoint,line.EndPoint,xf,hs,vs);
     else if(e is Polyline pl){
      int n=pl.NumberOfVertices,limit=pl.Closed?n:n-1;
      for(int i=0;i<limit;i++)if(Math.Abs(pl.GetBulgeAt(i))<1e-9)CollectFrameEdge(pl.GetPoint3dAt(i),pl.GetPoint3dAt((i+1)%n),xf,hs,vs);
     }else if(e is BlockReference br&&!br.BlockTableRecord.IsNull){
      var child=(BlockTableRecord)tr.GetObject(br.BlockTableRecord,OpenMode.ForRead);
      if(!child.IsFromExternalReference&&!child.IsFromOverlayReference)CollectFrameEdges(child,tr,xf*br.BlockTransform,hs,vs,chain,depth+1,ref budget);
     }
    }
   }finally{chain.Remove(b.ObjectId);}
  }
  static Extents3d? FindPaperRectangle(BlockTableRecord paper,Transaction tr){
   var hs=new List<FrameEdge>();var vs=new List<FrameEdge>();int budget=25000;
   CollectFrameEdges(paper,tr,Matrix3d.Identity,hs,vs,new HashSet<ObjectId>(),0,ref budget);
   // Longest edges first; a title-border rectangle must have all four edges.
   // Scan only paper geometry and nested title blocks, never viewport contents.
   var h=hs.OrderByDescending(e=>e.Length).Take(180).ToArray();
   var v=vs.OrderByDescending(e=>e.Length).Take(180).ToArray();
   Extents3d? best=null;double area=0;
   for(int i=0;i<h.Length;i++)for(int j=i+1;j<h.Length;j++){
    double x0=h[i].X1,x1=h[i].X2,y0=Math.Min(h[i].Y1,h[j].Y1),y1=Math.Max(h[i].Y1,h[j].Y1),w=x1-x0,z=y1-y0;
    if(w<=1e-7||z<=1e-7||w*z<=area||w/z>4||z/w>4)continue;
    double t=Math.Max(1e-6,Math.Max(w,z)*1e-5);
    if(Math.Abs(h[j].X1-x0)>t||Math.Abs(h[j].X2-x1)>t)continue;
    bool left=v.Any(e=>Math.Abs(e.X1-x0)<=t&&Math.Abs(e.Y1-y0)<=t&&Math.Abs(e.Y2-y1)<=t);
    if(!left)continue;
    bool right=v.Any(e=>Math.Abs(e.X1-x1)<=t&&Math.Abs(e.Y1-y0)<=t&&Math.Abs(e.Y2-y1)<=t);
    if(right){area=w*z;best=new Extents3d(new Point3d(x0,y0,0),new Point3d(x1,y1,0));}
   }
   return best;
  }
  static Extents3d? PaperContentBounds(BlockTableRecord paper,Transaction tr){
   Extents3d? all=null;
   foreach(ObjectId id in paper){
    if(!(tr.GetObject(id,OpenMode.ForRead) is Entity e)||e is Viewport||!e.Visible)continue;
    try{var ext=e.GeometricExtents;if(all.HasValue){var b=all.Value;b.AddExtents(ext);all=b;}else all=ext;}catch(Autodesk.AutoCAD.Runtime.Exception){}
   }
   return all;
  }
  static bool ValidFrame(Extents3d e){
   double w=e.MaxPoint.X-e.MinPoint.X,h=e.MaxPoint.Y-e.MinPoint.Y;
   return w>1e-7&&h>1e-7&&!double.IsInfinity(w)&&!double.IsInfinity(h)&&!double.IsNaN(w)&&!double.IsNaN(h);
  }
  static Extents3d ReadPaperFrame(string path,string layoutName,Action<string> say){
   using(var db=Open(path))using(var tr=db.TransactionManager.StartTransaction()){
    var ld=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
    var l=(Layout)tr.GetObject(ld.GetAt(layoutName),OpenMode.ForRead);
    var p=(BlockTableRecord)tr.GetObject(l.BlockTableRecordId,OpenMode.ForRead);
    var frame=FindPaperRectangle(p,tr);
    if(frame.HasValue&&ValidFrame(frame.Value)){say("SHEET FRAME RECT "+layoutName+" | "+frame.Value);return frame.Value;}
    // Fallback is paper-only geometry (never the unbounded model projection).
    frame=PaperContentBounds(p,tr);
    if(frame.HasValue&&ValidFrame(frame.Value)){say("SHEET FRAME PAPER FALLBACK "+layoutName+" | "+frame.Value);return frame.Value;}
    throw new System.Exception("Cannot establish paper frame for "+layoutName);
   }
  }
  sealed class FrameGrid {
   public double[] X,Y;public Extents3d[] Frames;
   public FrameGrid(Extents3d[] frames,int columns,double gap){
    if(frames.Length==0||columns<1||gap<0||double.IsNaN(gap)||double.IsInfinity(gap))throw new System.Exception("Invalid frame grid");
    Frames=frames;
    int nc=Math.Min(columns,frames.Length),nr=(frames.Length-1)/columns+1;
    var cw=new double[nc];var rh=new double[nr];X=new double[frames.Length];Y=new double[frames.Length];
    for(int i=0;i<frames.Length;i++){
     var f=frames[i];if(!ValidFrame(f))throw new System.Exception("Invalid sheet frame "+(i+1));
     cw[i%columns]=Math.Max(cw[i%columns],f.MaxPoint.X-f.MinPoint.X);
     rh[i/columns]=Math.Max(rh[i/columns],f.MaxPoint.Y-f.MinPoint.Y);
    }
    var cx=new double[nc];var ry=new double[nr];
    for(int i=1;i<nc;i++)cx[i]=cx[i-1]+cw[i-1]+gap;
    for(int i=1;i<nr;i++)ry[i]=ry[i-1]-rh[i-1]-gap;
    for(int i=0;i<frames.Length;i++){X[i]=cx[i%columns];Y[i]=ry[i/columns];}
   }
   public Point3d Insert(int i){return new Point3d(X[i]-Frames[i].MinPoint.X,Y[i]-Frames[i].MaxPoint.Y,0);}
  }
  static void VerifyGridPlacement(Database db,FrameGrid grid,Action<string> say){
   using(var tr=db.TransactionManager.StartTransaction()){
    var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);
    var model=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
    var byName=new Dictionary<string,BlockReference>(StringComparer.OrdinalIgnoreCase);
    foreach(ObjectId id in model){
     var br=tr.GetObject(id,OpenMode.ForRead) as BlockReference;
     if(br==null)throw new System.Exception("Unexpected ungrouped sheet entity");
     var def=(BlockTableRecord)tr.GetObject(br.BlockTableRecord,OpenMode.ForRead);
     byName.Add(def.Name,br);
    }
    if(byName.Count!=grid.Frames.Length)throw new System.Exception("Sheet grid count mismatch");
    for(int i=0;i<grid.Frames.Length;i++){
     if(!byName.TryGetValue("CSE_SHEET_"+(i+1).ToString("D4"),out var br))throw new System.Exception("Missing grid sheet "+(i+1));
     var expected=grid.Insert(i);
     double tol=Math.Max(1e-6,Math.Max(Math.Abs(expected.X),Math.Abs(expected.Y))*1e-9);
     if(Math.Abs(br.Position.X-expected.X)>tol||Math.Abs(br.Position.Y-expected.Y)>tol||Math.Abs(br.ScaleFactors.X-1)>1e-9||Math.Abs(br.ScaleFactors.Y-1)>1e-9||Math.Abs(br.Rotation)>1e-9)throw new System.Exception("Persisted grid placement mismatch "+(i+1));
    }
   }
   say("GRID FRAME REOPEN OK | "+grid.Frames.Length);
  }
  static void CheckGridMath(){
   var frames=Enumerable.Range(0,13).Select(i=>new Extents3d(new Point3d(100*i,-30*i,0),new Point3d(100*i+420+(i%3)*100,-30*i+297+(i%4)*40,0))).ToArray();
   foreach(int columns in new[]{1,5,6,10,20}){
    var g=new FrameGrid(frames,columns,25);
    for(int i=0;i<frames.Length;i++){
     var ins=g.Insert(i);if(Math.Abs(ins.X+frames[i].MinPoint.X-g.X[i])>1e-6||Math.Abs(ins.Y+frames[i].MaxPoint.Y-g.Y[i])>1e-6)throw new System.Exception("Frame anchor regression");
     if(i>=columns&&Math.Abs(g.X[i]-g.X[i-columns])>1e-6)throw new System.Exception("Frame column regression");
     if(i%columns!=0){int prev=i-1;if(g.Y[i]!=g.Y[prev]||g.X[i]<g.X[prev]+frames[prev].MaxPoint.X-frames[prev].MinPoint.X+25-1e-6)throw new System.Exception("Frame row regression");}
     for(int j=0;j<i;j++){
      var a=frames[i];var b=frames[j];double ax=g.X[i]+a.MaxPoint.X-a.MinPoint.X,ay=g.Y[i]-(a.MaxPoint.Y-a.MinPoint.Y),bx=g.X[j]+b.MaxPoint.X-b.MinPoint.X,by=g.Y[j]-(b.MaxPoint.Y-b.MinPoint.Y);
      if(Math.Min(ax,bx)-Math.Max(g.X[i],g.X[j])>1e-6&&Math.Min(g.Y[i],g.Y[j])-Math.Max(ay,by)>1e-6)throw new System.Exception("Frame overlap regression");
     }
    }
   }
  }
  // Plot setup is separate from floating viewport camera/scale. Use exact
  // title-border window, a compatible device/media and paper 1:1.
  static void FitSheetPlot(Database db,string name,Action<string> say){
   if(say==null)say=_=>{};
   try{
    using(var tr=db.TransactionManager.StartTransaction()){
     var ld=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
     var layout=(Layout)tr.GetObject(ld.GetAt(name),OpenMode.ForRead);
     var paper=(BlockTableRecord)tr.GetObject(layout.BlockTableRecordId,OpenMode.ForRead);
     var frame=FindPaperRectangle(paper,tr);
     if(!frame.HasValue||!ValidFrame(frame.Value)){say("PLOT FRAME SKIP | "+name+" | no closed outer rectangle");return;}
     var f=frame.Value;double w=f.MaxPoint.X-f.MinPoint.X,h=f.MaxPoint.Y-f.MinPoint.Y;
     // Revit DWG paper coordinates are normally millimetres. Only accept
     // plausible paper dimensions; preserve explicitly inch-based paper units.
     var units=layout.PlotPaperUnits;
     double factor=units==PlotPaperUnit.Inches&&Math.Max(w,h)<100?25.4:1;
     if(factor==1)units=PlotPaperUnit.Millimeters;
     double mmw=w*factor,mmh=h*factor;
     if(Math.Min(mmw,mmh)<70||Math.Max(mmw,mmh)>2500){say("PLOT FRAME SKIP | "+name+" | unqualified paper units");return;}
     var validator=PlotSettingsValidator.Current;
     string current=layout.PlotConfigurationName;
     string bestDevice=null,bestMedia=null;PlotRotation bestRotation=PlotRotation.Degrees000;double bestScore=double.PositiveInfinity;
     var devices=new[]{current,"DWG To PDF.pc3"}.Where(s=>!string.IsNullOrWhiteSpace(s)&&!s.Equals("None",StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase);
     foreach(string device in devices){
      using(var trial=new PlotSettings(false)){
       try{
        trial.CopyFrom(layout);validator.SetPlotConfigurationName(trial,device,null);validator.RefreshLists(trial);
        var media=validator.GetCanonicalMediaNameList(trial).Cast<string>().ToArray();
        foreach(string medium in media){
         try{
          validator.SetCanonicalMediaName(trial,medium);
          var size=trial.PlotPaperSize;var margin=trial.PlotPaperMargins;
          double pw=size.X-margin.MinPoint.X-margin.MaxPoint.X,ph=size.Y-margin.MinPoint.Y-margin.MaxPoint.Y;
          for(int rot=0;rot<2;rot++){
           double aw=rot==0?pw:ph,ah=rot==0?ph:pw,sw=rot==0?size.X:size.Y,sh=rot==0?size.Y:size.X;
           if(aw+0.001<mmw||ah+0.001<mmh||sw>mmw*1.20+10||sh>mmh*1.20+10)continue;
           double score=Math.Abs(sw-mmw)/mmw+Math.Abs(sh-mmh)/mmh+(device.Equals(current,StringComparison.OrdinalIgnoreCase)?0:0.015);
           if(score<bestScore){bestScore=score;bestDevice=device;bestMedia=medium;bestRotation=rot==0?PlotRotation.Degrees000:PlotRotation.Degrees090;}
          }
         }catch(Autodesk.AutoCAD.Runtime.Exception){}
        }
       }catch(Autodesk.AutoCAD.Runtime.Exception ex){say("PLOT DEVICE SKIP | "+name+" | "+device+" | "+ex.Message);}
      }
     }
     if(bestDevice==null){say("PLOT FRAME SKIP | "+name+" | no compatible 1:1 media "+mmw+"x"+mmh);return;}
     using(var ps=new PlotSettings(false)){
      ps.CopyFrom(layout);
      validator.SetPlotConfigurationName(ps,bestDevice,bestMedia);validator.RefreshLists(ps);
      validator.SetPlotPaperUnits(ps,units);validator.SetPlotRotation(ps,bestRotation);
      validator.SetPlotType(ps,Autodesk.AutoCAD.DatabaseServices.PlotType.Window);
      validator.SetPlotWindowArea(ps,new Extents2d(f.MinPoint.X,f.MinPoint.Y,f.MaxPoint.X,f.MaxPoint.Y));
      validator.SetUseStandardScale(ps,true);validator.SetStdScaleType(ps,StdScaleType.Scale1To1);
      validator.SetPlotCentered(ps,true);validator.SetZoomToPaperOnUpdate(ps,true);
      layout.UpgradeOpen();layout.CopyFrom(ps);layout.PlotSettingsName="";
      var win=layout.PlotWindowArea;double eps=Math.Max(1e-6,Math.Max(w,h)*1e-8);
      if(layout.PlotType!=Autodesk.AutoCAD.DatabaseServices.PlotType.Window||!layout.PlotCentered||Math.Abs(win.MinPoint.X-f.MinPoint.X)>eps||Math.Abs(win.MinPoint.Y-f.MinPoint.Y)>eps||Math.Abs(win.MaxPoint.X-f.MaxPoint.X)>eps||Math.Abs(win.MaxPoint.Y-f.MaxPoint.Y)>eps)throw new System.Exception("Plot window verification failed");
      tr.Commit();
      say("PLOT FRAME 1:1 OK | "+name+" | "+bestDevice+" | "+bestMedia+" | "+bestRotation+" | "+f);
     }
    }
   }catch(System.Exception ex){say("PLOT FRAME WARNING | "+name+" | "+ex.Message+" | source page setup retained");}
  }
'@
$m=One $m $anchor ($helpers+[Environment]::NewLine+'  static void MergeFlattened(List<SheetItem> sheets,string path,DwgVersion version,int columns,double gap,Action<string> say,Dictionary<string,Extents3d> paperFrames=null){')
$m=One $m 'using(var target=new Database(true,true)){double x=0,y=0,rowHeight=0;' @'
CheckGridMath();
   var frameList=new List<Extents3d>();
   foreach(string flat in flats){
    if(paperFrames!=null){
     if(!paperFrames.TryGetValue(flat,out var paperFrame))throw new System.Exception("Missing original paper frame "+flat);
     frameList.Add(paperFrame);
    }else{
     using(var fdb=Open(flat))using(var ft=fdb.TransactionManager.StartTransaction()){
      var fbt=(BlockTable)ft.GetObject(fdb.BlockTableId,OpenMode.ForRead);
      var fm=(BlockTableRecord)ft.GetObject(fbt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
      var f=FindPaperRectangle(fm,ft)??PaperContentBounds(fm,ft);
      if(!f.HasValue||!ValidFrame(f.Value))throw new System.Exception("Invalid direct flattened fixture frame");
      frameList.Add(f.Value);
     }
    }
   }
   var grid=new FrameGrid(frameList.ToArray(),columns,gap);
   using(var target=new Database(true,true)){
'@
$m=One $m 'var ids=new ObjectIdCollection();Extents3d? bounds=null;foreach(ObjectId id in sm){var ent=st.GetObject(id,OpenMode.ForRead) as Entity;if(ent==null)continue;ids.Add(id);try{var ex=ent.GeometricExtents;if(bounds.HasValue){var b=bounds.Value;b.AddExtents(ex);bounds=b;}else bounds=ex;}catch(Autodesk.AutoCAD.Runtime.Exception){}}if(ids.Count==0||!bounds.HasValue)throw new System.Exception("Empty flattened model: "+sheets[i].Number);var ext=bounds.Value;double w=ext.MaxPoint.X-ext.MinPoint.X,h=ext.MaxPoint.Y-ext.MinPoint.Y;if(w<=0||h<=0)throw new System.Exception("Invalid sheet bounds");if(i%columns==0&&i>0){x=0;y-=rowHeight+gap;rowHeight=0;}' 'var ids=new ObjectIdCollection();foreach(ObjectId id in sm)if(st.GetObject(id,OpenMode.ForRead) is Entity)ids.Add(id);if(ids.Count==0)throw new System.Exception("Empty flattened model: "+sheets[i].Number);'
$m=One $m 'new Point3d(x-ext.MinPoint.X,y-ext.MaxPoint.Y,0)' 'grid.Insert(i)'
$m=One $m 'x+=w+gap;rowHeight=Math.Max(rowHeight,h);' 'say("GRID FRAME "+sheets[i].Number+" | row="+(i/columns+1)+" | col="+(i%columns+1)+" | anchor="+grid.X[i]+","+grid.Y[i]+" | frame="+grid.Frames[i]);'
$m=One $m 'say("MODEL VERIFIED: "+sheets.Count+" sheets");' 'using(var gridCheck=Open(path))VerifyGridPlacement(gridCheck,grid,say);say("MODEL VERIFIED: "+sheets.Count+" sheets");'
Write-Source 'Cad\ModelMerge.cs' $m
Write-Host 'V2.6.8 candidate: original paper title-frame grid, per-column/row dimensions, persisted placements, 1:1 plot window.'
