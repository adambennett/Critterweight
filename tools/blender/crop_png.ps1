<#
.SYNOPSIS
  Crops (and optionally scales) review images for art comparisons. Windows PowerShell 5.1 (System.Drawing).
.EXAMPLE
  powershell -File tools/blender/crop_png.ps1 -In a.png -Out a_crop.png -X 1300 -Y 400 -W 1240 -H 1240 -Scale 0.5
  powershell -File tools/blender/crop_png.ps1 -In a.png,b.png -Out side_by_side.png -X 1300 -Y 400 -W 1240 -H 1240 -Scale 0.5   # joins horizontally
#>
param([string[]]$In, [string]$Out, [int]$X = 0, [int]$Y = 0, [int]$W = 0, [int]$H = 0, [double]$Scale = 1.0)
Add-Type -AssemblyName System.Drawing
$tiles = @()
$In = @($In | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
foreach ($p in $In) {
	$src = [System.Drawing.Image]::FromFile((Resolve-Path $p))
	$w = if ($W -gt 0) { $W } else { $src.Width - $X }
	$h = if ($H -gt 0) { $H } else { $src.Height - $Y }
	$tw = [int]($w * $Scale); $th = [int]($h * $Scale)
	$bmp = New-Object System.Drawing.Bitmap $tw, $th
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $tw, $th), (New-Object System.Drawing.Rectangle $X, $Y, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
	$g.Dispose(); $src.Dispose()
	$tiles += $bmp
}
$total = ($tiles | Measure-Object -Property Width -Sum).Sum
$maxh = ($tiles | Measure-Object -Property Height -Maximum).Maximum
$canvas = New-Object System.Drawing.Bitmap ([int]$total), ([int]$maxh)
$g2 = [System.Drawing.Graphics]::FromImage($canvas)
$x0 = 0
foreach ($t in $tiles) { $g2.DrawImage($t, $x0, 0); $x0 += $t.Width; $t.Dispose() }
$g2.Dispose()
$canvas.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose()
Write-Output "wrote $Out"
