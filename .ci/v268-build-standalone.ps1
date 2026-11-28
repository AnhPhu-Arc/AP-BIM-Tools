# Build standalone edition from the exact V2.6.8 staging tree.
# Run AFTER v268-build-qualification.ps1 in the same Windows CI job.
$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
$version = '2.6.8'
$work = Join-Path $env:RUNNER_TEMP 'ap268-build'
$wix = Join-Path $work 'wix\wix.exe'
$rev = Join-Path $root 'source\AP.BimTools\bin\publish\2024'
$cad = Join-Path $root '_cse_msi\ApplicationPlugins\CADSheetExport.2021.bundle'
$head = Join-Path $root '_cse_msi\HeadlessApp\AP.CSE.Headless.bundle'
$manifest = Join-Path $rev 'zzz.AP.BimTools.CadExport.addin'
$module = Join-Path $work 'CADExport'
function Need($p) { if(!(Test-Path -LiteralPath $p)){throw "Missing: $p"} }
foreach($p in @($wix,$manifest,(Join-Path $rev 'AP.CadExport'),$cad,$head,$module)){Need $p}
[xml]$addin = Get-Content -LiteralPath $manifest -Raw
if($addin.RevitAddIns.AddIn.FullClassName -ne 'CadSheetExport.App' -or $addin.RevitAddIns.AddIn.Assembly -ne 'AP.CadExport\CadSheetExport.Revit.dll'){throw 'Unexpected CAD Export manifest'}
# Assert independent ribbon initialization in CAD module (full AP DLL must not be required).
$appSource = @(Get-ChildItem (Join-Path $module 'Revit') -Recurse -Filter '*.cs' -File | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'CreateRibbonTab' -and (Get-Content -LiteralPath $_.FullName -Raw) -match 'AP-GEN' })
if(!$appSource.Count){throw 'Standalone ribbon initialization not verified: review CadSheetExport.App before shipping'}
$appSource | ForEach-Object {Write-Host "Ribbon source: $($_.FullName)"}
$refs=[Reflection.Assembly]::ReflectionOnlyLoadFrom((Join-Path $rev 'AP.CadExport\CadSheetExport.Revit.dll')).GetReferencedAssemblies()
if(@($refs|Where-Object {$_.Name -eq 'AP.BimTools'}).Count){throw 'CAD Export depends on full AP assembly'}
$ns='http://wixtoolset.org/schemas/v4/wxs'
$doc=New-Object System.Xml.XmlDocument
function Node($parent,[string]$name,[hashtable]$attrs) {
  $e=$doc.CreateElement($name,$ns)
  foreach($key in $attrs.Keys){$e.SetAttribute($key,[string]$attrs[$key])}
  [void]$parent.AppendChild($e)
  return ,$e
}
function Id([string]$prefix,[string]$key) {
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hex=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key.ToLowerInvariant())))).Replace('-','');return $prefix+$hex.Substring(0,30)}finally{$sha.Dispose()}
}
$script:expected=@()
$script:components=@()
$top=Node $doc 'Wix' @{}
# Shared product family with full MSI; standalone replaces a same-version full install.
# Switch editions only after closing Autodesk applications and uninstalling previous edition.
$pkg=Node $top 'Package' @{Name='AP CAD Export';Manufacturer='AP BIM Tools';Version=$version;UpgradeCode='39A83E67-0A17-48A0-B328-68386F8CE19B';Scope='perMachine'}
$null=Node $pkg 'MajorUpgrade' @{AllowSameVersionUpgrades='yes';Schedule='afterInstallInitialize';DowngradeErrorMessage='A newer AP BIM Tools edition is installed. Uninstall it before switching editions.'}
$null=Node $pkg 'MediaTemplate' @{EmbedCab='yes'}
function New-PayloadDir($parent,[string]$name,[string]$key){return ,(Node $parent 'Directory' @{Id=(Id 'D' $key);Name=$name})}
function PutFile($parent,[string]$source,[string]$key){
  $file=Get-Item -LiteralPath $source
  if($file.Name -match '^(AP\.BimTools|RevitAPI(UI)?|acmgd|acdbmgd|accoremgd|AcSmComponents)\.dll$'){throw "Disallowed standalone payload: $($file.Name)"}
  $cid=Id 'C' $key
  $component=Node $parent 'Component' @{Id=$cid;Guid='*';Bitness='always64'}
  $null=Node $component 'File' @{Id=(Id 'F' $key);Source=$file.FullName;Name=$file.Name;KeyPath='yes'}
  $script:components+= $cid
  $script:expected+= [pscustomobject]@{Name=$file.Name;Hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash;Path=$key}
}
function PutTree($parent,[string]$source,[string]$key){
  Need $source
  foreach($f in Get-ChildItem -LiteralPath $source -File){PutFile $parent $f.FullName ($key+'/'+$f.Name)}
  foreach($d in Get-ChildItem -LiteralPath $source -Directory){$k=$key+'/'+$d.Name;$child=New-PayloadDir $parent $d.Name $k;PutTree $child $d.FullName $k}
}
$common=Node $pkg 'StandardDirectory' @{Id='CommonAppDataFolder'}
$autodesk=New-PayloadDir $common 'Autodesk' 'ProgramData/Autodesk'
$revit=New-PayloadDir $autodesk 'Revit' 'ProgramData/Autodesk/Revit'
$addins=New-PayloadDir $revit 'Addins' 'ProgramData/Autodesk/Revit/Addins'
$r24=New-PayloadDir $addins '2024' 'ProgramData/Autodesk/Revit/Addins/2024'
PutFile $r24 $manifest 'ProgramData/Autodesk/Revit/Addins/2024/zzz.AP.BimTools.CadExport.addin'
$rKey='ProgramData/Autodesk/Revit/Addins/2024/AP.CadExport'
$rd=New-PayloadDir $r24 'AP.CadExport' $rKey
PutTree $rd (Join-Path $rev 'AP.CadExport') $rKey
$plugins=New-PayloadDir $autodesk 'ApplicationPlugins' 'ProgramData/Autodesk/ApplicationPlugins'
$cKey='ProgramData/Autodesk/ApplicationPlugins/CADSheetExport.2021.bundle'
$cd=New-PayloadDir $plugins 'CADSheetExport.2021.bundle' $cKey
PutTree $cd $cad $cKey
$pf=Node $pkg 'StandardDirectory' @{Id='ProgramFiles64Folder'}
$ap=New-PayloadDir $pf 'AP-BIM Tools' 'ProgramFiles/AP-BIM Tools'
$engine=New-PayloadDir $ap 'CAD Engine' 'ProgramFiles/AP-BIM Tools/CAD Engine'
$year=New-PayloadDir $engine '2021' 'ProgramFiles/AP-BIM Tools/CAD Engine/2021'
$ha=New-PayloadDir $year 'HeadlessApp' 'ProgramFiles/AP-BIM Tools/CAD Engine/2021/HeadlessApp'
$hKey='ProgramFiles/AP-BIM Tools/CAD Engine/2021/HeadlessApp/AP.CSE.Headless.bundle'
$hd=New-PayloadDir $ha 'AP.CSE.Headless.bundle' $hKey
PutTree $hd $head $hKey
$feature=Node $pkg 'Feature' @{Id='CadExportOnly';Title='CAD Export';Level='1'}
foreach($id in $script:components){$null=Node $feature 'ComponentRef' @{Id=$id}}
$wxs=Join-Path $work 'AP-CAD-Export-Standalone.wxs'
$doc.Save($wxs)
$out=Join-Path $root 'output\AP-CAD-Export-2.6.8-Standalone.msi'
& $wix build -arch x64 -o $out $wxs
if($LASTEXITCODE -ne 0){throw 'Standalone WiX build failed'}
Need $out
# Verify embedded cabinet contents through administrative extraction.
$extract=Join-Path $work 'standalone-admin-extract'
New-Item -ItemType Directory -Path $extract -Force|Out-Null
$p=Start-Process msiexec.exe -ArgumentList @('/a',('"'+$out+'"'),'/qn',('TARGETDIR="'+$extract+'"'),'/norestart') -PassThru -Wait
if($p.ExitCode -ne 0){throw "Standalone MSI extraction failed: $($p.ExitCode)"}
$actual=@(Get-ChildItem -LiteralPath $extract -Recurse -File|Where-Object {$_.Extension -ne '.msi'}|ForEach-Object {[pscustomobject]@{Name=$_.Name;Hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
$expectedKeys=@($script:expected|ForEach-Object {$_.Name+'|'+$_.Hash}|Sort-Object)
$actualKeys=@($actual|ForEach-Object {$_.Name+'|'+$_.Hash}|Sort-Object)
if(Compare-Object $expectedKeys $actualKeys){throw 'Standalone MSI payload differs from V2.6.8 staging files'}
if(@($actual|Where-Object {$_.Name -like '*.addin'}).Count -ne 1){throw 'Standalone must have exactly one Revit manifest'}
$script:expected|Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $root 'output\Standalone-Payload.csv')
$hash=(Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  AP-CAD-Export-2.6.8-Standalone.msi"|Set-Content -Encoding ASCII (Join-Path $root 'output\Standalone-SHA256.txt')
Write-Host "Standalone MSI payload PASS: $out"
'Standalone payload verified; live Revit 2024 / AutoCAD 2021 Ribbon, modes A/B/C, edition switching and uninstall still require testing.'|Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY
