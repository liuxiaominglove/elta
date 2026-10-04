# ELTA Windows - build assets/elta.ico from the shared source PNG (multi-size, PNG-compressed entries)
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File windows\make-icon.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = (Resolve-Path (Join-Path $root '..\generated-images\ELTA_icon_rounded_v3_v31.png')).Path
$outDir = Join-Path $root 'src\Elta.Windows\assets'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = Join-Path $outDir 'elta.ico'

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$source = [System.Drawing.Image]::FromFile($src)

function Get-PngBytes([System.Drawing.Image]$img, [int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($img, 0, 0, $size, $size)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $ms.ToArray()
}

$pngs = @{}
foreach ($s in $sizes) { $pngs[$s] = [byte[]](Get-PngBytes $source $s) }
$source.Dispose()

$fs = [System.IO.File]::Create($out)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)                  # reserved
$bw.Write([UInt16]1)                  # type: icon
$bw.Write([UInt16]$sizes.Count)       # image count
$offset = 6 + 16 * $sizes.Count
foreach ($s in $sizes) {
    $data = $pngs[$s]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim)             # width (0 = 256)
    $bw.Write([byte]$dim)             # height
    $bw.Write([byte]0)                # palette count
    $bw.Write([byte]0)                # reserved
    $bw.Write([UInt16]1)              # planes
    $bw.Write([UInt16]32)             # bits per pixel
    $bw.Write([UInt32]$data.Length)   # bytes in resource
    $bw.Write([UInt32]$offset)        # offset
    $offset += $data.Length
}
foreach ($s in $sizes) { $bw.Write([byte[]]$pngs[$s]) }
$bw.Flush()
$bw.Close()
$fs.Close()

$icon = New-Object System.Drawing.Icon($out)
Write-Host ("sizes: {0}" -f ($sizes -join ','))
Write-Host ("output: {0} ({1} bytes), loaded={2}x{3}" -f $out, (Get-Item $out).Length, $icon.Width, $icon.Height)
$icon.Dispose()
