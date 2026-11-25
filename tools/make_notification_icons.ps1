# Regenerates Android notification icons (owner 2026-11-25).
#   powershell -File tools/make_notification_icons.ps1
#
# Small icon: Android renders ONLY the alpha channel. The old files were 100%
# opaque white, which is why the shade showed a white square. This draws the
# DropOff pin as a white-on-transparent silhouette with a transparent centre.
# Large icon: a real flat PNG of the DropOff logo (the old largeIcon resource
# was @mipmap/launcher_icon, an adaptive-icon XML that cannot be decoded as a
# bitmap and made the curtain fall back to a system icon labelled "System").
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$res = Join-Path $root 'app\android\app\src\main\res'
$logoPath = Join-Path $root 'app\assets\brand\dropoff_logo.png'

$sizes = [ordered]@{ mdpi = 24; hdpi = 36; xhdpi = 48; xxhdpi = 72; xxxhdpi = 96 }
$largeSizes = [ordered]@{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }

function New-Bitmap([int]$w, [int]$h) {
  $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  @($bmp, $g)
}

function Save-Png($bmp, $g, [string]$path) {
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "  $path"
}

# ---- small (status bar) icon: white silhouette, transparent everywhere else --
foreach ($d in $sizes.Keys) {
  $w = [int]$sizes[$d]; $h = $w
  $r = New-Bitmap $w $h
  $bmp = $r[0]; $g = $r[1]
  $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

  # Pin body = round head + tapered point. Overlapping fills form one glyph.
  $head = New-Object System.Drawing.Drawing2D.GraphicsPath
  $head.AddEllipse([float]($w * 0.10), [float]($h * 0.04), [float]($w * 0.80), [float]($h * 0.72))
  $g.FillPath($white, $head); $head.Dispose()

  $tip = New-Object System.Drawing.Drawing2D.GraphicsPath
  $tip.AddPolygon(@(
    (New-Object System.Drawing.PointF([float]($w * 0.15), [float]($h * 0.47))),
    (New-Object System.Drawing.PointF([float]($w * 0.85), [float]($h * 0.47))),
    (New-Object System.Drawing.PointF([float]($w * 0.50), [float]($h * 0.98)))
  ))
  $g.FillPath($white, $tip); $tip.Dispose()

  # Transparent parcel cut-out: a small diamond, the DropOff mark's centrepiece.
  # Graphics.Clear() ignores the clip region and wipes the WHOLE bitmap, so
  # punch the hole with SourceCopy compositing instead.
  $hole = New-Object System.Drawing.Drawing2D.GraphicsPath
  $hole.AddPolygon(@(
    (New-Object System.Drawing.PointF([float]($w * 0.50), [float]($h * 0.20))),
    (New-Object System.Drawing.PointF([float]($w * 0.72), [float]($h * 0.35))),
    (New-Object System.Drawing.PointF([float]($w * 0.50), [float]($h * 0.50))),
    (New-Object System.Drawing.PointF([float]($w * 0.28), [float]($h * 0.35)))
  ))
  $prev = $g.CompositingMode
  $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $g.FillPath([System.Drawing.Brushes]::Transparent, $hole)
  $g.CompositingMode = $prev
  $hole.Dispose(); $white.Dispose()

  Save-Png $bmp $g (Join-Path $res "drawable-$d\ic_stat_dropoff.png")
}

# ---- large (curtain / shade) icon: the actual DropOff logo ------------------
$src = [System.Drawing.Image]::FromFile($logoPath)
foreach ($d in $largeSizes.Keys) {
  $w = [int]$largeSizes[$d]
  $r = New-Bitmap $w $w
  $bmp = $r[0]; $g = $r[1]
  $g.DrawImage($src, 0, 0, $w, $w)
  Save-Png $bmp $g (Join-Path $res "drawable-$d\ic_notification_large.png")
}
$src.Dispose()
Write-Host 'done'
