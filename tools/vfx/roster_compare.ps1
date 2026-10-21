<#
.SYNOPSIS
  One labelled before/after roster comparison per view from tools/vfx/roster_wall.ps1 captures:
  the fighters' band of each wall (before on top, after below), cropped and saved as an
  evidence-sized JPEG. Windows PowerShell 5.1 / System.Drawing.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/vfx/roster_compare.ps1 -In B:\Critterweight-work\v0.9.17\captures\roster -Out docs\evidence\verification\v0.9.17\art -BeforeLabel v0.9.16 -AfterLabel v0.9.17
#>
param(
	[Parameter(Mandatory = $true)][string]$In,
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$BeforeLabel = "before",
	[string]$AfterLabel = "after",
	[double]$CropX = 0.12, [double]$CropY = 0.37, [double]$CropW = 0.76, [double]$CropH = 0.24,
	[int]$Width = 2400,
	[long]$Quality = 86
)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Out | Out-Null
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $Quality
$font = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
$white = [System.Drawing.Brushes]::White
$shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
foreach ($view in @('front', 'back')) {
	$pair = @(@($BeforeLabel, (Join-Path $In "before_$view.png")), @($AfterLabel, (Join-Path $In "after_$view.png")))
	if (-not (Test-Path $pair[0][1]) -or -not (Test-Path $pair[1][1])) { Write-Host "missing $view captures"; continue }
	$first = [System.Drawing.Image]::FromFile($pair[0][1])
	$src = New-Object System.Drawing.Rectangle ([int]($first.Width * $CropX)), ([int]($first.Height * $CropY)), ([int]($first.Width * $CropW)), ([int]($first.Height * $CropH))
	$first.Dispose()
	$tileH = [int]($src.Height * $Width / $src.Width)
	$bmp = New-Object System.Drawing.Bitmap $Width, ($tileH * 2)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	for ($k = 0; $k -lt 2; $k++) {
		$img = [System.Drawing.Image]::FromFile($pair[$k][1])
		$dst = New-Object System.Drawing.Rectangle 0, ($tileH * $k), $Width, $tileH
		$g.DrawImage($img, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
		$img.Dispose()
		$label = "{0} ({1})" -f $pair[$k][0], $view
		$size = $g.MeasureString($label, $font)
		$g.FillRectangle($shade, 0, ($tileH * $k), ($size.Width + 16), ($size.Height + 8))
		$g.DrawString($label, $font, $white, 8, ($tileH * $k + 4))
	}
	$g.Dispose()
	$path = Join-Path $Out "roster_$view.jpg"
	$bmp.Save($path, $codec, $ep)
	$bmp.Dispose()
	Write-Host "wrote $path"
}
