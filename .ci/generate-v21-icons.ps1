Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$outDir = Join-Path $PWD 'source\AP.BimTools\Icons'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$icons = [ordered]@{
  ArchModel='A'; ArchRooms='R'; Select='S'; Structure='ST'; Marks='#';
  RebarStudio='RB'; RebarBeam='B'; RebarColumn='C'; RebarWall='W'; RebarSlab='SL'; RebarFoundation='F';
  RebarTools='T'; RebarApply='AP'; RebarStarter='SF'; RebarClear='X'; RebarSpacing='SP'; RebarNumber='N'; RebarSelect='SE';
  RebarDocs='D'; BBS='BBS'; Schedule='SC'; Review3D='3D'; Sections='SEC'; Audit='Q'; Report='RP'; Visible='V';
  QuickDim='DIM'; DimGrid='G'; DimLevel='L'; DimWall='W'; DimPile='P'; DimColumn='C'; QA='QA';
  MepConnect='M'; MepQA='Q'; MepData='D'; GenQA='Q'; GenDocs='DOC'; Tools='T'
}

function Get-Color([string]$name) {
  if ($name.StartsWith('Rebar') -or $name -in @('BBS','Schedule','Review3D','Sections','Visible')) { return [Drawing.Color]::FromArgb(255,35,92,180) }
  if ($name.StartsWith('Dim') -or $name -eq 'QuickDim') { return [Drawing.Color]::FromArgb(255,110,65,170) }
  if ($name.StartsWith('Mep')) { return [Drawing.Color]::FromArgb(255,20,135,120) }
  if ($name.StartsWith('Arch')) { return [Drawing.Color]::FromArgb(255,185,95,30) }
  if ($name -in @('Structure','Marks')) { return [Drawing.Color]::FromArgb(255,90,90,90) }
  if ($name -in @('QA','GenQA','Audit','Report')) { return [Drawing.Color]::FromArgb(255,180,55,55) }
  return [Drawing.Color]::FromArgb(255,65,110,70)
}

foreach ($entry in $icons.GetEnumerator()) {
  foreach ($size in @(16,32)) {
    $bmp = New-Object Drawing.Bitmap($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([Drawing.Color]::Transparent)

    $color = Get-Color $entry.Key
    $penWidth = [Math]::Max(1,[int]($size / 10))
    $pen = New-Object Drawing.Pen($color,$penWidth)
    $pad = [Math]::Max(1,[int]($size / 16))
    $g.DrawRectangle($pen,$pad,$pad,$size-(2*$pad)-1,$size-(2*$pad)-1)

    if ($entry.Key -eq 'RebarBeam') {
      $y1=[int]($size*.35); $y2=[int]($size*.65)
      $g.DrawLine($pen,[int]($size*.2),$y1,[int]($size*.8),$y1)
      $g.DrawLine($pen,[int]($size*.2),$y2,[int]($size*.8),$y2)
    }
    elseif ($entry.Key -eq 'RebarColumn') {
      $g.DrawRectangle($pen,[int]($size*.30),[int]($size*.20),[int]($size*.40),[int]($size*.60))
    }
    elseif ($entry.Key -eq 'RebarWall') {
      $g.DrawLine($pen,[int]($size*.30),[int]($size*.18),[int]($size*.30),[int]($size*.82))
      $g.DrawLine($pen,[int]($size*.70),[int]($size*.18),[int]($size*.70),[int]($size*.82))
      $g.DrawLine($pen,[int]($size*.30),[int]($size*.35),[int]($size*.70),[int]($size*.35))
      $g.DrawLine($pen,[int]($size*.30),[int]($size*.65),[int]($size*.70),[int]($size*.65))
    }
    elseif ($entry.Key -eq 'RebarSlab') {
      foreach($q in @(0.32,0.50,0.68)) {
        $g.DrawLine($pen,[int]($size*.22),[int]($size*$q),[int]($size*.78),[int]($size*$q))
        $g.DrawLine($pen,[int]($size*$q),[int]($size*.22),[int]($size*$q),[int]($size*.78))
      }
    }
    elseif ($entry.Key -eq 'RebarFoundation') {
      $g.DrawLine($pen,[int]($size*.20),[int]($size*.72),[int]($size*.80),[int]($size*.72))
      $g.DrawLine($pen,[int]($size*.32),[int]($size*.30),[int]($size*.68),[int]($size*.30))
      $g.DrawLine($pen,[int]($size*.32),[int]($size*.30),[int]($size*.22),[int]($size*.72))
      $g.DrawLine($pen,[int]($size*.68),[int]($size*.30),[int]($size*.78),[int]($size*.72))
    }
    elseif ($entry.Key -eq 'QuickDim' -or $entry.Key.StartsWith('Dim')) {
      $g.DrawLine($pen,[int]($size*.20),[int]($size*.50),[int]($size*.80),[int]($size*.50))
      $g.DrawLine($pen,[int]($size*.20),[int]($size*.32),[int]($size*.20),[int]($size*.68))
      $g.DrawLine($pen,[int]($size*.80),[int]($size*.32),[int]($size*.80),[int]($size*.68))
    }
    else {
      $fontSize = if ($entry.Value.Length -le 2) { [Math]::Max(6,[int]($size*.34)) } else { [Math]::Max(5,[int]($size*.22)) }
      $font = New-Object Drawing.Font('Segoe UI',$fontSize,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
      $brush = New-Object Drawing.SolidBrush($color)
      $fmt = New-Object Drawing.StringFormat
      $fmt.Alignment = [Drawing.StringAlignment]::Center
      $fmt.LineAlignment = [Drawing.StringAlignment]::Center
      $rect = New-Object Drawing.RectangleF(0,0,$size,$size)
      $g.DrawString([string]$entry.Value,$font,$brush,$rect,$fmt)
      $fmt.Dispose(); $brush.Dispose(); $font.Dispose()
    }

    $path = Join-Path $outDir ($entry.Key + $size + '.png')
    $bmp.Save($path,[Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose(); $g.Dispose(); $bmp.Dispose()
  }
}
Write-Host "Generated $($icons.Count * 2) AP-BIM ribbon icons."
