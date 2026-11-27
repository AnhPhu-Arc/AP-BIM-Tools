param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Read-Source([string]$p){[IO.File]::ReadAllText((Join-Path $CadExportRoot $p),$utf8)}
function Write-Source([string]$p,[string]$s){[IO.File]::WriteAllText((Join-Path $CadExportRoot $p),$s,$utf8)}
function One([string]$s,[string]$a,[string]$b){if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Source mismatch: $a"};return $s.Replace($a,$b)}

$p=Read-Source 'Cad\Processor.cs'
# Snapshot persisted on/off state BEFORE starting a source transaction.
# On is an editor-dependent property; it is not a reliable source for an inactive layout.
$p=One $p 'ObjectId layoutId=ObjectId.Null;' 'var sourceFlags=ReadStoredViewportFlags(src,say);ObjectId layoutId=ObjectId.Null;'
$p=One $p 'new ViewportSnapshot(oldVp,shift,clonedId,name)' 'new ViewportSnapshot(oldVp,shift,clonedId,name,GetStoredViewportEnabled(sourceFlags,oldVp.Handle.ToString()))'
$p=One $p 'snapshot.Assert(vp);' @'
snapshot.Assert(vp,true);
     snapshot.ExpectedFrozenHandles=allFrozen.Cast<ObjectId>().Select(f=>f.Handle.ToString()).ToArray();
     snapshot.AssertFrozen(vp);
'@
Write-Source 'Cad\Processor.cs' $p

$m=Read-Source 'Cad\ModelMerge.cs'
$m=One $m 'public ViewportSnapshot(Viewport src,Vector3d shift,ObjectId id,string name){' 'public string[] ExpectedFrozenHandles=new string[0];public ViewportSnapshot(Viewport src,Vector3d shift,ObjectId id,string name,bool enabled){'
$m=One $m 'Enabled=src.On;Locked=src.Locked;Clipped=src.NonRectClipOn;' 'Enabled=enabled;Locked=src.Locked;Clipped=src.NonRectClipOn;'
$m=One $m 'public void Assert(Viewport dest){' @'
   public void AssertFrozen(Viewport dest){
    var actual=new HashSet<string>(dest.GetFrozenLayers().Cast<ObjectId>().Select(f=>f.Handle.ToString()),StringComparer.OrdinalIgnoreCase);
    if(!actual.SetEquals(ExpectedFrozenHandles))throw new System.Exception("Viewport frozen-layer mapping mismatch: "+LayoutName+" | "+HandleText);
   }
   public void Assert(Viewport dest,bool activeLayout){
'@
$m=One $m 'if(!size||!camera||!scale||dest.On!=Enabled||dest.NonRectClipOn!=Clipped||dest.Locked!=Locked)' 'if(!size||!camera||!scale||(activeLayout&&dest.On!=Enabled)||dest.NonRectClipOn!=Clipped||dest.Locked!=Locked)'
$m=One $m '+" | scale="+scale+" | expected center="' '+" | scale="+scale+" | activeCheck="+activeLayout+" | expected On="+Enabled+" | expected center="'
# The ASCII DXF is a READ-ONLY inspection artifact, never converted back into
# the DWG. Use Autodesk's documented group 90 bit 0x20000, not the transient
# Number or On property. Group 68 is logged for diagnostics only.
$anchor='  static void VerifyViewportSnapshots(Database db,List<ViewportSnapshot> expected,Action<string> say){'
$helper=@'
  sealed class StoredViewportFlags {
   public int Flags; public int? Status; public bool Enabled{get{return (Flags&0x20000)==0;}}
  }
  static Dictionary<string,StoredViewportFlags> ParseStoredViewportFlags(TextReader reader){
   var result=new Dictionary<string,StoredViewportFlags>(StringComparer.OrdinalIgnoreCase);
   string entity="",handle=null;int? flags=null,status=null;bool subclass=false;
   Action flush=()=>{
    if(entity=="VIEWPORT"){
     if(string.IsNullOrEmpty(handle)||!flags.HasValue)throw new System.Exception("DXF viewport is missing a handle or group 90.");
     if(result.ContainsKey(handle))throw new System.Exception("Duplicate DXF viewport handle: "+handle);
     result.Add(handle,new StoredViewportFlags{Flags=flags.Value,Status=status});
    }
   };
   string codeLine;
   while((codeLine=reader.ReadLine())!=null){
    string value=reader.ReadLine();
    if(value==null)throw new System.Exception("Truncated viewport inspection DXF.");
    if(!int.TryParse(codeLine.Trim(),System.Globalization.NumberStyles.Integer,System.Globalization.CultureInfo.InvariantCulture,out int code))throw new System.Exception("Invalid DXF group code.");
    value=value.Trim();
    if(code==0){flush();entity=value;handle=null;flags=null;status=null;subclass=false;continue;}
    if(entity!="VIEWPORT")continue;
    if(code==100){subclass=value=="AcDbViewport";continue;}
    if(code==5&&handle==null)handle=value;
    if(subclass&&code==90)flags=int.Parse(value,System.Globalization.CultureInfo.InvariantCulture);
    if(subclass&&code==68)status=int.Parse(value,System.Globalization.CultureInfo.InvariantCulture);
   }
   flush();return result;
  }
  static Dictionary<string,StoredViewportFlags> ReadStoredViewportFlags(Database db,Action<string> say){
   string filename=db.Filename;
   string root=Path.GetDirectoryName(Path.GetFullPath(filename));
   string dxf=Path.Combine(root,"VPCHK_"+Guid.NewGuid().ToString("N").Substring(0,8)+".dxf");
   try{
    InDb(db,()=>db.DxfOut(dxf,16,DwgVersion.AC1032));
    using(var reader=new StreamReader(dxf)){
     var flags=ParseStoredViewportFlags(reader);
     say("PERSISTED VP FLAGS | "+Path.GetFileName(filename)+" | "+flags.Count);
     return flags;
    }
   }finally{if(File.Exists(dxf))File.Delete(dxf);}
  }
  static bool GetStoredViewportEnabled(Dictionary<string,StoredViewportFlags> flags,string handle){
   if(!flags.TryGetValue(handle,out var f))throw new System.Exception("Persisted viewport flags missing: "+handle);
   return f.Enabled;
  }
  static void CheckPersistedViewportFlagsParser(){
   // Both entities are inactive (status -1 or 0), but only the explicit
   // 0x20000 bit means disabled. Include a true disabled negative control.
   string sample="0\nVIEWPORT\n5\nAB\n100\nAcDbEntity\n100\nAcDbViewport\n68\n-1\n90\n32768\n0\nVIEWPORT\n5\nCD\n100\nAcDbEntity\n100\nAcDbViewport\n68\n0\n90\n163840\n0\nEOF\n";
   using(var reader=new StringReader(sample)){
    var f=ParseStoredViewportFlags(reader);
    if(f.Count!=2||!GetStoredViewportEnabled(f,"AB")||GetStoredViewportEnabled(f,"CD"))throw new System.Exception("Viewport persisted flag parser regression.");
   }
  }
'@
$m=One $m $anchor ($helper+[Environment]::NewLine+$anchor)
$m=One $m 'static void VerifyViewportSnapshots(Database db,List<ViewportSnapshot> expected,Action<string> say){
   using(var tr=db.TransactionManager.StartTransaction()){' @'
static void VerifyViewportSnapshots(Database db,List<ViewportSnapshot> expected,Action<string> say){
   if(expected.Count==0)return;
   var stored=ReadStoredViewportFlags(db,say);
   using(var tr=db.TransactionManager.StartTransaction()){
'@
$m=One $m 'snapshot.Assert(vp);' @'
      snapshot.Assert(vp,false);
      snapshot.AssertFrozen(vp);
      if(!stored.TryGetValue(snapshot.HandleText,out var flags))throw new System.Exception("Missing persisted viewport on reopen: "+snapshot.LayoutName+" | "+snapshot.HandleText);
      if(flags.Enabled!=snapshot.Enabled)throw new System.Exception("Persisted viewport OFF/ON mismatch: "+snapshot.LayoutName+" | "+snapshot.HandleText+" | flags="+flags.Flags+" | status="+flags.Status+" | expected="+snapshot.Enabled);
      say("VP PERSISTED ON OK "+group.Key+" | "+snapshot.HandleText+" | enabled="+flags.Enabled+" | flags="+flags.Flags+" | status="+flags.Status+" | transient On="+vp.On);
'@
$m=One $m 'if(mode=="B"||mode=="ALL")Merge(layoutTests.Take(1).ToList(),Path.Combine(folder,"Lsingle.dwg"),DwgVersion.AC1032,report);' 'if(mode=="B"||mode=="ALL"){CheckPersistedViewportFlagsParser();Merge(layoutTests.Take(1).ToList(),Path.Combine(folder,"Lsingle.dwg"),DwgVersion.AC1032,report);}'
Write-Source 'Cad\ModelMerge.cs' $m
Write-Host 'V2.6.7 Mode B: distinguish persisted DXF viewport visibility from editor-dependent On; retain active On, geometry, clipping, locked and frozen-layer verification.'
