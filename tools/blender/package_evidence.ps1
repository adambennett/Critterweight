param([string]$ArtRoot='B:\Critterweight-art')
# Run with Windows PowerShell 5.1 (powershell.exe) for System.Drawing.
# Evidence processing only: crop/resize captured pixels without retouching the art.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'art_env.ps1')
Add-Type -AssemblyName System.Drawing
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out=Join-Path $repo 'docs\evidence\art\revamp'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$ids=@('f_stoke','f_jitters','f_dredge','f_slurry','f_gusto','f_dozer','boss_bilge','boss_conduit','boss_snappington','npc_scrapling','npc_blister','npc_kid_lamprey')
$jpeg=[Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object {$_.MimeType -eq 'image/jpeg'}
$quality=[Drawing.Imaging.EncoderParameters]::new(1)
$quality.Param[0]=[Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality,[long]87)
$font=[Drawing.Font]::new('Segoe UI',18)
$small=[Drawing.Font]::new('Segoe UI',12)
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
public static class ArtPixels {
 public static Rectangle Bounds(Bitmap image) {
  int minX=image.Width,minY=image.Height,maxX=-1,maxY=-1;
  for(int y=0;y<image.Height;y++)for(int x=0;x<image.Width;x++) {
   Color c=image.GetPixel(x,y);
   if(c.R<90 && c.G<90 && c.B<90) {
    minX=Math.Min(minX,x);minY=Math.Min(minY,y);maxX=Math.Max(maxX,x);maxY=Math.Max(maxY,y);
   }
  }
  if(maxX<0)throw new Exception("Empty silhouette");
  return Rectangle.FromLTRB(minX,minY,maxX+1,maxY+1);
 }
}
"@
function Save-Jpeg([Drawing.Image]$image,[string]$name) {$image.Save((Join-Path $out $name),$jpeg,$quality)}
function Copy-Jpeg([string]$path,[string]$name) {
 $im=[Drawing.Image]::FromFile($path)
 try {Save-Jpeg $im $name} finally {$im.Dispose()}
}
$bounds=@{}
$ledger=@()
try {
 foreach($id in $ids) {
  foreach($phase in @('before','after')) {
   $path=Join-Path $ArtRoot "captures\$phase\$id-silhouette.png"
   $im=[Drawing.Bitmap]::FromFile($path)
   try {$bounds["$phase/$id"]=[ArtPixels]::Bounds($im)} finally {$im.Dispose()}
  }
  $union=[Drawing.Rectangle]::Union($bounds["before/$id"],$bounds["after/$id"])
  $union.Inflate(50,50)
  $union=[Drawing.Rectangle]::Intersect($union,[Drawing.Rectangle]::new(0,0,1920,1080))
  $height=[int][Math]::Ceiling(600.0*$union.Height/$union.Width)
  $sheet=[Drawing.Bitmap]::new(1200,$height+60)
  $g=[Drawing.Graphics]::FromImage($sheet)
  try {
   $g.Clear([Drawing.Color]::FromArgb(242,240,232));$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
   $column=0
   foreach($phase in @('before','after')) {
    $g.DrawString(($id+' / '+$phase),$font,[Drawing.Brushes]::Black,[single]($column*600+16),[single]12)
    $path=Join-Path $ArtRoot "captures\$phase\$id.png"
    $im=[Drawing.Image]::FromFile($path)
    try {$g.DrawImage($im,[Drawing.Rectangle]::new($column*600,60,600,$height),$union,[Drawing.GraphicsUnit]::Pixel)} finally {$im.Dispose()}
    $ledger += [pscustomobject]@{id=$id;phase=$phase;source=("captures/$phase/$id.png");sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;crop=@($union.X,$union.Y,$union.Width,$union.Height);output="$id-comparison.jpg"}
    $column++
   }
   Save-Jpeg $sheet "$id-comparison.jpg"
  } finally {$g.Dispose();$sheet.Dispose()}
 }
 # Native 48-pixel thumbnails and 3x nearest-neighbour enlargements, with no silhouette editing.
 $sheet=[Drawing.Bitmap]::new(1000,80+$ids.Count*170)
 $g=[Drawing.Graphics]::FromImage($sheet)
 try {
  $g.Clear([Drawing.Color]::White)
  $g.DrawString('48 px silhouettes: native size + 3x enlargement',$font,[Drawing.Brushes]::Black,12,10)
  $g.DrawString('BEFORE',$small,[Drawing.Brushes]::Black,220,50);$g.DrawString('AFTER',$small,[Drawing.Brushes]::Black,600,50)
  for($i=0;$i -lt $ids.Count;$i++) {
   $id=$ids[$i];$y=80+$i*170
   $g.DrawString($id,$small,[Drawing.Brushes]::Black,10,[single]($y+55))
   for($p=0;$p -lt 2;$p++) {
    $phase=@('before','after')[$p]
    $im=[Drawing.Image]::FromFile((Join-Path $ArtRoot "captures\$phase\$id-silhouette.png"))
    $thumb=[Drawing.Bitmap]::new(48,48);$tg=[Drawing.Graphics]::FromImage($thumb)
    try {
     $tg.Clear([Drawing.Color]::White);$tg.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
     $b=$bounds["$phase/$id"];$scale=46.0/[Math]::Max($b.Width,$b.Height)
     $w=[int]($b.Width*$scale);$h=[int]($b.Height*$scale)
     $tg.DrawImage($im,[Drawing.Rectangle]::new([int]((48-$w)/2),[int]((48-$h)/2),$w,$h),$b,[Drawing.GraphicsUnit]::Pixel)
     $g.DrawImageUnscaled($thumb,220+$p*380,$y+50)
     $g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
     $g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
     $g.DrawImage($thumb,[Drawing.Rectangle]::new(300+$p*380,$y+5,144,144),[Drawing.Rectangle]::new(0,0,48,48),[Drawing.GraphicsUnit]::Pixel)
    } finally {$tg.Dispose();$thumb.Dispose();$im.Dispose()}
   }
  }
  Save-Jpeg $sheet 'silhouettes-48px.jpg'
 } finally {$g.Dispose();$sheet.Dispose()}
 foreach($phase in @('before','after')) {
  foreach($name in @('wall-fighters','wall-bosses','wall-minions','wall-hub','wall-crowd','duel-1920x1080','duel-1280x800','busy-1920x1080','busy-1280x800')) {
   Copy-Jpeg (Join-Path $ArtRoot "captures\$phase\$name.png") "$phase-$name.jpg"
  }
 }
 foreach($id in $ids) {
  foreach($suffix in @('collision','effects-normal','effects-status')) {Copy-Jpeg (Join-Path $ArtRoot "captures\after\$id-$suffix.png") "$id-$suffix.jpg"}
  $sheet=[Drawing.Bitmap]::new(1600,960);$g=[Drawing.Graphics]::FromImage($sheet)
  try {
   $g.Clear([Drawing.Color]::FromArgb(242,240,232));$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
   for($n=0;$n -lt 4;$n++) {
    $x=($n%2)*800;$y=[int][Math]::Floor($n/2)*480
    $captureSecond=if($id -eq 'npc_blister'){8+$n}else{20+3*$n}
    $g.DrawString(($id+' / '+$captureSecond+' seconds'),$small,[Drawing.Brushes]::Black,[single]($x+10),[single]($y+3))
    $im=[Drawing.Image]::FromFile((Join-Path $ArtRoot ('captures\after\'+$id+'-motion_'+$n.ToString('00')+'.png')))
    try {$g.DrawImage($im,[Drawing.Rectangle]::new($x,$y+30,800,450))} finally {$im.Dispose()}
   }
   Save-Jpeg $sheet "$id-motion.jpg"
  } finally {$g.Dispose();$sheet.Dispose()}
 }
 $ledger | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'image-processing.json') -Encoding utf8
 Write-Output "Saved evidence in $out"
} finally {$font.Dispose();$small.Dispose();$quality.Dispose()}
