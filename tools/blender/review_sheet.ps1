param([string]$Phase='after',[string[]]$Ids=@('f_stoke','f_jitters','f_dredge','f_slurry','f_gusto','f_dozer'),[string]$Output='B:\Critterweight-art\captures\review-sheet.jpg')
Add-Type -AssemblyName System.Drawing
$sheet=[Drawing.Bitmap]::new(1500,[int]([Math]::Ceiling($Ids.Count/3)*540))
$graphics=[Drawing.Graphics]::FromImage($sheet)
$graphics.Clear([Drawing.Color]::FromArgb(246,244,237))
$graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font=[Drawing.Font]::new('Segoe UI',18)
try {
 for($i=0;$i -lt $Ids.Count;$i++) {
  $img=[Drawing.Image]::FromFile("B:\Critterweight-art\captures\$Phase\$($Ids[$i]).png")
  try {
   $x=($i%3)*500;$y=[Math]::Floor($i/3)*540
   $graphics.DrawString($Ids[$i],$font,[Drawing.Brushes]::Black,[single]($x+15),[single]($y+8))
   $graphics.DrawImage($img,[Drawing.Rectangle]::new($x,$y+40,500,500),[Drawing.Rectangle]::new(480,90,960,960),[Drawing.GraphicsUnit]::Pixel)
  } finally {$img.Dispose()}
 }
 $sheet.Save($Output,[Drawing.Imaging.ImageFormat]::Jpeg)
} finally {$graphics.Dispose();$font.Dispose();$sheet.Dispose()}
