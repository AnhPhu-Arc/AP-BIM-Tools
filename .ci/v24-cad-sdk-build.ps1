param([string]$CadYear='2021',[string]$CadRuntime='Auto',[string]$RevitDir='', [string]$CadDir='', [string]$SsoTlb='', [switch]$BuildOnly)
$ErrorActionPreference='Stop'
if(!$BuildOnly -or $CadYear -ne '2021'){throw 'Hosted CI first target is AutoCAD 2021; no other host claimed.'}
function Run([string]$exe,[string[]]$arguments){& $exe @arguments;if($LASTEXITCODE -ne 0){throw "$exe failed: $LASTEXITCODE"}}
function Find-One([string]$root,[string]$file){
 $f=@(Get-ChildItem -LiteralPath $root -Filter $file -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
 if(!$f.Count){throw "Missing $file in $root"}
 return $f[0].FullName
}
$root=$PSScriptRoot
$work=Join-Path $root ('.build\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work -Force | Out-Null
$refs=New-Item -ItemType Directory (Join-Path $work 'RevitRefs') -Force
$nuget=if($env:NUGET_PACKAGES){$env:NUGET_PACKAGES}else{Join-Path $env:USERPROFILE '.nuget\packages'}
foreach($n in @('RevitAPI','RevitAPIUI')){
 $pkg=Join-Path $nuget ('nice3point.revit.api.'+$n.ToLowerInvariant())
 $version=@(Get-ChildItem -LiteralPath $pkg -Directory | Where-Object {$_.Name -match '^2024\.'} | Sort-Object Name -Descending)
 if(!$version.Count){throw "No 2024 package in $pkg"}
 Copy-Item -LiteralPath (Find-One $version[0].FullName "$n.dll") -Destination $refs.FullName
}
# The Autodesk ObjectARX SDK provides build-time reference assemblies and COM type libraries.
# Do not redistribute Autodesk managed reference assemblies in the MSI.
$sdkDir=Join-Path $work 'ObjectARX'
New-Item -ItemType Directory $sdkDir -Force|Out-Null
$sdkExe=Join-Path $work 'objectarx2021.exe'
Invoke-WebRequest -Uri 'https://download.autodesk.com/esd/objectarx/2021/objectarx_for_autocad_2021_win_64bit_dlm.sfx.exe' -OutFile $sdkExe -UseBasicParsing
$seven=(Get-Command 7z.exe -ErrorAction Stop).Source
Run $seven @('x','-y',("-o"+$sdkDir),$sdkExe)
$cadRefs=New-Item -ItemType Directory (Join-Path $work 'CadRefs') -Force
foreach($n in 'acmgd.dll','acdbmgd.dll','accoremgd.dll'){
 Copy-Item -LiteralPath (Find-One $sdkDir $n) -Destination $cadRefs.FullName
}
$tlb=Find-One $sdkDir 'AcSmComponents24.tlb'
$tools=@(Get-ChildItem -Path (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs\Windows') -Filter TlbImp.exe -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.DirectoryName -match '\\x64$'} | Sort-Object FullName -Descending)
if(!$tools.Count){throw 'TlbImp x64 not found on runner'}
$sso=Join-Path $work 'CadSso.dll'
Run $tools[0].FullName @($tlb,("/out:"+$sso),'/namespace:CadSso','/machine:X64')
$revout=Join-Path $work 'Revit';$cadout=Join-Path $work 'Cad';$coreout=Join-Path $work 'Core'
Run dotnet @('build',(Join-Path $root 'Revit\Revit.csproj'),'-c','Release','-o',$revout,'-p:TargetFramework=net48',("-p:RevitPath="+$refs.FullName))
foreach($pair in @(@('Cad\Cad.csproj',$cadout),@('Core\Core.csproj',$coreout))){
 Run dotnet @('build',(Join-Path $root $pair[0]),'-c','Release','-o',$pair[1],'-p:TargetFramework=net48',("-p:CadPath="+$cadRefs.FullName),("-p:SsoPath="+$sso))
}
[pscustomobject]@{Year='2021';Series='R24.0';Framework='net48';AcadExe='C:\Program Files\Autodesk\AutoCAD 2021\acad.exe';RevitOutput=$revout;CadOutput=$cadout;CoreOutput=$coreout}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $work 'build-info.json') -Encoding UTF8
