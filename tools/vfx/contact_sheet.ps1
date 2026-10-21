<#
.SYNOPSIS
  Before/after VFX contact sheets from two test_vfx_showcase capture folders (docs/art/VFX.md).
.DESCRIPTION
  For every shot in the "after" folder's index.json, writes <Out>\<fighter>_<shot>.png: the top row
  is the "before" capture's frames, the bottom row the "after" frames (same simulation times),
  each cropped to the fight area and labelled with its phase (prep, contact, motion, ...).
  Windows PowerShell 5.1 / System.Drawing.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/vfx/contact_sheet.ps1 -Before B:\vfx\before -After B:\vfx\after -Out B:\vfx\sheets
#>
param(
	[Parameter(Mandatory = $true)][string]$Before,
	[Parameter(Mandatory = $true)][string]$After,
	[Parameter(Mandatory = $true)][string]$Out,
	[double]$CropX = 0.234, [double]$CropY = 0.255, [double]$CropW = 0.547, [double]$CropH = 0.648,   # fractions of the frame
	[int]$TileW = 520,
	[string]$Only = ""
)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Out | Out-Null
$index = Get-Content -Raw (Join-Path $After 'index.json') | ConvertFrom-Json
$font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$white = [System.Drawing.Brushes]::White
$shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
foreach ($shot in $index.shots) {
	$name = "$($shot.fighter)_$($shot.shot)"
	if ($Only -ne "" -and $name -notlike "*$Only*") { continue }
	$files = @($shot.files)
	$n = $files.Count
	$first = [System.Drawing.Image]::FromFile((Join-Path $After $files[0]))
	$cx = [int]($first.Width * $CropX); $cy = [int]($first.Height * $CropY)
	$cw = [int]($first.Width * $CropW); $ch = [int]($first.Height * $CropH)
	$first.Dispose()
	$tileH = [int]($TileW * $ch / $cw)
	$sheet = New-Object System.Drawing.Bitmap ([int]($TileW * $n)), ([int]($tileH * 2))
	$g = [System.Drawing.Graphics]::FromImage($sheet)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.Clear([System.Drawing.Color]::Black)
	for ($k = 0; $k -lt $n; $k++) {
		$label = @($shot.labels)[$k]
		$row = 0
		foreach ($dir in @($Before, $After)) {
			$p = Join-Path $dir $files[$k]
			if (Test-Path $p) {
				$img = [System.Drawing.Image]::FromFile($p)
				$src = New-Object System.Drawing.Rectangle $cx, $cy, $cw, $ch
				$dst = New-Object System.Drawing.Rectangle ([int]($k * $TileW)), ([int]($row * $tileH)), $TileW, $tileH
				$g.DrawImage($img, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
				$img.Dispose()
			}
			$tag = if ($row -eq 0) { "BEFORE (v0.9.16)" } else { "AFTER (v0.9.17)" }
			$text = "$tag  $label"
			$sz = $g.MeasureString($text, $font)
			$g.FillRectangle($shade, [single]($k * $TileW + 4), [single]($row * $tileH + 4), [single]($sz.Width + 6), [single]($sz.Height + 2))
			$g.DrawString($text, $font, $white, [single]($k * $TileW + 7), [single]($row * $tileH + 5))
			$row++
		}
	}
	$g.Dispose()
	$sheet.Save((Join-Path $Out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
	$sheet.Dispose()
	Write-Host "sheet $name"
}
