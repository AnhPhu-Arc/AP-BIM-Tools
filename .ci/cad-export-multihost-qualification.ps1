# CAD Export multi-host compile qualification, not a release installer.
# Run after v268-build-qualification.ps1, which reconstructs the exact tested source.
# Outputs candidates and a truthful report; no unverified binary enters either MSI.
$ErrorActionPreference='Stop'
$root=(Get-Location).Path
$work=Join-Path $env:RUNNER_TEMP 'ap268-build'
$module=Join-Path $work 'CADExport'
$out=Join-Path $root 'output\compatibility'
New-Item -ItemType Directory -Force $out | Out-Null
$report=New-Object 'System.Collections.Generic.List[object]'
function Record($hostName,$runtime,$state,$detail){
 $report.Add([pscustomobject]@{Host=$hostName;Runtime=$runtime;Compile=$state;RuntimeTest='NOT TESTED';Detail=$detail})
 $report | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out 'compile-matrix.csv')
}
function Need($p){if(!(Test-Path -LiteralPath $p)){throw "Missing $p"};return (Resolve-Path -LiteralPath $p).Path}
function Build($project,$tfm,$dest,$props,$log){
 New-Item -ItemType Directory -Force $dest | Out-Null
 $args=@('build',$project,'-c','Release','-o',$dest,("-p:TargetFramework="+$tfm),'-p:DeployAddin=false','-p:LaunchRevit=false')+$props
 & dotnet @args 2>&1 | ForEach-Object {"$_"} | Tee-Object -FilePath $log | Out-Host
 if($LASTEXITCODE -ne 0){throw "dotnet build failed ($LASTEXITCODE); see $log"}
}
function FindDll($folder,$name){Get-ChildItem -LiteralPath $folder -Recurse -File -Filter $name | Sort-Object FullName | Select-Object -First 1}
$nuget=if($env:NUGET_PACKAGES){$env:NUGET_PACKAGES}else{Join-Path $env:USERPROFILE '.nuget\packages'}
# Existing full suite already restores the Nice3point Revit API per-year packages.
# Compile each baseline independently; updated 2025/26 runtime needs separate live testing.
Push-Location -LiteralPath (Need $module)
try{
 foreach($y in 2023..2027){
  $tfm=if($y -le 2024){'net48'}elseif($y -le 2026){'net8.0-windows'}else{'net10.0-windows'}
  try{
   $ref=Join-Path $work "revit-ref-$y"
   New-Item -ItemType Directory -Force $ref | Out-Null
   foreach($name in 'RevitAPI','RevitAPIUI'){
    $p=Need (Join-Path $nuget ('nice3point.revit.api.'+$name.ToLowerInvariant()))
    $versions=@(Get-ChildItem -LiteralPath $p -Directory | Where-Object {$_.Name -match ("^"+$y+"\." )} | Sort-Object {[version](($_.Name -split '-')[0])})
    if(!$versions.Count){throw "No $y API package: $name"}
    $selected=$versions[0]
    $f=FindDll $selected.FullName "$name.dll"
    if(!$f){throw "API reference missing: $name"}
    Copy-Item -LiteralPath $f.FullName -Destination $ref -Force
   }
   $dest=Join-Path $out "Revit\$y"
   Build 'Revit\Revit.csproj' $tfm $dest @("-p:RevitPath=$ref") (Join-Path $out "Revit-$y.log")
   [void](Need (Join-Path $dest 'CadSheetExport.Revit.dll'))
   if(@(Get-ChildItem -LiteralPath $dest -Recurse -File | Where-Object {$_.Name -match '^RevitAPI(UI)?\.dll$'}).Count){throw 'Autodesk API copied into candidate output'}
   Record "Revit $y" $tfm 'PASS' 'Compile candidate only; startup and DWG export not exercised'
  }catch{Record "Revit $y" $tfm 'FAIL' $_.Exception.Message}
 }
 # Autodesk documents compatibility of 2021 managed API binaries through 2024.
 # The 2021 worker already compiled in v268; never relabel later hosts as runtime tested.
 foreach($y in 2021..2024){Record "AutoCAD $y" 'net48 / R24.x' 'BASELINE 2021' '2021 binary candidate; per-host bundle and runtime tests required'}
 # Pin SDK package sets to the documented runtime split.
 # AutoCAD 2025 package versions differ between desktop and Core/Model.
 $targets=@(
  @{Host='2025';Runtime='net8.0-windows';Desktop='25.0.1';Core='25.0.0';Model='25.0.0'},
  @{Host='2026-net8';Runtime='net8.0-windows';Desktop='25.1.0';Core='25.1.0';Model='25.1.0'},
  @{Host='2026-net10';Runtime='net10.0-windows';Desktop='25.1.1';Core='25.1.1';Model='25.1.1'},
  @{Host='2027';Runtime='net10.0-windows';Desktop='26.0.0';Core='26.0.0';Model='26.0.0'}
 )
 foreach($t in $targets){
  try{
   $ref=Join-Path $work ("cad-ref-"+$t.Host)
   New-Item -ItemType Directory -Force $ref | Out-Null
   foreach($pair in @(@('autocad.net',$t.Desktop),@('autocad.net.core',$t.Core),@('autocad.net.model',$t.Model))){
    $pkg=$pair[0];$ver=$pair[1];$zip=Join-Path $work "$pkg.$ver.zip";$dir=Join-Path $work "$pkg.$ver"
    Invoke-WebRequest -UseBasicParsing -Uri "https://api.nuget.org/v3-flatcontainer/$pkg/$ver/$pkg.$ver.nupkg" -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
    foreach($name in 'acmgd.dll','accoremgd.dll','acdbmgd.dll'){
     $f=FindDll $dir $name;if($f){Copy-Item -LiteralPath $f.FullName -Destination $ref -Force}
    }
   }
   foreach($name in 'acmgd.dll','accoremgd.dll','acdbmgd.dll'){[void](Need (Join-Path $ref $name))}
   # Compile-only probe against existing generated COM interfaces. Never publish
   # as a release: target-specific ObjectARX TLB validation remains mandatory.
   $sso=Need (Join-Path $work 'interop\CadSso.dll')
   foreach($p in @(@('Cad\Cad.csproj','Desktop','CadSheetExport.AutoCAD.dll'),@('Core\Core.csproj','Headless','CadSheetExport.HeadlessEngine.dll'),@('CoreLoader\CoreLoader.csproj','Loader','CadSheetExport.HeadlessLoader.dll'))){
    $dest=Join-Path $out ("CAD\"+$t.Host+"\"+$p[1])
    Build $p[0] $t.Runtime $dest @("-p:CadPath=$ref","-p:SsoPath=$sso") (Join-Path $out ("CAD-"+$t.Host+"-"+$p[1]+".log"))
    [void](Need (Join-Path $dest $p[2]))
    if(@(Get-ChildItem -LiteralPath $dest -Recurse -File|Where-Object {$_.Name -match '^(acmgd|accoremgd|acdbmgd|AcSmComponents)\.dll$'}).Count){throw 'Autodesk API copied into candidate output'}
   }
   Record ("AutoCAD "+$t.Host) $t.Runtime 'PASS PROBE' 'Compile only with baseline COM interfaces; target ObjectARX SSO/ActiveX and runtime qualification required'
  }catch{Record ("AutoCAD "+$t.Host) $t.Runtime 'FAIL' $_.Exception.Message}
 }
}finally{Pop-Location}
$report | Format-Table -AutoSize | Out-Host
$report | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out 'compile-matrix.csv')
# Do not publish candidate DLLs, which may include third-party reference dependencies.
# Keep compile reports and logs only.
foreach($p in 'Revit','CAD'){Remove-Item (Join-Path $out $p) -Recurse -Force -ErrorAction SilentlyContinue}
if(@($report|Where-Object {$_.Compile -eq 'FAIL'}).Count){throw 'One or more target compiles failed. See compatibility logs. Existing installers remain baseline-only.'}
