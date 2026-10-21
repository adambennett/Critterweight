<#
.SYNOPSIS
  One compact before/after VFX overview per fighter from two test_vfx_showcase capture folders.
.DESCRIPTION
  For each fighter: a strip of key frames (ability 1, ability 2 and JUICE at contact and in motion,
  the charged heavy or heavy at contact, and the elemental reaction), "before" on top and "after"
  below, each cropped to the fight area, labelled, saved as JPEG (evidence-sized).
  Windows PowerShell 5.1 / System.Drawing.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/vfx/overview_sheet.ps1 -Before B:\vfx\before -After B:\vfx\after -Out docs\evidence\verification\v0.9.17\vfx
#>
param(
	[Parameter(Mandatory = $true)][string]$Before,
	[Parameter(Mandatory = $true)][string]$After,
	[Parameter(Mandatory = $true)][string]$Out,
	[int]$TileW = 360,
	[long]$Quality = 82,
	[double]$CropX = 0.234, [double]$CropY = 0.255, [double]$CropW = 0.547, [double]$CropH = 0.648
)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Out | Out-Null
$index = Get-Content -Raw (Join-Path $After 'index.json') | ConvertFrom-Json
$font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$white = [System.Drawing.Brushes]::White
$shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $Quality
$want = @(@('ability1', 'contact'), @('ability1', 'motion'), @('ability2', 'contact'), @('ability2', 'motion'),
	@('juice', 'contact'), @('juice', 'motion'), @('heavy_charged', 'release'), @('heavy', 'contact'), @('reaction', 'reaction'))
$fighters = $index.shots | ForEach-Object { $_.fighter } | Select-Object -Unique
foreach ($f in $fighters) {
	$tiles = @()
	foreach ($w in $want) {
		$shot = $index.shots | Where-Object { $_.fighter -eq $f -and $_.shot -eq $w[0] } | Select-Object -First 1
		if ($null -eq $shot) { continue }
		$k = [array]::IndexOf(@($shot.labels), $w[1])
		if ($k -lt 0) { continue }
		$tiles += , @("$($w[0]) $($w[1])", @($shot.files)[$k])
	}
	if ($tiles.Count -eq 0) { continue }
	$first = [System.Drawing.Image]::FromFile((Join-Path $After $tiles[0][1]))
	$cx = [int]($first.Width * $CropX); $cy = [int]($first.Height * $CropY)
	$cw = [int]($first.Width * $CropW); $ch = [int]($first.Height * $CropH)
	$first.Dispose()
	$tileH = [int]($TileW * $ch / $cw)
	$sheet = New-Object System.Drawing.Bitmap ([int]($TileW * $tiles.Count)), ([int]($tileH * 2))
	$g = [System.Drawing.Graphics]::FromImage($sheet)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.Clear([System.Drawing.Color]::Black)
	for ($k = 0; $k -lt $tiles.Count; $k++) {
		$row = 0
		foreach ($dir in @($Before, $After)) {
			$p = Join-Path $dir $tiles[$k][1]
			if (Test-Path $p) {
				$img = [System.Drawing.Image]::FromFile($p)
				$g.DrawImage($img, (New-Object System.Drawing.Rectangle ([int]($k * $TileW)), ([int]($row * $tileH)), $TileW, $tileH),
					(New-Object System.Drawing.Rectangle $cx, $cy, $cw, $ch), [System.Drawing.GraphicsUnit]::Pixel)
				$img.Dispose()
			}
			$text = "{0}  {1}" -f $(if ($row -eq 0) { "0.9.16" } else { "0.9.17" }), $tiles[$k][0]
			$sz = $g.MeasureString($text, $font)
			$g.FillRectangle($shade, [single]($k * $TileW + 3), [single]($row * $tileH + 3), [single]($sz.Width + 4), [single]($sz.Height + 1))
			$g.DrawString($text, $font, $white, [single]($k * $TileW + 5), [single]($row * $tileH + 4))
			$row++
		}
	}
	$g.Dispose()
	$sheet.Save((Join-Path $Out "$f.jpg"), $codec, $ep)
	$sheet.Dispose()
	Write-Host "overview $f"
}
