<#
.SYNOPSIS
  A labelled horizontal strip of images cropped to the same region (evidence comparisons: a fighter
  before/after from the front and back, a skin before/after a swap). Windows PowerShell 5.1 /
  System.Drawing; JPEG out.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/vfx/strip.ps1 -In "a.png,b.png" -Labels "v0.9.16,v0.9.17" -Out cmp.jpg -Crop "0.34,0.2,0.32,0.55"
#>
param(
	[Parameter(Mandatory = $true)][string]$In,
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$Labels = "",
	[string]$Crop = "0,0,1,1",        # x, y, w, h as fractions of the source
	[int]$TileH = 520,
	[long]$Quality = 86
)
Add-Type -AssemblyName System.Drawing
$files = $In -split ','
$names = if ($Labels -ne "") { $Labels -split ',' } else { @() }
$c = $Crop -split ',' | ForEach-Object { [double]$_ }
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $Quality
$font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$white = [System.Drawing.Brushes]::White
$shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
$first = [System.Drawing.Image]::FromFile($files[0].Trim())
$src = New-Object System.Drawing.Rectangle ([int]($first.Width * $c[0])), ([int]($first.Height * $c[1])), ([int]($first.Width * $c[2])), ([int]($first.Height * $c[3]))
$first.Dispose()
$tileW = [int]($src.Width * $TileH / $src.Height)
$bmp = New-Object System.Drawing.Bitmap ($tileW * $files.Count), $TileH
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
for ($k = 0; $k -lt $files.Count; $k++) {
	$img = [System.Drawing.Image]::FromFile($files[$k].Trim())
	$g.DrawImage($img, (New-Object System.Drawing.Rectangle ($tileW * $k), 0, $tileW, $TileH), $src, [System.Drawing.GraphicsUnit]::Pixel)
	$img.Dispose()
	if ($k -lt $names.Count -and $names[$k] -ne "") {
		$size = $g.MeasureString($names[$k], $font)
		$g.FillRectangle($shade, ($tileW * $k), 0, ($size.Width + 12), ($size.Height + 6))
		$g.DrawString($names[$k], $font, $white, ($tileW * $k + 6), 3)
	}
}
$g.Dispose()
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save($Out, $codec, $ep)
$bmp.Dispose()
Write-Host "wrote $Out"
