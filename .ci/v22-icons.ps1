$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$dest = '.\\source\\AP.BimTools'

function New-Icon([string]$name, [int]$size, [scriptblock]$draw) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $dark = [System.Drawing.Color]::FromArgb(255,35,45,55)
    $red = [System.Drawing.Color]::FromArgb(255,215,55,55)
    $blue = [System.Drawing.Color]::FromArgb(255,55,110,170)
    $concrete = [System.Drawing.Color]::FromArgb(255,205,208,212)
    & $draw $g $size $dark $red $blue $concrete

    $path = Join-Path $dest ("Icon{0}{1}.png" -f $name,$size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function P([float]$v,[int]$s) { return [single]($v*$s/32.0) }

$beam = {
 param($g,$s,$dark,$red,$blue,$concrete)
 $penD=New-Object Drawing.Pen($dark,[Math]::Max(1,(P 1 $s))); $penR=New-Object Drawing.Pen($red,[Math]::Max(1,(P 1.5 $s))); $penB=New-Object Drawing.Pen($blue,[Math]::Max(1,(P 1 $s)))
 $brush=New-Object Drawing.SolidBrush($concrete)
 $g.FillRectangle($brush,(P 3 $s),(P 11 $s),(P 26 $s),(P 10 $s)); $g.DrawRectangle($penD,(P 3 $s),(P 11 $s),(P 26 $s),(P 10 $s))
 $g.DrawLine($penR,(P 5 $s),(P 13 $s),(P 27 $s),(P 13 $s)); $g.DrawLine($penR,(P 5 $s),(P 19 $s),(P 27 $s),(P 19 $s))
 foreach($x in 7,12,17,22,27){$g.DrawRectangle($penB,(P $x $s),(P 12 $s),(P 1.2 $s),(P 8 $s))}
 $penD.Dispose();$penR.Dispose();$penB.Dispose();$brush.Dispose()
}
$column = {
 param($g,$s,$dark,$red,$blue,$concrete)
 $penD=New-Object Drawing.Pen($dark,[Math]::Max(1,(P 1 $s))); $penR=New-Object Drawing.Pen($red,[Math]::Max(1,(P 1.4 $s))); $penB=New-Object Drawing.Pen($blue,[Math]::Max(1,(P 1 $s))); $brush=New-Object Drawing.SolidBrush($concrete)
 $g.FillRectangle($brush,(P 11 $s),(P 2 $s),(P 10 $s),(P 28 $s));$g.DrawRectangle($penD,(P 11 $s),(P 2 $s),(P 10 $s),(P 28 $s))
 $g.DrawLine($penR,(P 13.5 $s),(P 4 $s),(P 13.5 $s),(P 28 $s));$g.DrawLine($penR,(P 18.5 $s),(P 4 $s),(P 18.5 $s),(P 28 $s))
 foreach($y in 6,10,14,18,22,26){$g.DrawRectangle($penB,(P 12.5 $s),(P $y $s),(P 7 $s),(P 1.5 $s))}
 $penD.Dispose();$penR.Dispose();$penB.Dispose();$brush.Dispose()
}
$wall = {
 param($g,$s,$dark,$red,$blue,$concrete)
 $penD=New-Object Drawing.Pen($dark,[Math]::Max(1,(P 1 $s)));$penR=New-Object Drawing.Pen($red,[Math]::Max(1,(P 1 $s)));$penB=New-Object Drawing.Pen($blue,[Math]::Max(1,(P 1 $s)));$brush=New-Object Drawing.SolidBrush($concrete)
 $g.FillRectangle($brush,(P 5 $s),(P 3 $s),(P 22 $s),(P 26 $s));$g.DrawRectangle($penD,(P 5 $s),(P 3 $s),(P 22 $s),(P 26 $s))
 foreach($x in 8,12,16,20,24){$g.DrawLine($penR,(P $x $s),(P 4 $s),(P $x $s),(P 28 $s))}
 foreach($y in 7,11,15,19,23,27){$g.DrawLine($penB,(P 6 $s),(P $y $s),(P 26 $s),(P $y $s))}
 $penD.Dispose();$penR.Dispose();$penB.Dispose();$brush.Dispose()
}
$slab = {
 param($g,$s,$dark,$red,$blue,$concrete)
 $penD=New-Object Drawing.Pen($dark,[Math]::Max(1,(P 1 $s)));$penR=New-Object Drawing.Pen($red,[Math]::Max(1,(P 1 $s)));$penB=New-Object Drawing.Pen($blue,[Math]::Max(1,(P 1 $s)));$brush=New-Object Drawing.SolidBrush($concrete)
 $pts = [Drawing.PointF[]]@((New-Object Drawing.PointF((P 4 $s),(P 11 $s))),(New-Object Drawing.PointF((P 23 $s),(P 5 $s))),(New-Object Drawing.PointF((P 29 $s),(P 12 $s))),(New-Object Drawing.PointF((P 10 $s),(P 18 $s))))
 $g.FillPolygon($brush,$pts);$g.DrawPolygon($penD,$pts)
 foreach($i in 1..4){$x=4+$i*4.5;$g.DrawLine($penR,(P $x $s),(P (11-$i*1.4) $s),(P ($x+6) $s),(P (18-$i*1.4) $s))}
 foreach($i in 1..4){$g.DrawLine($penB,(P (5+$i*1.3) $s),(P (12+$i*1.2) $s),(P (24+$i*1.3) $s),(P (6+$i*1.2) $s))}
 $penD.Dispose();$penR.Dispose();$penB.Dispose();$brush.Dispose()
}
$foundation = {
 param($g,$s,$dark,$red,$blue,$concrete)
 $penD=New-Object Drawing.Pen($dark,[Math]::Max(1,(P 1 $s)));$penR=New-Object Drawing.Pen($red,[Math]::Max(1,(P 1.3 $s)));$penB=New-Object Drawing.Pen($blue,[Math]::Max(1,(P 1 $s)));$brush=New-Object Drawing.SolidBrush($concrete)
 $g.FillRectangle($brush,(P 12 $s),(P 5 $s),(P 8 $s),(P 16 $s));$g.DrawRectangle($penD,(P 12 $s),(P 5 $s),(P 8 $s),(P 16 $s))
 $g.FillRectangle($brush,(P 4 $s),(P 21 $s),(P 24 $s),(P 7 $s));$g.DrawRectangle($penD,(P 4 $s),(P 21 $s),(P 24 $s),(P 7 $s))
 $g.DrawLine($penR,(P 14 $s),(P 7 $s),(P 14 $s),(P 27 $s));$g.DrawLine($penR,(P 18 $s),(P 7 $s),(P 18 $s),(P 27 $s))
 foreach($x in 7,11,15,19,23){$g.DrawLine($penB,(P $x $s),(P 24 $s),(P ($x+2) $s),(P 24 $s))}
 $penD.Dispose();$penR.Dispose();$penB.Dispose();$brush.Dispose()
}
$dim = {
 param($g,$s,$dark,$red,$blue,$concrete)
 $penD=New-Object Drawing.Pen($dark,[Math]::Max(1,(P 1 $s)));$penB=New-Object Drawing.Pen($blue,[Math]::Max(1,(P 1 $s)));$brushR=New-Object Drawing.SolidBrush($red)
 $g.DrawLine($penD,(P 4 $s),(P 16 $s),(P 28 $s),(P 16 $s));$g.DrawLine($penD,(P 4 $s),(P 12 $s),(P 4 $s),(P 20 $s));$g.DrawLine($penD,(P 28 $s),(P 12 $s),(P 28 $s),(P 20 $s))
 $g.FillPolygon($brushR,[Drawing.PointF[]]@((New-Object Drawing.PointF((P 4 $s),(P 16 $s))),(New-Object Drawing.PointF((P 8 $s),(P 14 $s))),(New-Object Drawing.PointF((P 8 $s),(P 18 $s)))))
 $g.FillPolygon($brushR,[Drawing.PointF[]]@((New-Object Drawing.PointF((P 28 $s),(P 16 $s))),(New-Object Drawing.PointF((P 24 $s),(P 14 $s))),(New-Object Drawing.PointF((P 24 $s),(P 18 $s)))))
 $g.DrawLine($penB,(P 8 $s),(P 23 $s),(P 24 $s),(P 23 $s))
 $penD.Dispose();$penB.Dispose();$brushR.Dispose()
}
$docs = {
 param($g,$s,$dark,$red,$blue,$concrete)
 $penD=New-Object Drawing.Pen($dark,[Math]::Max(1,(P 1 $s)));$penB=New-Object Drawing.Pen($blue,[Math]::Max(1,(P 1 $s)));$penR=New-Object Drawing.Pen($red,[Math]::Max(1,(P 1 $s)));$brush=New-Object Drawing.SolidBrush([Drawing.Color]::White)
 $g.FillRectangle($brush,(P 7 $s),(P 3 $s),(P 18 $s),(P 26 $s));$g.DrawRectangle($penD,(P 7 $s),(P 3 $s),(P 18 $s),(P 26 $s))
 foreach($y in 11,15,19,23){$g.DrawLine($penB,(P 10 $s),(P $y $s),(P 22 $s),(P $y $s))}
 $g.DrawLine($penR,(P 10 $s),(P 26 $s),(P 18 $s),(P 26 $s))
 $penD.Dispose();$penB.Dispose();$penR.Dispose();$brush.Dispose()
}

foreach($s in 16,32) {
    New-Icon 'Beam' $s $beam
    New-Icon 'Column' $s $column
    New-Icon 'Wall' $s $wall
    New-Icon 'Slab' $s $slab
    New-Icon 'Foundation' $s $foundation
    New-Icon 'Dim' $s $dim
    New-Icon 'Docs' $s $docs
}
