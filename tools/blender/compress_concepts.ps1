param([string]$Source='B:\Critterweight-art\concepts',[string]$Destination=(Join-Path $PSScriptRoot '..\..\docs\evidence\art\concepts'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$encoder=[Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object {$_.MimeType -eq 'image/jpeg'}
$parameters=[Drawing.Imaging.EncoderParameters]::new(1)
$parameters.Param[0]=[Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality,[long]86)
try {
 foreach ($file in Get-ChildItem -LiteralPath $Source -Filter '*-turnaround-*.png') {
  $img=[Drawing.Image]::FromFile($file.FullName)
  try { $img.Save((Join-Path $Destination ($file.BaseName+'.jpg')),$encoder,$parameters) } finally { $img.Dispose() }
 }
} finally {$parameters.Dispose()}
