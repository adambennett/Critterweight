<#
.SYNOPSIS
  Copies images into an evidence folder as compact JPEGs (resized to at most -MaxWidth).
  Windows PowerShell 5.1 / System.Drawing.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/dev/jpeg_evidence.ps1 -In "B:\a.png,B:\b.png" -Out docs\evidence\verification\v0.9.17\art -MaxWidth 1600
#>
param(
	[Parameter(Mandatory = $true)][string]$In,
	[Parameter(Mandatory = $true)][string]$Out,
	[int]$MaxWidth = 1600,
	[long]$Quality = 84,
	[string]$Prefix = ""
)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Out | Out-Null
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $Quality
foreach ($src in ($In -split ',')) {
	$src = $src.Trim()
	if (-not (Test-Path $src)) { Write-Host "missing $src"; continue }
	$img = [System.Drawing.Image]::FromFile($src)
	$w = [Math]::Min($MaxWidth, $img.Width)
	$h = [int]($img.Height * $w / $img.Width)
	$bmp = New-Object System.Drawing.Bitmap $w, $h
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.DrawImage($img, 0, 0, $w, $h)
	$g.Dispose()
	$img.Dispose()
	$name = $Prefix + [System.IO.Path]::GetFileNameWithoutExtension($src) + ".jpg"
	$bmp.Save((Join-Path $Out $name), $codec, $ep)
	$bmp.Dispose()
	Write-Host "wrote $name"
}
