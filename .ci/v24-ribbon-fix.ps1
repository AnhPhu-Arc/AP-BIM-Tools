[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('BeforeLegacyScripts','AfterPayloadExtract','Finalize')][string]$Phase)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($true,$true)
function Normalize-Utf8([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $text = [IO.File]::ReadAllText($full,$utf8)
    [IO.File]::WriteAllText($full,$text,$utf8)
}
if($Phase -ne 'Finalize') {
    foreach($folder in '.\source','.\.ci') {
        Get-ChildItem -LiteralPath $folder -Recurse -File |
            Where-Object { $_.Extension -in '.cs','.ps1','.xaml','.resx' } |
            ForEach-Object { Normalize-Utf8 $_.FullName }
    }
    Write-Host "UTF8 BOM normalization complete: $Phase"
    return
}
Add-Type -AssemblyName System.Drawing
$dir=(Resolve-Path -LiteralPath '.\source\AP.BimTools').ProviderPath
$app=Join-Path $dir 'Application.cs'
$proj=Join-Path $dir 'AP.BimTools.csproj'
$src=[IO.File]::ReadAllText($app,$utf8)
# Do not try to salvage corrupted source. Reconstruct from original UTF8 bytes.
if($src -notmatch 'Th\u00e9p d\u1ea7m' -or $src -match 'Th\u00c3\u00a9p') {
    throw 'Ribbon text is not intact; run BeforeLegacyScripts BEFORE the v22 menu script.'
}
if($src -notmatch 'AddWithIcon<') { throw 'Existing icon helper not found.' }
if([IO.File]::ReadAllText($proj,$utf8) -notmatch '<Resource\s+Include="Icon\*\.png"') {
    throw 'Icon resource wildcard is missing.'
}
$rx=[regex]'(?m)^([ \t]*)Add<([A-Za-z_][A-Za-z0-9_]*)>\((.*)\);[ \t]*\r?$'
$matches=$rx.Matches($src)
if($matches.Count -lt 30){throw "Unexpected number of legacy buttons: $($matches.Count)"}
$names=@($matches|ForEach-Object {$_.Groups[2].Value}|Sort-Object -Unique)
function New-CommandIcon([string]$name,[int]$size) {
    $bmp=New-Object Drawing.Bitmap($size,$size)
    $g=[Drawing.Graphics]::FromImage($bmp)
    $blue=New-Object Drawing.Pen([Drawing.Color]::FromArgb(255,71,145,219),2.0)
    $light=New-Object Drawing.Pen([Drawing.Color]::FromArgb(255,216,230,242),1.7)
    $accent=New-Object Drawing.Pen([Drawing.Color]::FromArgb(255,245,170,70),2.1)
    $fill=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255,46,89,135))
    $badge=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255,29,55,83))
    try {
        $g.Clear([Drawing.Color]::Transparent)
        $g.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.ScaleTransform([single]($size/32.0),[single]($size/32.0))
        switch -Regex ($name) {
            'Door' { $g.FillRectangle($fill,7,3,16,25);$g.DrawRectangle($light,7,3,16,25);$g.DrawLine($blue,9,5,19,9);$g.DrawLine($blue,19,9,19,25);$g.DrawEllipse($accent,15,15,2,2);break }
            'Window' { $g.FillRectangle($fill,4,5,24,20);$g.DrawRectangle($light,4,5,24,20);$g.DrawLine($light,16,5,16,25);$g.DrawLine($light,4,15,28,15);break }
            'Floor|Ceiling' { $p=[Drawing.PointF[]]@((New-Object Drawing.PointF(3,12)),(New-Object Drawing.PointF(21,5)),(New-Object Drawing.PointF(29,12)),(New-Object Drawing.PointF(11,20)));$g.FillPolygon($fill,$p);$g.DrawPolygon($light,$p);if($name -match 'Ceiling'){$g.DrawLine($accent,9,27,9,20)}else{$g.DrawLine($accent,9,21,9,27)};break }
            'Wall|Beam|Column|Framing|Foundation' { $g.FillRectangle($fill,5,8,22,14);$g.DrawRectangle($light,5,8,22,14);$g.DrawLine($blue,12,8,12,22);$g.DrawLine($blue,20,8,20,22);break }
            'Room|Space' { $g.FillRectangle($fill,4,4,24,24);$g.DrawLine($light,4,4,28,4);$g.DrawLine($light,28,4,28,28);$g.DrawLine($light,4,4,4,28);$g.DrawLine($light,4,28,13,28);$g.DrawLine($light,22,28,28,28);break }
            'CableTray' { $g.DrawLine($light,4,8,28,8);$g.DrawLine($light,4,24,28,24);foreach($x in 6,12,18,24){$g.DrawLine($blue,$x,8,$x,24)};break }
            'Pipe|Conduit|Duct|Connector|Connect|Fitting' { $g.DrawLine($blue,3,15,14,15);$g.DrawLine($blue,18,15,29,15);$g.DrawRectangle($light,12,10,8,10);$g.DrawLine($light,4,12,4,18);$g.DrawLine($light,28,12,28,18);break }
            'Offset|Coordinate' { $g.DrawLine($light,6,26,6,4);$g.DrawLine($light,6,26,28,26);$g.DrawLine($accent,6,26,23,9);$g.DrawLine($accent,23,9,23,16);$g.DrawLine($accent,23,9,16,9);break }
            'Link' { $g.DrawEllipse($light,3,9,16,11);$g.DrawEllipse($blue,13,12,16,11);break }
            'CAD|Sheet|View|Report|Export' { $g.FillRectangle($fill,6,3,20,26);$g.DrawRectangle($light,6,3,20,26);foreach($y in 9,14,19){$g.DrawLine($blue,10,$y,22,$y)};break }
            'Pin' { $g.FillRectangle($fill,10,4,12,12);$g.DrawRectangle($light,10,4,12,12);$g.DrawLine($light,5,17,27,17);$g.DrawLine($accent,16,17,16,28);break }
            'Isolate|Reset|Select|Category|Type' { $g.DrawRectangle($blue,5,5,22,22);$g.DrawRectangle($light,10,10,12,12);break }
            'Clash' { $g.DrawRectangle($light,3,5,17,17);$g.DrawRectangle($accent,12,12,17,17);break }
            'Audit|Health|Warning|Purge|About' { $g.DrawEllipse($blue,4,4,24,24);$g.DrawLine($light,16,8,16,18);$g.DrawEllipse($light,15,22,2,2);break }
            default { $g.DrawRectangle($light,5,5,22,22);$g.DrawLine($blue,8,16,24,16);$g.DrawLine($blue,16,8,16,24);break }
        }
        # Action marker distinguishes commands sharing an element type.
        $g.FillEllipse($badge,18,18,14,14)
        switch -Regex ($name) {
            'Renumber|Number|Prefix' {$g.DrawLine($accent,22,21,22,28);$g.DrawLine($accent,25,21,25,28);$g.DrawLine($accent,20,23,29,23);$g.DrawLine($accent,20,26,29,26);break}
            'Disallow|Unpin|Purge|Reset' {$g.DrawLine($accent,21,25,29,25);break}
            'Allow|Create|Pin' {$g.DrawLine($accent,21,25,29,25);$g.DrawLine($accent,25,21,25,29);break}
            'Export|Report' {$g.DrawLine($accent,20,25,29,25);$g.DrawLine($accent,29,25,25,21);$g.DrawLine($accent,29,25,25,29);break}
            'Flip|Offset' {$g.DrawLine($accent,21,22,29,22);$g.DrawLine($accent,29,22,26,25);$g.DrawLine($accent,29,28,21,28);$g.DrawLine($accent,21,28,24,25);break}
            'Audit|Health|Warning|Clash' {$g.DrawLine($accent,21,25,24,28);$g.DrawLine($accent,24,28,29,21);break}
            default {$g.DrawRectangle($accent,21,21,8,8);break}
        }
        $bmp.Save((Join-Path $dir ("Icon{0}{1}.png" -f $name,$size)),[Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $badge.Dispose();$fill.Dispose();$accent.Dispose();$light.Dispose();$blue.Dispose();$g.Dispose();$bmp.Dispose()
    }
}
foreach($name in $names){foreach($size in 16,32){New-CommandIcon $name $size}}
$src=$rx.Replace($src,[System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    $indent=$m.Groups[1].Value
    $name=$m.Groups[2].Value
    $argsText=$m.Groups[3].Value
    return ('{0}AddWithIcon<{1}>({2}, "{1}");' -f $indent,$name,$argsText)
})
if($rx.IsMatch($src)){throw 'A legacy AP logo button remains.'}
[IO.File]::WriteAllText($app,$src,$utf8)
Write-Host "Ribbon source updated: $($names.Count) command-specific icon pairs. Compile and test before release."
