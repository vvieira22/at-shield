# Compose WiX dialog bitmaps from brand assets.
# dialog.bmp 493x312 (WixUI dialog units 370x234) · banner.bmp 493x58 (370x44)
param(
  [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $RepoRoot 'installer\bitmaps'
$iconPath = Join-Path $RepoRoot 'apps\at_shield\assets\icon.png'
$heroPath = Join-Path $outDir 'hero.png'
$dialogPath = Join-Path $outDir 'dialog.bmp'
$bannerPath = Join-Path $outDir 'banner.bmp'

if (-not (Test-Path -LiteralPath $iconPath)) {
  throw "missing icon: $iconPath"
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function New-Bmp([int]$W, [int]$H) {
  New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
}

function Save-Bmp([System.Drawing.Bitmap]$Bmp, [string]$Path) {
  $Bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Bmp)
}

$black = [System.Drawing.Color]::FromArgb(13, 13, 13)
$cream = [System.Drawing.Color]::FromArgb(247, 244, 240)
$ember = [System.Drawing.Color]::FromArgb(229, 30, 37)
$ink = [System.Drawing.Color]::FromArgb(244, 244, 245)
$splitX = 176

# --- dialog ---
$dialog = New-Bmp 493 312
$g = [System.Drawing.Graphics]::FromImage($dialog)
$g.SmoothingMode = 'HighQuality'
$g.InterpolationMode = 'HighQualityBicubic'
$g.PixelOffsetMode = 'HighQuality'
$g.Clear($black)
$g.FillRectangle((New-Object System.Drawing.SolidBrush $cream), $splitX, 0, 493 - $splitX, 312)

if (Test-Path -LiteralPath $heroPath) {
  $hero = [System.Drawing.Image]::FromFile($heroPath)
  try {
    # Cover the left panel, crop toward the brighter core.
    $srcW = [Math]::Max(1, [int]($hero.Height * ($splitX / 312.0)))
    $srcX = [Math]::Max(0, [int](($hero.Width - $srcW) / 2))
    $g.DrawImage($hero,
      (New-Object System.Drawing.Rectangle 0, 0, $splitX, 312),
      (New-Object System.Drawing.Rectangle $srcX, 0, $srcW, $hero.Height),
      [System.Drawing.GraphicsUnit]::Pixel)
  } finally { $hero.Dispose() }
}

$icon = [System.Drawing.Image]::FromFile($iconPath)
try {
  $iconSize = 118
  $ix = [int](($splitX - $iconSize) / 2)
  $iy = [int]((312 - $iconSize) / 2)
  $g.DrawImage($icon, $ix, $iy, $iconSize, $iconSize)
} finally { $icon.Dispose() }

$g.FillRectangle((New-Object System.Drawing.SolidBrush $ember), $splitX, 0, 2, 312)
$g.Dispose()
Save-Bmp $dialog $dialogPath
$dialog.Dispose()

# --- banner ---
$banner = New-Bmp 493 58
$bg = [System.Drawing.Graphics]::FromImage($banner)
$bg.SmoothingMode = 'HighQuality'
$bg.InterpolationMode = 'HighQualityBicubic'
$bg.Clear($black)
$icon = [System.Drawing.Image]::FromFile($iconPath)
try {
  $bg.DrawImage($icon, 12, 7, 44, 44)
} finally { $icon.Dispose() }

$font = New-Object System.Drawing.Font 'Segoe UI', 13, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$brush = New-Object System.Drawing.SolidBrush $ink
$bg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$bg.DrawString('A.T. SHIELD', $font, $brush, 64, 18)
$bg.FillRectangle((New-Object System.Drawing.SolidBrush $ember), 0, 56, 493, 2)
$font.Dispose(); $brush.Dispose(); $bg.Dispose()
Save-Bmp $banner $bannerPath
$banner.Dispose()

function Assert-Bmp([string]$Path, [int]$W, [int]$H) {
  $img = [System.Drawing.Image]::FromFile($Path)
  try {
    if ($img.Width -ne $W -or $img.Height -ne $H) {
      throw "bad size $Path ($($img.Width)x$($img.Height), expected ${W}x${H})"
    }
  } finally { $img.Dispose() }
}

Assert-Bmp $dialogPath 493 312
Assert-Bmp $bannerPath 493 58
Write-Host "OK dialog.bmp 493x312"
Write-Host "OK banner.bmp 493x58"
