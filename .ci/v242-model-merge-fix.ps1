# Mode C: preserve diagnostic evidence, run EXPORTLAYOUT to completion, and identify the failing stage.
param([Parameter(Mandatory=$true)][string]$CadExportRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Replace-One([string]$s,[string]$a,[string]$b){
 if(([regex]::Matches($s,[regex]::Escape($a))).Count -ne 1){throw "Mode C patch source mismatch: $a"}
 return $s.Replace($a,$b)
}
$model=(Resolve-Path -LiteralPath (Join-Path $CadExportRoot 'Cad\ModelMerge.cs')).ProviderPath
$m=[IO.File]::ReadAllText($model,$utf8)
$start=$m.IndexOf('static async Task MergeModel(')
$end=$m.IndexOf('   using(var target=new Database(true,true))',$start)
if($start -lt 0 -or $end -lt 0){throw 'Mode C method boundary not found'}
$prefix=@'
static async Task MergeModel(List<SheetItem> sheets,string path,DwgVersion version,int columns,double gap,string work,Action<string> say)
  {
   if(columns<1||gap<0)throw new System.Exception("Invalid model grid");
   var docs=Acad.DocumentManager;
   var previous=docs.MdiActiveDocument;
   var flats=new List<string>();
   string root=Path.GetDirectoryName(path);
   bool completed=false;
   string stage="START";
   try {
    for(int i=0;i<sheets.Count;i++){
     var s=sheets[i];
     stage="EXPORTLAYOUT "+s.Number+" ["+s.Layout+"]";
     // Keep the same output directory while flattening, so relative Links remain resolvable.
     string flat=Path.Combine(root,"_CSE_FLAT_"+Guid.NewGuid().ToString("N")+".dwg");
     flats.Add(flat);
     say(stage+" | Source="+s.FinalDwg+" | Target="+flat);
     var d=docs.Open(s.FinalDwg,false);
     try{
      docs.MdiActiveDocument=d;
      System.Exception failure=null;
      await docs.ExecuteInCommandContextAsync(async _=>{
       object filedia=null,cmddia=null;
       try{
        if(docs.MdiActiveDocument!=d)throw new System.InvalidOperationException("EXPORTLAYOUT document is not active");
        filedia=Acad.GetSystemVariable("FILEDIA");
        cmddia=Acad.GetSystemVariable("CMDDIA");
        Acad.SetSystemVariable("FILEDIA",0);
        Acad.SetSystemVariable("CMDDIA",0);
        Acad.SetSystemVariable("CTAB",s.Layout);
        if(Convert.ToInt32(Acad.GetSystemVariable("CVPORT"))>1)d.Editor.SwitchToPaperSpace();
        if(!string.Equals(Convert.ToString(Acad.GetSystemVariable("CTAB")),s.Layout,StringComparison.OrdinalIgnoreCase))
         throw new System.InvalidOperationException("Cannot activate requested paper layout");
        say(stage+" | CTAB="+Acad.GetSystemVariable("CTAB")+" | CVPORT="+Acad.GetSystemVariable("CVPORT")+" | CMDNAMES="+Acad.GetSystemVariable("CMDNAMES"));
        // Await the actual native command; do not advance to cloning while export is pending.
        await d.Editor.CommandAsync("_.EXPORTLAYOUT",flat);
        say(stage+" | CommandAsync returned | CMDNAMES="+Acad.GetSystemVariable("CMDNAMES"));
       }catch(System.Exception e){failure=e;}
       finally{
        try{if(filedia!=null)Acad.SetSystemVariable("FILEDIA",filedia);}catch(System.Exception e){say("FILEDIA restore warning: "+e.Message);}
        try{if(cmddia!=null)Acad.SetSystemVariable("CMDDIA",cmddia);}catch(System.Exception e){say("CMDDIA restore warning: "+e.Message);}
       }
      },null);
      if(failure!=null)throw new System.Exception(stage+" failed: "+failure.Message,failure);
      if(!File.Exists(flat)||new FileInfo(flat).Length==0)throw new System.Exception(stage+" did not produce a DWG");
      using(var checkFlat=Open(flat))using(var trFlat=checkFlat.TransactionManager.StartTransaction()){
       var btFlat=(BlockTable)trFlat.GetObject(checkFlat.BlockTableId,OpenMode.ForRead);
       var msFlat=(BlockTableRecord)trFlat.GetObject(btFlat[BlockTableRecord.ModelSpace],OpenMode.ForRead);
       if(!msFlat.Cast<ObjectId>().Any())throw new System.Exception(stage+" produced an empty Model Space");
      }
      say("FLAT OK "+s.Number+" | bytes="+new FileInfo(flat).Length);
     }finally{
      try{d.CloseAndDiscard();}
      finally{if(previous!=null)docs.MdiActiveDocument=previous;}
     }
    }
    stage="CLONE flattened models";
'@
$m=$m.Substring(0,$start)+$prefix+[Environment]::NewLine+$m.Substring($end)
$m=Replace-One $m 'for(int i=0;i<flats.Count;i++){using(var src=Open(flats[i]))' 'for(int i=0;i<flats.Count;i++){stage="CLONE "+sheets[i].Number;say(stage);using(var src=Open(flats[i]))'
$m=Replace-One $m 'InDb(target,()=>LayoutManager.Current.CurrentLayout="Model");target.SaveAs(path,version);' 'stage="SAVE merged Model";say(stage);InDb(target,()=>LayoutManager.Current.CurrentLayout="Model");target.SaveAs(path,version);'
$m=Replace-One $m 'using(var check=Open(path))using(var tr=check.TransactionManager.StartTransaction())' 'stage="VERIFY merged Model";say(stage);using(var check=Open(path))using(var tr=check.TransactionManager.StartTransaction())'
$old='}catch{if(File.Exists(path))File.Delete(path);throw;}finally{foreach(var f in flats)try{if(File.Exists(f))File.Delete(f);}catch{}}}'
$new=@'
    completed=true;
   }catch(System.Exception ex){
    say("MODEL MERGE FAILED AT "+stage+" | "+ex);
    if(File.Exists(path))try{File.Delete(path);}catch(System.Exception cleanup){say("CLEANUP WARNING "+cleanup.Message);}
    throw new System.Exception(stage+": "+ex.Message,ex);
   }finally{
    // Preserve successfully generated intermediates for diagnostics without polluting the deliverable folder.
    foreach(var f in flats)try{
     if(!File.Exists(f))continue;
     if(!completed){
      string recover=Path.Combine(work,"model_recovery");
      Directory.CreateDirectory(recover);
      File.Copy(f,Path.Combine(recover,Path.GetFileName(f)),false);
     }
     File.Delete(f);
    }catch(System.Exception cleanup){say("FLAT recovery warning: "+cleanup.Message);}
   }
  }
'@
$m=Replace-One $m $old $new
[IO.File]::WriteAllText($model,$m,$utf8)
$processor=(Resolve-Path -LiteralPath (Join-Path $CadExportRoot 'Cad\Processor.cs')).ProviderPath
$p=[IO.File]::ReadAllText($processor,$utf8)
$p=Replace-One $p 'Say("MERGE ERROR: "+ex+" | dùng DWG riêng.");' 'File.WriteAllText(Path.Combine(work,"merge_error.txt"),ex.ToString());Say("MERGE ERROR: "+ex+" | dùng DWG riêng.");'
$p=Replace-One $p 'Say(result);File.WriteAllText(Path.Combine(work,"state.txt"),result);' 'if(!combined&&(j.Combine||j.Model)&&File.Exists(Path.Combine(work,"merge_error.txt"))){var detail=File.ReadAllText(Path.Combine(work,"merge_error.txt"));var first=detail.Split(new[]{''\r'',''\n''},StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();if(!string.IsNullOrEmpty(first))result+=" | "+first;}Say(result);File.WriteAllText(Path.Combine(work,"state.txt"),result);'
[IO.File]::WriteAllText($processor,$p,$utf8)
Write-Host 'Mode C: awaited EXPORTLAYOUT, stage diagnostics and recovery enabled.'
