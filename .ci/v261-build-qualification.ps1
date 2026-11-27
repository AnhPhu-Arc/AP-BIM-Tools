# AP-BIM Tools unified Windows CI, build candidate 2.6.1 / Revit 2023-27 / CAD 2021.
# Only AP-owned sources and generated interop enter the installer. SDK references remain transient.
$ErrorActionPreference='Stop'
$root=(Get-Location).Path
$utf8=New-Object System.Text.UTF8Encoding($true,$true)
function Run([string]$exe,[string[]]$argList){ & $exe @argList; if($LASTEXITCODE -ne 0){throw "Command failed ($LASTEXITCODE): $exe $($argList -join ' ')"}}
function Need([string]$p){if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing file: $p"};return (Resolve-Path -LiteralPath $p).ProviderPath}
function Copy-Binaries([string]$src,[string]$dst){
 New-Item -ItemType Directory -Path $dst -Force | Out-Null
 $files=@(Get-ChildItem -LiteralPath $src -File | Where-Object {$_.Extension -in '.dll','.json','.config'})
 if(!$files.Count){throw "Empty binary output: $src"}
 foreach($f in $files){if($f.Name -match '^(RevitAPI(UI)?|acmgd|acdbmgd|accoremgd|AcSmComponents)\.dll$'){throw "Vendor API copied unexpectedly: $($f.Name)"};Copy-Item -LiteralPath $f.FullName -Destination $dst -Force}
}
function Find-Ref([string]$dir,[string]$name){
 return (Get-ChildItem -LiteralPath $dir -Filter $name -Recurse -File -ErrorAction SilentlyContinue|Sort-Object FullName|Select-Object -First 1)
}
$work=Join-Path $env:RUNNER_TEMP 'ap261-build'
New-Item -ItemType Directory $work -Force | Out-Null
$archive=Join-Path $work 'cad-source.tar.xz'
$stream=[IO.File]::Create($archive)
try{foreach($i in 0..7){$part=Need (Join-Path $root ('.ci\cad-source\part{0:D2}.bin' -f $i));$bytes=[IO.File]::ReadAllBytes($part);$stream.Write($bytes,0,$bytes.Length)}}finally{$stream.Dispose()}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine '81e41ddf6d2dc63135ccfb88531ba670e3a51dc3b2fa378629f8ab444f7d6550'){throw 'CAD source archive SHA256 mismatch'}
Run 'tar' @('-xf',$archive,'-C',$work)
$module=Join-Path $work 'CADExport'
& (Join-Path $root '.ci\v24-worker-launch-fix.ps1') -CadExportRoot $module
& (Join-Path $root '.ci\v243-export-fix.ps1') -CadExportRoot $module
& (Join-Path $root '.ci\v244-isolated-model.ps1') -CadExportRoot $module
$command=Need (Join-Path $module 'Revit\Command.cs')
$t=[IO.File]::ReadAllText($command,$utf8)
$t=$t.Replace('V2.4.0 | CAD EXPORT 1.3.1','V2.6.1 | GEOMETRY QUALIFICATION')
# Keep a record of the first worker launch and permit explicit, safe fallback on early failure only.
$t=$t.Replace('File.WriteAllText(launchLog,DateTime.Now.ToString("o")','File.AppendAllText(launchLog,DateTime.Now.ToString("o")')
$old='string outcome=File.Exists(state)?File.ReadAllText(state):"FAILED | CAD worker không trả kết quả.";return outcome.StartsWith'
$new='string outcome=File.Exists(state)?File.ReadAllText(state):"FAILED | CAD worker không trả kết quả.";if(silent&&!Job.Read(job).Model&&outcome=="LAUNCHED"&&System.Diagnostics.Process.GetProcessesByName("acad").Length==0){var output=Job.Read(job).Output;if(Directory.Exists(output)){File.AppendAllText(launchLog,"Core startup failed; retrying desktop worker once."+Environment.NewLine);return Launch(exe,year,job,seed,false,pulse);}}return outcome.StartsWith'
if(!$t.Contains($old)){throw 'Unexpected launch fallback insertion point'}
$t=$t.Replace($old,$new)
[IO.File]::WriteAllText($command,$t,$utf8)
& (Join-Path $root '.ci\v250-desktop-first.ps1') -CadExportRoot $module
& (Join-Path $root '.ci\v251-headless-layout.ps1') -CadExportRoot $module
& (Join-Path $root '.ci\v260-headless-qualification.ps1') -CadExportRoot $module
& (Join-Path $root '.ci\v261-geometry-projection.ps1') -CadExportRoot $module

# The AP builds populate the official Revit reference packages used by Nice3point.
$nuget=if($env:NUGET_PACKAGES){$env:NUGET_PACKAGES}else{Join-Path $env:USERPROFILE '.nuget\packages'}
$rp=Join-Path $work 'revit-ref'
New-Item -ItemType Directory $rp -Force|Out-Null
foreach($n in 'RevitAPI','RevitAPIUI'){
 $p=Join-Path $nuget ('nice3point.revit.api.'+$n.ToLowerInvariant())
 $v=Get-ChildItem -LiteralPath $p -Directory | Where-Object {$_.Name -match '^2024\.'} | Sort-Object Name -Descending | Select-Object -First 1
 if(!$v){throw "Revit 2024 package missing: $p"}
 $f=Find-Ref $v.FullName "$n.dll";if(!$f){throw "Revit reference not found: $n"}
 Copy-Item -LiteralPath $f.FullName -Destination $rp
}
# Download Autodesk-owned NuGet packages for managed AutoCAD references; no redistribution.
$cp=Join-Path $work 'cad-ref';New-Item -ItemType Directory $cp -Force|Out-Null
foreach($pkg in 'autocad.net','autocad.net.core','autocad.net.model'){
 $zip=Join-Path $work "$pkg.zip";$dest=Join-Path $work $pkg
 Invoke-WebRequest -UseBasicParsing -Uri "https://api.nuget.org/v3-flatcontainer/$pkg/24.0.0/$pkg.24.0.0.nupkg" -OutFile $zip
 Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
 foreach($n in 'acmgd.dll','accoremgd.dll','acdbmgd.dll'){
  $f=Find-Ref $dest $n;if($f){Copy-Item -LiteralPath $f.FullName -Destination $cp -Force}
 }
}
foreach($n in 'acmgd.dll','accoremgd.dll','acdbmgd.dll'){[void](Need (Join-Path $cp $n))}
# SSO TLB is part of Autodesk ObjectARX. First try a data-only extraction.
$sdkDir=Join-Path $work 'ObjectARX';New-Item -ItemType Directory $sdkDir -Force|Out-Null
$sdk=Join-Path $work 'objectarx2021.exe'
Invoke-WebRequest -UseBasicParsing -Uri 'https://download.autodesk.com/esd/objectarx/2021/objectarx_for_autocad_2021_win_64bit_dlm.sfx.exe' -OutFile $sdk
& 7z.exe x -t7z -y ("-o"+$sdkDir) $sdk
$tlb=Find-Ref $sdkDir 'AcSmComponents24.tlb'
if(!$tlb){
 # Autodesk documents -suppresslaunch -d for extracting without launching installation.
 $sig=Get-AuthenticodeSignature -FilePath $sdk
 if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Autodesk'){throw "Cannot verify Autodesk SFX signature: $($sig.Status)"}
 $p=Start-Process -FilePath $sdk -ArgumentList @('-suppresslaunch','-d',('"' + $sdkDir + '"')) -PassThru
 if(!$p.WaitForExit(240000)){try{$p.Kill()}catch{};throw 'Autodesk SDK extraction timed out'}
 Write-Host "SDK extractor exit: $($p.ExitCode)"
 $tlb=Find-Ref $sdkDir 'AcSmComponents24.tlb'
 if(!$tlb -and (Test-Path 'C:\Autodesk')){$tlb=Find-Ref 'C:\Autodesk' 'AcSmComponents24.tlb'}
}
if(!$tlb){throw 'AcSmComponents24.tlb absent after official SDK extraction; cannot build DST functionality.'}
$tools=Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs\Windows'
$tlbimp=Get-ChildItem -LiteralPath $tools -Filter TlbImp.exe -Recurse -File|Where-Object {$_.DirectoryName -match '\\x64$'}|Sort-Object FullName -Descending|Select-Object -First 1
if(!$tlbimp){throw 'TlbImp x64 missing'}
# Resolve ObjectDBX/ActiveX references explicitly. On a clean runner these
# type libraries are not registered, so bare TlbImp silently loses members.
$interop=Join-Path $work 'interop'
New-Item -ItemType Directory $interop -Force | Out-Null
$axdb=Find-Ref $sdkDir 'axdb24enu.tlb'
$acax=Find-Ref $sdkDir 'acax24enu.tlb'
if(!$axdb -or !$acax){throw 'ObjectARX ActiveX dependencies axdb24enu.tlb / acax24enu.tlb not found'}
$dbx=Join-Path $interop 'AxDbInterop.dll'
$activex=Join-Path $interop 'AcadActiveXInterop.dll'
$sso=Join-Path $interop 'CadSso.dll'
Run $tlbimp.FullName @($axdb.FullName,("/out:"+$dbx),'/machine:X64')
Run $tlbimp.FullName @($acax.FullName,("/out:"+$activex),("/reference:"+$dbx),("/tlbreference:"+$axdb.FullName),'/machine:X64')
Run $tlbimp.FullName @($tlb.FullName,("/out:"+$sso),'/namespace:CadSso','/machine:X64',("/reference:"+$dbx),("/reference:"+$activex),("/tlbreference:"+$axdb.FullName),("/tlbreference:"+$acax.FullName))
foreach($file in @($dbx,$activex,$sso)){[void](Need $file)}
# Assert the imported API contains the actual method used for sheet import.
$loaded=@([Reflection.Assembly]::LoadFrom($dbx),[Reflection.Assembly]::LoadFrom($activex),[Reflection.Assembly]::LoadFrom($sso))
$type=$loaded[2].GetType('CadSso.AcSmAcDbLayoutReference',$true)
$types=@($type)+@($type.GetInterfaces())
if(!(@($types|ForEach-Object {$_.GetMethods()}|Where-Object {$_.Name -eq 'SetName'}).Count)){throw 'Incomplete COM import: SetName not available'}
Write-Host 'COM API check passed: AcSmAcDbLayoutReference.SetName'
# Compile all three CAD modules.
$revout=Join-Path $work 'Revit';$cadout=Join-Path $work 'Cad';$coreout=Join-Path $work 'Headless';$loaderout=Join-Path $work 'Loader'
Copy-Item -LiteralPath (Join-Path $root 'global.json') -Destination (Join-Path $module 'global.json') -Force
Push-Location -LiteralPath $module
try{
 Run 'dotnet' @('build','Revit\Revit.csproj','-c','Release','-o',$revout,'-p:TargetFramework=net48',("-p:RevitPath="+$rp))
 foreach($pair in @(@('Cad\Cad.csproj',$cadout),@('Core\Core.csproj',$coreout),@('CoreLoader\CoreLoader.csproj',$loaderout))){
  Run 'dotnet' @('build',$pair[0],'-c','Release','-o',$pair[1],'-p:TargetFramework=net48',("-p:CadPath="+$cp),("-p:SsoPath="+$sso))
 }
}finally{Pop-Location}
# Keep generated interop dependencies adjacent to both managed workers.
foreach($dest in @($cadout,$coreout)){
 foreach($ref in @($dbx,$activex)){Copy-Item -LiteralPath $ref -Destination $dest -Force}
}
foreach($f in @((Join-Path $revout 'CadSheetExport.Revit.dll'),(Join-Path $cadout 'CadSheetExport.AutoCAD.dll'),(Join-Path $cadout 'CadSso.dll'),(Join-Path $coreout 'CadSheetExport.HeadlessEngine.dll'),(Join-Path $loaderout 'CadSheetExport.HeadlessLoader.dll'),(Join-Path $coreout 'CadSso.dll'))){[void](Need $f)}
# The true headless modules must not directly reference the desktop API.
foreach($file in @((Join-Path $coreout 'CadSheetExport.HeadlessEngine.dll'),(Join-Path $loaderout 'CadSheetExport.HeadlessLoader.dll'))){
 $refs=[Reflection.Assembly]::ReflectionOnlyLoadFrom($file).GetReferencedAssemblies()
 if(@($refs|Where-Object {$_.Name -ieq 'acmgd'}).Count){throw "Headless module references AcMgd: $file"}
 if($file.EndsWith('HeadlessLoader.dll') -and @($refs|Where-Object {$_.Name -in 'CadSso','AxDbInterop','AcadActiveXInterop','CadSheetExport.HeadlessEngine'}).Count){throw 'Loader has unexpected eager dependency'}
 Write-Host ("HEADLESS REFERENCE PASS: "+[IO.Path]::GetFileName($file)+" | "+(($refs|ForEach-Object {$_.Name}) -join ', '))
}
$publish=@()
foreach($y in 2023..2027){
 $dir=Join-Path $root "source\AP.BimTools\bin\publish\$y"
 if(!(Test-Path -LiteralPath $dir -PathType Container)){throw "Missing publish folder: $dir"}
 $m=@(Get-ChildItem -LiteralPath $dir -Filter '*.addin' -File | Where-Object {(Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) -match 'AP\.BimTools\.Application'})
 if($m.Count -ne 1){throw "AP manifest missing or duplicated for Revit $y"}
 [xml]$xml=Get-Content -LiteralPath $m[0].FullName -Raw -Encoding UTF8
 $a=$xml.SelectSingleNode('/RevitAddIns/AddIn[FullClassName="AP.BimTools.Application"]/Assembly').InnerText
 if([IO.Path]::IsPathRooted($a)){throw "Nonportable manifest: $a"}
 [void](Need (Join-Path $dir $a))
 $publish+=$dir
}
$r24=Join-Path $root 'source\AP.BimTools\bin\publish\2024'
Copy-Binaries $revout (Join-Path $r24 'AP.CadExport')
$bundle=Join-Path $root '_cse_msi\ApplicationPlugins\CADSheetExport.2021.bundle'
Copy-Binaries $cadout (Join-Path $bundle 'Contents')
$headlessRoot=Join-Path $root '_cse_msi\HeadlessApp\AP.CSE.Headless.bundle'
Copy-Binaries $coreout (Join-Path $headlessRoot 'Contents')
Copy-Binaries $loaderout (Join-Path $headlessRoot 'Contents')
@"
<?xml version="1.0" encoding="utf-8"?>
<ApplicationPackage SchemaVersion="1.0" AppVersion="2.6.1" ProductCode="{2BE9143C-42C7-4D16-AB87-590DE4B52600}" Name="AP CAD Headless Qualification" Description="Headless runtime qualification only">
 <CompanyDetails Name="AP" />
 <Components>
  <RuntimeRequirements OS="Win64" SeriesMin="R24.0" SeriesMax="R24.0" />
  <ComponentEntry AppName="AP CSE Headless" ModuleName="./Contents/CadSheetExport.HeadlessLoader.dll" AppType=".Net" LoadOnCommandInvocation="True" LoadOnAutoCADStartup="False">
   <Commands GroupName="AP_CSE_HEADLESS"><Command Global="CSEHEADLESS" Local="CSEHEADLESS"/></Commands>
  </ComponentEntry>
 </Components>
</ApplicationPackage>
"@ | Set-Content -LiteralPath (Join-Path $headlessRoot 'PackageContents.xml') -Encoding UTF8

'2021'|Set-Content -LiteralPath (Join-Path $bundle 'host.txt') -Encoding UTF8
@"
<?xml version="1.0" encoding="utf-8"?>
<ApplicationPackage SchemaVersion="1.0" AutodeskProduct="AutoCAD" Name="AP-BIM CAD Export 2021" AppVersion="2.6.1" ProductCode="{$([guid]::NewGuid())}" Description="AP-BIM Tools DWG and Sheet Set processor">
 <CompanyDetails Name="AP" />
 <Components><RuntimeRequirements OS="Win64" Platform="AutoCAD*" SeriesMin="R24.0" SeriesMax="R24.0" />
 <ComponentEntry AppName="AP-BIM CAD Export" ModuleName="./Contents/CadSheetExport.AutoCAD.dll" AppType=".Net" LoadOnCommandInvocation="True" LoadOnAutoCADStartup="True">
 <Commands GroupName="CSE_COMMANDS"><Command Global="CSEPROCESS" Local="CSEPROCESS" /><Command Global="CSEHEALTH" Local="CSEHEALTH" /><Command Global="CSEAUTO" Local="CSEAUTO" /><Command Global="CSEPROBE" Local="CSEPROBE" /><Command Global="CSEOPENSET" Local="CSEOPENSET" /></Commands>
 </ComponentEntry></Components>
</ApplicationPackage>
"@ | Set-Content -LiteralPath (Join-Path $bundle 'PackageContents.xml') -Encoding UTF8
@'
<?xml version="1.0" encoding="utf-8"?>
<RevitAddIns><AddIn Type="Application"><Name>AP-BIM Tools CAD Export</Name><Assembly>AP.CadExport\CadSheetExport.Revit.dll</Assembly><AddInId>CB70258D-1DD7-4C5C-B6C3-689F3A63E235</AddInId><FullClassName>CadSheetExport.App</FullClassName><VendorId>CSEX</VendorId><VendorDescription>AP-BIM Tools CAD Export module</VendorDescription></AddIn></RevitAddIns>
'@ | Set-Content -LiteralPath (Join-Path $r24 'zzz.AP.BimTools.CadExport.addin') -Encoding UTF8
$installer=Need (Join-Path $root 'install\Installer.cs')
$txt=[IO.File]::ReadAllText($installer,$utf8)
if($txt -notmatch '39A83E67-0A17-48A0-B328-68386F8CE19B'){throw 'Upgrade identity mismatch'}
if(([regex]::Matches($txt,'project\.BuildMsi\(\);')).Count -ne 1){throw 'Installer pattern mismatch'}
$extra=@'
var cseFeature = new Feature { Name = "CAD Export worker", Description = "AutoCAD 2021 worker for AP-BIM CAD Export (Revit 2024)" };
var cseDirs = System.IO.Directory.GetDirectories(@"_cse_msi\ApplicationPlugins")
    .Select(p => new Dir(System.IO.Path.GetFileName(p), new Files(cseFeature, System.IO.Path.Combine(p, "*.*")))).ToArray();
var headlessDirs = System.IO.Directory.GetDirectories(@"_cse_msi\HeadlessApp")
    .Select(p => new Dir(System.IO.Path.GetFileName(p), new Files(cseFeature, System.IO.Path.Combine(p, "*.*")))).ToArray();
project.Dirs = project.Dirs.Concat(new[] { new Dir(@"%CommonAppDataFolder%\Autodesk\ApplicationPlugins", cseDirs), new Dir(@"%ProgramFiles%\AP-BIM Tools\CAD Engine\2021\HeadlessApp", headlessDirs) }).ToArray();
project.BuildMsi();
'@
[IO.File]::WriteAllText($installer,$txt.Replace('project.BuildMsi();',$extra),$utf8)
$wixDir=Join-Path $work 'wix'
Run 'dotnet' @('tool','install','wix','--version','7.0.1','--tool-path',$wixDir)
$wix=Need (Join-Path $wixDir 'wix.exe')
Run $wix @('eula','accept','wix7')
Run $wix @('extension','add','-g','WixToolset.UI.wixext/7.0.1')
$env:PATH="$wixDir;$env:PATH"
Run 'dotnet' (@('run','--project','.\install\Installer.csproj','--','2.6.1')+$publish)
$msi=Need (Join-Path $root 'output\AP-BIM-Tools-2.6.1.msi')
# Native read-only MSI API avoids the Windows Installer COM reflection mismatch.
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ApMsiRead {
 [DllImport("msi.dll",CharSet=CharSet.Unicode,EntryPoint="MsiOpenDatabaseW")] static extern uint Open(string path,IntPtr persist,out uint db);
 [DllImport("msi.dll",CharSet=CharSet.Unicode,EntryPoint="MsiDatabaseOpenViewW")] static extern uint OpenView(uint db,string sql,out uint view);
 [DllImport("msi.dll",EntryPoint="MsiViewExecute")] static extern uint Execute(uint view,uint record);
 [DllImport("msi.dll",EntryPoint="MsiViewFetch")] static extern uint Fetch(uint view,out uint rec);
 [DllImport("msi.dll",CharSet=CharSet.Unicode,EntryPoint="MsiRecordGetStringW")] static extern uint GetString(uint rec,uint col,StringBuilder value,ref uint length);
 [DllImport("msi.dll",EntryPoint="MsiCloseHandle")] static extern uint Close(uint handle);
 static void Check(uint status){if(status!=0)throw new InvalidOperationException("MSI API error "+status);}
 public static string[] Query(string path,string sql){
  uint db=0,view=0;var rows=new List<string>();
  try {Check(Open(path,IntPtr.Zero,out db));Check(OpenView(db,sql,out view));Check(Execute(view,0));
   while(true){uint rec=0;uint status=Fetch(view,out rec);if(status==259)break;Check(status);try{uint len=32768;var s=new StringBuilder((int)len);Check(GetString(rec,1,s,ref len));rows.Add(s.ToString());}finally{Close(rec);}}
  }finally{if(view!=0)Close(view);if(db!=0)Close(db);}
  return rows.ToArray();
 }
}
'@
$names=@([ApMsiRead]::Query($msi,'SELECT FileName FROM File')|ForEach-Object {($_ -split '\|')[-1]})
$expected=@{'AP.BimTools.dll'=5;'CadSheetExport.Revit.dll'=1;'zzz.AP.BimTools.CadExport.addin'=1;'CadSheetExport.AutoCAD.dll'=1;'CadSheetExport.HeadlessEngine.dll'=1;'CadSheetExport.HeadlessLoader.dll'=1;'CadSso.dll'=2;'AxDbInterop.dll'=2;'AcadActiveXInterop.dll'=2;'PackageContents.xml'=2}
foreach($n in $expected.Keys){$count=@($names|Where-Object {$_ -ieq $n}).Count;if($count -lt $expected[$n]){throw "MSI file table incomplete: $n ($count)"}}
if(@($names|Where-Object {$_ -match '^(RevitAPI(UI)?|acmgd|acdbmgd|accoremgd|AcSmComponents)\.dll$'}).Count){throw 'Vendor references unexpectedly packaged'}
$cabs=@([ApMsiRead]::Query($msi,'SELECT Cabinet FROM Media'))
if(!$cabs.Count -or @($cabs|Where-Object {!$_.StartsWith('#')}).Count){throw 'MSI is not self-contained'}
$version=@([ApMsiRead]::Query($msi,"SELECT Value FROM Property WHERE Property='ProductVersion'"))
if($version.Count -ne 1 -or $version[0] -ne '2.6.1'){throw 'Unexpected MSI product version'}
# Administrative extraction confirms the cabinet can actually be unpacked without installing.
$extract=Join-Path $work 'msi-admin-extract';New-Item -ItemType Directory $extract -Force|Out-Null
$msiexec=Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/a',('"'+$msi+'"'),'/qn',('TARGETDIR="'+$extract+'"'),'/norestart') -Wait -PassThru
if($msiexec.ExitCode -ne 0){throw "MSI administrative extraction failed: $($msiexec.ExitCode)"}
$payload=Get-ChildItem -LiteralPath $extract -Recurse -File
if(@($payload|Where-Object {$_.Name -ieq 'CadSheetExport.AutoCAD.dll'}).Count -lt 1){throw 'Missing extracted desktop worker'}
if(@($payload|Where-Object {$_.Name -ieq 'CadSheetExport.Core.dll'}).Count){throw 'Unexpected obsolete Core worker'}
foreach($n in 'CadSheetExport.HeadlessLoader.dll','CadSheetExport.HeadlessEngine.dll'){if(@($payload|Where-Object {$_.Name -ieq $n}).Count -ne 1){throw "Headless payload missing: $n"}}
$hash=(Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  AP-BIM-Tools-2.6.1.msi"|Set-Content -LiteralPath (Join-Path $root 'output\SHA256.txt') -Encoding ASCII
Write-Host "MSI PASS: $msi | SHA256=$hash"
'Build and MSI payload verified. Runtime Revit/AutoCAD test is still required; initial worker target AutoCAD 2021.'|Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8
