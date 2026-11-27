param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}
$p=Read-Source 'Cad\Processor.cs'
$p=One $p 'new Processor().Probe();' 'var probeJob=Job.Read(path);ProbeFor(probeJob.Model?"C":probeJob.Combine?"B":"A");'
$p=One $p 'var floating=VisibleViewportIds(sl,sp,st,modelBounds,say);' 'var floating=FloatingViewportIds(sl,sp,st,say);'
# Preserve the source enabled state in Mode B, rather than enabling every view.
$p=One $p 'InDb(target,()=>cloned.On=true);' 'InDb(target,()=>cloned.On=oldVp.On);'
Write-Source 'Cad\Processor.cs' $p

$m=Read-Source 'Cad\ModelMerge.cs'
$m=One $m 'public void Probe(){' 'public void Probe(){ProbeFor("ALL");} static void ProbeFor(string mode){'
$m=One $m 'var target=Path.Combine(folder,"M.dwg");' 'if(mode=="C"||mode=="ALL"){var target=Path.Combine(folder,"M.dwg");'
$m=One $m 'LinkPack.Check(target);' 'LinkPack.Check(target);}'
$m=One $m 'var layoutTests=new List<SheetItem>();' @'
    if(mode=="A"){File.AppendAllText(log,"PASS: Mode A DWG read, write and pack."+Environment.NewLine);File.WriteAllText(result,"PASS");return;}
    File.AppendAllText(log,"PREFLIGHT MODE "+mode+Environment.NewLine);
    var layoutTests=new List<SheetItem>();
'@
# The Autodesk Viewport API requires adding a viewport to the DB before setting its properties.
$m=One $m 'var floating=new Viewport{CenterPoint=new Point3d(90,60,0),Width=80,Height=60,ViewCenter=new Point2d(25,35),ViewHeight=100};' 'var floating=new Viewport();'
$m=One $m 'paper.AppendEntity(floating);tr.AddNewlyCreatedDBObject(floating,true);InDb(db,()=>floating.On=true);' @'
        paper.AppendEntity(floating);tr.AddNewlyCreatedDBObject(floating,true);
        InDb(db,()=>{
         floating.CenterPoint=new Point3d(90,60,0);
         floating.Width=80;floating.Height=60;
         floating.ViewDirection=Vector3d.ZAxis;floating.ViewTarget=Point3d.Origin;
         floating.ViewCenter=new Point2d(25,35);floating.ViewHeight=100;floating.TwistAngle=0;
         floating.PerspectiveOn=false;floating.FrontClipOn=false;floating.BackClipOn=false;
         floating.NonRectClipOn=false;floating.On=true;
        });
        File.AppendAllText(log,"FIXTURE VIEWPORT "+ViewportFlags(floating)+Environment.NewLine);
'@
# Keep B and C independently qualified; neither can fail solely because an unrelated probe failed.
$m=One $m 'Merge(layoutTests.Take(1).ToList(),Path.Combine(folder,"Lsingle.dwg"),DwgVersion.AC1032,report);' 'if(mode=="B"||mode=="ALL")Merge(layoutTests.Take(1).ToList(),Path.Combine(folder,"Lsingle.dwg"),DwgVersion.AC1032,report);if(mode=="C"||mode=="ALL"){'
$m=One $m 'report("PREFLIGHT: mixed layout merge");string mixed=' '}if(mode=="B"||mode=="ALL"){report("PREFLIGHT: mixed layout merge");string mixed='
$m=One $m 'File.AppendAllText(log,"PASS: paper-only + mixed Model/Paper Layout merge, single-sheet merge, DWG reopen."+Environment.NewLine);' 'File.AppendAllText(log,"PASS: Mode B paper-only + mixed Layout merge, single-sheet merge, DWG reopen."+Environment.NewLine);}'
$m=One $m 'File.AppendAllText(log,"PASS: side DB save/read, pack, merge two models and reopen."+Environment.NewLine);' 'File.AppendAllText(log,"PASS: selected preflight "+mode+"; DWG read/write and pack."+Environment.NewLine);'

# Never classify a viewport by its dimensions or scale alone. Autodesk documents
# that the first ID returned by GetViewports is the overall paper-space viewport.
$a=$m.IndexOf('  static List<ObjectId> VisibleViewportIds(')
$b=$m.IndexOf('  static void RepairRasterMap(',$a)
if($a -lt 0 -or $b -lt 0){throw 'Viewport selector boundary missing'}
$selector=@'
  static string ViewportFlags(Viewport vp){
   return "handle="+vp.Handle+" | Number="+vp.Number+" | On="+vp.On+" | dir="+vp.ViewDirection+
    " | target="+vp.ViewTarget+" | center="+vp.ViewCenter+" | twist="+vp.TwistAngle+
    " | perspective="+vp.PerspectiveOn+" | nonRect="+vp.NonRectClipOn+" | front="+vp.FrontClipOn+
    " | back="+vp.BackClipOn+" | frozen="+vp.GetFrozenLayers().Count+" | width="+vp.Width+" | height="+vp.Height+" | viewHeight="+vp.ViewHeight;
  }
  static List<ObjectId> FloatingViewportIds(Layout layout,BlockTableRecord paper,Transaction tr,Action<string> say){
   var all=new List<ObjectId>();
   foreach(ObjectId id in paper)if(tr.GetObject(id,OpenMode.ForRead) is Viewport)all.Add(id);
   if(all.Count==0)return all;
   var ids=layout.GetViewports();
   ObjectId overall=ids.Count>0?ids[0]:ObjectId.Null;
   if(overall.IsNull||!all.Contains(overall)){
    var identified=all.Where(id=>((Viewport)tr.GetObject(id,OpenMode.ForRead)).Number==1).ToList();
    if(identified.Count!=1)throw new System.Exception("Cannot identify overall paper viewport: "+layout.LayoutName+" | GetViewports="+ids.Count+" | entities="+all.Count);
    overall=identified[0];
   }
   foreach(var id in all)say("VP SOURCE "+layout.LayoutName+" | Overall="+(id==overall)+" | "+ViewportFlags((Viewport)tr.GetObject(id,OpenMode.ForRead)));
   return all.Where(id=>id!=overall).ToList();
  }
  static List<ObjectId> VisibleViewportIds(Layout layout,BlockTableRecord paper,Transaction tr,Extents3d? modelBounds,Action<string> say){
   if(!modelBounds.HasValue){say("PAPER ONLY "+layout.LayoutName);return new List<ObjectId>();}
   var floating=FloatingViewportIds(layout,paper,tr,say);
   var selected=floating.Where(id=>((Viewport)tr.GetObject(id,OpenMode.ForRead)).On).ToList();
   if(selected.Count==0)throw new System.Exception("Model has content but no enabled floating viewport: "+layout.LayoutName);
   return selected;
  }
'@
$m=$m.Substring(0,$a)+$selector+[Environment]::NewLine+$m.Substring($b)
# Support actual planar polygon boundaries, including Revit rectangular clips
# represented by a closed polyline. Do not approximate arcs or unsupported shapes.
$a=$m.IndexOf('  static void AddRectClip(')
$b=$m.IndexOf('  static void FlattenProjected(',$a)
if($a -lt 0 -or $b -lt 0){throw 'Spatial clip helper boundary missing'}
$clip=@'
  static void AddViewportClip(BlockReference block,Transaction dt,Transaction st,Viewport vp,Point3d center,double scale,Action<string> say){
   var points=new Point2dCollection();
   if(vp.NonRectClipOn){
    if(vp.NonRectClipEntityId.IsNull)throw new System.Exception("Enabled viewport clip has no boundary");
    var polygon=st.GetObject(vp.NonRectClipEntityId,OpenMode.ForRead) as Polyline;
    if(polygon==null||!polygon.Closed||polygon.NumberOfVertices<3||!polygon.Normal.GetNormal().IsEqualTo(Vector3d.ZAxis))
     throw new System.Exception("Unsupported non-rectangular clip geometry: "+vp.Handle);
    for(int i=0;i<polygon.NumberOfVertices;i++){
     if(Math.Abs(polygon.GetBulgeAt(i))>1e-10)throw new System.Exception("Curved viewport clip not supported: "+vp.Handle);
     var p=polygon.GetPoint3dAt(i);
     points.Add(new Point2d(center.X+(p.X-vp.CenterPoint.X)/scale,center.Y+(p.Y-vp.CenterPoint.Y)/scale));
    }
    say("POLYGON CLIP "+vp.Handle+" | vertices="+points.Count);
   }else{
    double width=vp.Width/scale,height=vp.Height/scale;
    points.Add(new Point2d(center.X-width/2,center.Y-height/2));
    points.Add(new Point2d(center.X+width/2,center.Y+height/2));
   }
   var filter=new Autodesk.AutoCAD.DatabaseServices.Filters.SpatialFilter();
   filter.Definition=new Autodesk.AutoCAD.DatabaseServices.Filters.SpatialFilterDefinition(points,Vector3d.ZAxis,0,0,0,true);
   block.CreateExtensionDictionary();
   var ext=(DBDictionary)dt.GetObject(block.ExtensionDictionary,OpenMode.ForWrite);
   var dictionary=new DBDictionary();ext.SetAt("ACAD_FILTER",dictionary);dt.AddNewlyCreatedDBObject(dictionary,true);
   dictionary.SetAt("SPATIAL",filter);dt.AddNewlyCreatedDBObject(filter,true);
  }
'@
$m=$m.Substring(0,$a)+$clip+[Environment]::NewLine+$m.Substring($b)
$m=One $m 'if(!IsTop2D(vp)||vp.NonRectClipOn||vp.FrontClipOn||vp.BackClipOn||vp.GetFrozenLayers().Count!=0)' 'if(!IsTop2D(vp)||vp.FrontClipOn||vp.BackClipOn||vp.GetFrozenLayers().Count!=0)'
$m=One $m 'throw new System.Exception("Unsupported viewport projection (only rectangular, top, zero twist, no VP freeze): "+layoutName+" | "+vp.Handle);' 'throw new System.Exception("Unsupported viewport projection: "+layoutName+" | "+ViewportFlags(vp));'
$m=One $m 'AddRectClip(block,dt,center,vp.Width/scale,vp.Height/scale);' 'AddViewportClip(block,dt,st,vp,center,scale,say);'
# Stronger mode C test: projected block position/scale must match the
# defined fixture, not merely contain a BlockReference.
$m=One $m 'if(!pms.Cast<ObjectId>().Any(id=>pt.GetObject(id,OpenMode.ForRead) is BlockReference))throw new System.Exception("Projected viewport block missing");' @'
     var blocks=pms.Cast<ObjectId>().Select(id=>pt.GetObject(id,OpenMode.ForRead)).OfType<BlockReference>().ToList();
     if(blocks.Count!=1)throw new System.Exception("Expected one projected viewport block; found "+blocks.Count);
     var projectedBlock=blocks[0];
     if(Math.Abs(projectedBlock.ScaleFactors.X-0.6)>1e-7||Math.Abs(projectedBlock.Position.X-75)>1e-6||Math.Abs(projectedBlock.Position.Y-39)>1e-6)
      throw new System.Exception("Projected fixture transform incorrect: "+projectedBlock.Position+" | "+projectedBlock.ScaleFactors);
'@
Write-Source 'Cad\ModelMerge.cs' $m
$c=Read-Source 'Revit\Command.cs'
$c=One $c 'clock.Elapsed-terminalAt.Value>TimeSpan.FromSeconds(15)' 'clock.Elapsed-terminalAt.Value>TimeSpan.FromSeconds(5)'
$c=One $c 'CSEHEADLESS\r\n_.QUIT\r\n",System.Text.Encoding.ASCII);' 'CSEHEADLESS\r\n_.QUIT\r\n_N\r\n",System.Text.Encoding.ASCII);'
Write-Source 'Revit\Command.cs' $c
Write-Host 'V2.6.3 mode-specific probes, resident viewport initialization, explicit viewport flags and guarded polygon clipping.'
