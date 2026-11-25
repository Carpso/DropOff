# DropOff marketing artwork generator (owner 2026-11-25).
# Produces: 8 WhatsApp-catalogue cards (1080x1080), 5 tagged QR codes,
# an A5 flyer (300 dpi) and a 1080x1920 status poster.
#
#   powershell -File tools/make_marketing_art.ps1
#
# Requires Windows (System.Drawing). QR codes come from the `qrcode` npm CLI
# installed under the opencode temp folder by tools/make_qr.ps1.

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$art  = Join-Path $root 'docs\marketing\art'
$cat  = Join-Path $art 'catalogue'
$qrd  = Join-Path $art 'qr'
$fly  = Join-Path $art 'flyer'
foreach ($d in @($art, $cat, $qrd, $fly)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

$logoPath = Join-Path $root 'app\assets\brand\dropoff_logo.png'

# ---- brand ---------------------------------------------------------------
$FOREST   = [System.Drawing.Color]::FromArgb(255, 14, 59, 50)
$FOREST_D = [System.Drawing.Color]::FromArgb(255, 7, 35, 29)
$FOREST_L = [System.Drawing.Color]::FromArgb(255, 28, 107, 82)
$AMBER    = [System.Drawing.Color]::FromArgb(255, 246, 183, 60)
$AMBER_S  = [System.Drawing.Color]::FromArgb(255, 255, 233, 190)
$INK      = [System.Drawing.Color]::FromArgb(255, 23, 34, 30)
$WHITE    = [System.Drawing.Color]::White
$MUTED    = [System.Drawing.Color]::FromArgb(255, 159, 181, 175)
$MUTED_D  = [System.Drawing.Color]::FromArgb(255, 126, 145, 140)
$SILVER   = [System.Drawing.Color]::FromArgb(255, 201, 211, 207)
$GOLD     = [System.Drawing.Color]::FromArgb(255, 232, 184, 75)
$PLAT     = [System.Drawing.Color]::FromArgb(255, 221, 230, 233)
$TEAL     = [System.Drawing.Color]::FromArgb(255, 47, 181, 138)

# ---- primitives ----------------------------------------------------------
function New-Font([double]$px, [string]$style = 'Regular') {
  $family = 'Segoe UI'
  $fs = [System.Drawing.FontStyle]::Regular
  switch ($style) {
    'Bold'     { $fs = [System.Drawing.FontStyle]::Bold }
    'SemiBold' { $family = 'Segoe UI Semibold' }
    'Italic'   { $fs = [System.Drawing.FontStyle]::Italic }
    'Black'    { $family = 'Segoe UI Black' }
  }
  $fam = New-Object System.Drawing.FontFamily($family)
  New-Object System.Drawing.Font($fam, [float]$px, $fs, [System.Drawing.GraphicsUnit]::Pixel)
}
function New-RoundPath([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc([float]$x, [float]$y, [float]$d, [float]$d, 180, 90)
  $p.AddArc([float]($x + $w - $d), [float]$y, [float]$d, [float]$d, 270, 90)
  $p.AddArc([float]($x + $w - $d), [float]($y + $h - $d), [float]$d, [float]$d, 0, 90)
  $p.AddArc([float]$x, [float]($y + $h - $d), [float]$d, [float]$d, 90, 90)
  $p.CloseFigure()
  $p
}
function Fill-Round($g, $brush, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $p = New-RoundPath $x $y $w $h $r
  $g.FillPath($brush, $p); $p.Dispose()
}
function New-Canvas([int]$w, [int]$h) {
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  @($bmp, $g)
}
function Paint-Background($g, [int]$w, [int]$h) {
  $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
  $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $FOREST, $FOREST_D, 90.0)
  $g.FillRectangle($grad, $rect); $grad.Dispose()

  # soft amber glow, bottom-right
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.AddEllipse([float]($w - 780), [float]($h - 700), 1100, 1000)
  $pg = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp)
  $pg.CenterColor = [System.Drawing.Color]::FromArgb(34, 246, 183, 60)
  $pg.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 246, 183, 60))
  $g.FillPath($pg, $gp)
  $pg.Dispose(); $gp.Dispose()

  # faint top-left depth
  $gp2 = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp2.AddEllipse(-500, -520, 1100, 1000)
  $pg2 = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp2)
  $pg2.CenterColor = [System.Drawing.Color]::FromArgb(26, 28, 107, 82)
  $pg2.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 28, 107, 82))
  $g.FillPath($pg2, $gp2)
  $pg2.Dispose(); $gp2.Dispose()
}
function Draw-Tracked($g, [string]$text, $font, $brush, [double]$x, [double]$y, [double]$tracking) {
  $cx = $x
  foreach ($ch in $text.ToCharArray()) {
    $s = [string]$ch
    $g.DrawString($s, $font, $brush, [float]$cx, [float]$y)
    $m = $g.MeasureString($s, $font)
    $cx += ($m.Width - 2) + $tracking
  }
  $cx - $x
}
function Split-Wrap($g, [string]$text, $font, [double]$maxW) {
  $words = $text -split '\s+'
  $lines = New-Object System.Collections.ArrayList
  $cur = ''
  foreach ($w in $words) {
    $try = if ($cur -eq '') { $w } else { "$cur $w" }
    $m = $g.MeasureString($try, $font)
    if ($m.Width -gt $maxW -and $cur -ne '') {
      [void]$lines.Add($cur); $cur = $w
    } else { $cur = $try }
  }
  if ($cur -ne '') { [void]$lines.Add($cur) }
  ,$lines
}
function Draw-Wrap($g, [string]$text, $font, $brush, [double]$x, [double]$y, [double]$maxW, [double]$lineH) {
  $lines = Split-Wrap $g $text $font $maxW
  $cy = $y
  foreach ($l in $lines) {
    $g.DrawString($l, $font, $brush, [float]$x, [float]$cy)
    $cy += $lineH
  }
  $cy
}
function Draw-Logo($g, [double]$x, [double]$y, [double]$size, [double]$radius) {
  $img = [System.Drawing.Image]::FromFile($logoPath)
  $path = New-RoundPath $x $y $size $size $radius
  $old = $g.Clip
  $g.SetClip($path)
  $g.DrawImage($img, [float]$x, [float]$y, [float]$size, [float]$size)
  $g.Clip = $old
  $path.Dispose(); $img.Dispose()
}
function Save-Png($bmp, $g, [string]$path) {
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "  $([System.IO.Path]::GetFileName($path))"
}

$PHONE  = '0968551110'
$WA     = 'wa.me/c/260968551110'

# ---- catalogue card ------------------------------------------------------
function New-CatalogueCard {
  param(
    [string]$File,
    [string]$Eyebrow,
    [string]$Title,
    [string]$Price,
    [string]$PriceNote,
    [string[]]$Bullets,
    [System.Drawing.Color]$Accent,
    [string]$FootNote = 'Promo pricing — rises within 3–6 months. Your current cycle keeps its rate.'
  )
  $W = 1080; $H = 1080
  $r = New-Canvas $W $H
  $bmp = $r[0]; $g = $r[1]
  Paint-Background $g $W $H

  # header row
  $fBrand = New-Font 26 'Bold'
  $bAmber = New-Object System.Drawing.SolidBrush($AMBER)
  $bMuted = New-Object System.Drawing.SolidBrush($MUTED)
  $tw = Draw-Tracked $g 'DROPOFF' $fBrand $bAmber 88 84 5.0
  $fDot = New-Font 26 'Bold'
  $g.DrawString('·', $fDot, $bMuted, [float](88 + $tw + 8), 84)
  $null = Draw-Tracked $g 'CARPSO SOLUTIONS' $fBrand $bMuted (88 + $tw + 34) 84 5.0
  Draw-Logo $g ($W - 88 - 124) 66 124 30

  # hairline
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 28, 107, 82), 2)
  $g.DrawLine($pen, 88, 244, ($W - 88), 244)

  # eyebrow
  $fEye = New-Font 24 'Bold'
  $bAccent = New-Object System.Drawing.SolidBrush($Accent)
  $null = Draw-Tracked $g $Eyebrow.ToUpper() $fEye $bAccent 88 292 6.0

  # title
  $fTitle = New-Font 88 'Bold'
  $bWhite = New-Object System.Drawing.SolidBrush($WHITE)
  $g.DrawString($Title, $fTitle, $bWhite, [float]88, [float]336)

  # price
  $fPrice = New-Font 168 'Bold'
  $g.DrawString($Price, $fPrice, $bAccent, [float]80, [float]440)
  $fNote = New-Font 34 'SemiBold'
  $g.DrawString($PriceNote, $fNote, $bMuted, [float]92, [float]640)

  # bullets
  $fBul = New-Font 31 'Regular'
  $bBul = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 245, 255, 252))
  $y = 716
  foreach ($b in $Bullets) {
    $g.FillEllipse($bAccent, 90, ($y + 10), 14, 14)
    $yy = Draw-Wrap $g $b $fBul $bBul 126 $y 840 40
    $y = [Math]::Max($yy, $y + 40) + 12
  }

  # footnote
  $fFine = New-Font 21 'Regular'
  $bFine = New-Object System.Drawing.SolidBrush($MUTED_D)
  Draw-Wrap $g $FootNote $fFine $bFine 88 906 900 28 | Out-Null

  # footer bar
  $pen2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 255, 255, 255), 1)
  $g.DrawLine($pen2, 88, 982, ($W - 88), 982)
  $bInk = New-Object System.Drawing.SolidBrush($INK)
  Fill-Round $g $bAmber 88 1006 268 52 26
  $fPh = New-Font 27 'Bold'
  $g.DrawString($PHONE, $fPh, $bInk, [float]122, [float]1016)
  $fWa = New-Font 23 'Regular'
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Far
  $rect = New-Object System.Drawing.RectangleF(0, 1006, ($W - 88), 52)
  $g.DrawString($WA, $fWa, $bMuted, $rect, $sf)

  Save-Png $bmp $g (Join-Path $cat $File)
}

Write-Host '== catalogue cards =='
New-CatalogueCard -File '01-daily-rider.png' -Eyebrow 'Plan · 24 hours' -Title 'Daily Rider' -Price 'K49' -PriceNote '1 parcel · valid today' -Accent $AMBER -Bullets @(
  'One parcel, one trip. Valid 24 hours.',
  'Rider collects from your door.',
  'No per-trip rider fee inside the plan.'
) -FootNote 'Promo pricing — rises within 3–6 months. Your current cycle keeps its rate.'

New-CatalogueCard -File '02-silver.png' -Eyebrow 'Plan · 30 days' -Title 'Silver' -Price 'K250' -PriceNote '10 trips · 30 days' -Accent $SILVER -Bullets @(
  '10 trips in 30 days.',
  'No per-trip rider fee inside the cap.',
  'Pickup windows three times a day.'
)

New-CatalogueCard -File '03-gold.png' -Eyebrow 'Plan · 30 days' -Title 'Gold' -Price 'K500' -PriceNote '25 trips · 30 days' -Accent $GOLD -Bullets @(
  '25 trips in 30 days.',
  'No per-trip rider fee inside the cap.',
  'Best for shops sending daily.'
)

New-CatalogueCard -File '04-platinum.png' -Eyebrow 'Plan · 30 days' -Title 'Platinum' -Price 'K750' -PriceNote '50 trips · 30 days' -Accent $PLAT -Bullets @(
  '50 trips in 30 days.',
  'No per-trip rider fee inside the cap.',
  'For high-volume sellers.'
)

New-CatalogueCard -File '05-weekly-sprint.png' -Eyebrow 'Plan · 7 days' -Title 'Weekly Sprint' -Price 'K399' -PriceNote '20 parcels · 7 days' -Accent $TEAL -Bullets @(
  '20 parcels in 7 days.',
  'No per-trip rider fee inside the plan.',
  'Starts the moment you activate.'
)

New-CatalogueCard -File '06-pickup-booking.png' -Eyebrow 'Service · pay as you go' -Title 'Pickup booking' -Price 'From K49' -PriceNote 'Quoted in the app' -Accent $AMBER -Bullets @(
  'Rider collects from your door.',
  'Every item photographed and stamped.',
  'Repay only the exact receipt.'
) -FootNote 'Courier fares are quoted at the counter. No depot queue fee. Reply BOOK to start.'

New-CatalogueCard -File '07-last-mile.png' -Eyebrow 'Service · depot to door' -Title 'Last-mile collection' -Price 'From K49' -PriceNote 'Quoted in the app' -Accent $TEAL -Bullets @(
  'Parcel already at the courier depot.',
  'We collect it and deliver to the door.',
  'Recipients confirm receipt in-app.'
) -FootNote 'Courier fares are quoted at the counter. No depot queue fee. Reply COLLECT to start.'

New-CatalogueCard -File '08-business-account.png' -Eyebrow 'Service · bulk sending' -Title 'Business account' -Price 'From K250' -PriceNote 'Per month, per plan' -Accent $GOLD -Bullets @(
  'For 10+ parcels a week.',
  'Named account contact and invoicing.',
  'Plans from K250 up to K750.'
) -FootNote 'Promo pricing — rises within 3–6 months. Reply BUSINESS to start.'

# ---- QR codes ------------------------------------------------------------
Write-Host '== QR codes =='
$qrNode = 'C:\Users\User\AppData\Local\Temp\opencode\qrgen'
$qrCli  = Join-Path $qrNode 'node_modules\qrcode\bin\qrcode'

$codes = @(
  @{ n = 'qr-flier.png';  t = 'https://wa.me/260968551110?text=FLYER' },
  @{ n = 'qr-tiktok.png'; t = 'https://wa.me/260968551110?text=SEND100-TT' },
  @{ n = 'qr-facebook.png'; t = 'https://wa.me/260968551110?text=SEND100-FB' },
  @{ n = 'qr-status.png'; t = 'https://wa.me/260968551110?text=SEND100-STATUS' },
  @{ n = 'qr-rider.png';  t = 'https://wa.me/260968551110?text=RIDER' }
)
foreach ($c in $codes) {
  $out = Join-Path $qrd $c.n
  & node $qrCli -o $out -w 1200 -e H -d '#0E3B32' -l '#FFFFFF' --margin 2 $c.t 2>&1 | Out-Null
  if (Test-Path $out) { Write-Host "  $($c.n)" } else { Write-Host "  !! failed: $($c.n)" }
}

# ---- A5 flyer (300 dpi) --------------------------------------------------
Write-Host '== flyer =='
function New-Flyer {
  param([string]$File, [int]$W, [int]$H, [double]$Scale = 1.0)
  $r = New-Canvas $W $H
  $bmp = $r[0]; $g = $r[1]
  Paint-Background $g $W $H

  $m = 110 * $Scale
  $inner = $W - (2 * $m)

  Draw-Logo $g $m (90 * $Scale) (260 * $Scale) (64 * $Scale)
  $fBrand = New-Font (26 * $Scale) 'Bold'
  $bMuted = New-Object System.Drawing.SolidBrush($MUTED)
  $bAmber = New-Object System.Drawing.SolidBrush($AMBER)
  $bWhite = New-Object System.Drawing.SolidBrush($WHITE)
  $null = Draw-Tracked $g 'CARPSO SOLUTIONS' $fBrand $bMuted ($m + (292 * $Scale)) (110 * $Scale) 6.0
  $null = Draw-Tracked $g 'DROPOFF' $fBrand $bAmber ($m + (292 * $Scale)) (152 * $Scale) 6.0

  # headline
  $fH1 = New-Font (128 * $Scale) 'Bold'
  $y = 470 * $Scale
  $g.DrawString('STOP', $fH1, $bWhite, [float]$m, [float]$y)
  $g.DrawString('QUEUEING.', $fH1, $bWhite, [float]$m, [float]($y + (140 * $Scale)))
  $g.DrawString('START', $fH1, $bAmber, [float]$m, [float]($y + (290 * $Scale)))
  $g.DrawString('SENDING.', $fH1, $bAmber, [float]$m, [float]($y + (430 * $Scale)))

  $fSub = New-Font (42 * $Scale) 'Regular'
  $bSub = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 235, 245, 241))
  $yy = Draw-Wrap $g 'A DropOff rider collects from your door, photographs every item, and carries it to the courier for you.' $fSub $bSub $m (1082 * $Scale) $inner (58 * $Scale)

  # three steps
  $fStep = New-Font (34 * $Scale) 'SemiBold'
  $steps = @(
    'Book a pickup in the app — choose 05:30–07:30, 10:00–11:30 or 14:00–15:30.',
    'The rider photographs every item and carries it to the courier counter.',
    'Repay only the exact photographed receipt — no depot queue fee.'
  )
  $sy = $yy + (40 * $Scale)
  $i = 1
  foreach ($s in $steps) {
    $bInk = New-Object System.Drawing.SolidBrush($INK)
    $g.FillEllipse($bAmber, [float]$m, [float]$sy, [float](46 * $Scale), [float](46 * $Scale))
    $fNum = New-Font (26 * $Scale) 'Bold'
    $g.DrawString([string]$i, $fNum, $bInk, [float]($m + (15 * $Scale)), [float]($sy + (6 * $Scale)))
    $ey = Draw-Wrap $g $s $fStep $bSub ($m + (70 * $Scale)) $sy ($inner - (70 * $Scale)) (46 * $Scale)
    $sy = [Math]::Max($ey, $sy + (46 * $Scale)) + (22 * $Scale)
    $i++
  }

  # offer panel
  $py = $sy + (30 * $Scale)
  $ph = 210 * $Scale
  Fill-Round $g $bAmber $m $py $inner $ph (34 * $Scale)
  $bInk2 = New-Object System.Drawing.SolidBrush($INK)
  $fOff1 = New-Font (30 * $Scale) 'Bold'
  $null = Draw-Tracked $g 'FIRST 100 SENDERS' $fOff1 $bInk2 ($m + (40 * $Scale)) ($py + (30 * $Scale)) 4.0
  $fOff2 = New-Font (62 * $Scale) 'Bold'
  $g.DrawString('1 free parcel today', $fOff2, $bInk2, [float]($m + (36 * $Scale)), [float]($py + (72 * $Scale)))
  $fOff3 = New-Font (34 * $Scale) 'SemiBold'
  $g.DrawString('Use code SEND100 in the app', $fOff3, $bInk2, [float]($m + (38 * $Scale)), [float]($py + (150 * $Scale)))

  # QR block
  $qy = $py + $ph + (54 * $Scale)
  $qs = 420 * $Scale
  $qrImg = [System.Drawing.Image]::FromFile((Join-Path $qrd 'qr-flier.png'))
  $bWhiteS = New-Object System.Drawing.SolidBrush($WHITE)
  Fill-Round $g $bWhiteS $m $qy ($qs + (44 * $Scale)) ($qs + (44 * $Scale)) (30 * $Scale)
  $g.DrawImage($qrImg, [float]($m + (22 * $Scale)), [float]($qy + (22 * $Scale)), [float]$qs, [float]$qs)
  $qrImg.Dispose()

  $tx = $m + $qs + (80 * $Scale)
  $fScan = New-Font (34 * $Scale) 'SemiBold'
  $g.DrawString('Scan to chat', $fScan, $bSub, [float]$tx, [float]($qy + (30 * $Scale)))
  $g.DrawString('on WhatsApp', $fScan, $bSub, [float]$tx, [float]($qy + (74 * $Scale)))
  $fPh = New-Font (74 * $Scale) 'Bold'
  $g.DrawString($PHONE, $fPh, $bAmber, [float]$tx, [float]($qy + (150 * $Scale)))
  $fWa = New-Font (28 * $Scale) 'Regular'
  $g.DrawString('wa.me/260968551110', $fWa, $bMuted, [float]$tx, [float]($qy + (250 * $Scale)))
  $fApp = New-Font (28 * $Scale) 'SemiBold'
  $g.DrawString('dropoff.carpsosolutions.store', $fApp, $bSub, [float]$tx, [float]($qy + (300 * $Scale)))
  $fCities = New-Font (26 * $Scale) 'Regular'
  $g.DrawString('Lusaka  ·  Ndola  ·  Kitwe', $fCities, $bMuted, [float]$tx, [float]($qy + (352 * $Scale)))

  # footer — anchored so the fine print can never be clipped
  $fFine = New-Font (24 * $Scale) 'Regular'
  $bFine = New-Object System.Drawing.SolidBrush($MUTED_D)
  $fineText = 'Courier fares are quoted at the counter — we never invent a price. You repay only the photographed receipt. Plan prices are promotional and rise within 3–6 months; your current cycle keeps its rate. Cover is quoted protection, not insurance.'
  $fineLines = Split-Wrap $g $fineText $fFine $inner
  $fineLineH = 32 * $Scale
  $fineH = $fineLines.Count * $fineLineH
  $fy = $H - ($fineH + (170 * $Scale))
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 255, 255, 255), 1)
  $g.DrawLine($pen, $m, $fy, ($W - $m), $fy)
  $fSlog = New-Font (36 * $Scale) 'Bold'
  $null = Draw-Tracked $g 'WE CARRY IT TO THE COURIER' $fSlog $bAmber $m ($fy + (26 * $Scale)) 5.0
  Draw-Wrap $g $fineText $fFine $bFine $m ($fy + (86 * $Scale)) $inner $fineLineH | Out-Null

  Save-Png $bmp $g (Join-Path $fly $File)
}

New-Flyer -File 'dropoff-flyer-a5-300dpi.png' -W 1748 -H 2480 -Scale 1.0
New-Flyer -File 'dropoff-status-1080x1920.png' -W 1080 -H 1920 -Scale 0.735

Write-Host '== done =='
