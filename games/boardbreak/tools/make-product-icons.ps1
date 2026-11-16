# BoardBreak Robux product icons (512x512 PNG) -> games\boardbreak\assets\product-icons\<key>.png
# Usage: powershell -ExecutionPolicy Bypass -File games\boardbreak\tools\make-product-icons.ps1 [key ...]
# (ASCII only on purpose: Windows PowerShell 5.1 misreads UTF-8 files without BOM. Korean text is built from char codes.)
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "assets\product-icons"
New-Item -ItemType Directory -Force $out | Out-Null
$script:only = @($args)

$POWER = [string][char]0xD798                                    # him (power)
$MONEY = ([string][char]0xB3C8) + " " + [char]0xC601 + [char]0xC6D0 + [char]0xD788  # don yeong-won-hi (money forever)

function New-Icon([string]$key, [string]$big, [string]$small, [int[]]$top, [int[]]$bottom) {
	if ($script:only.Count -gt 0 -and $script:only -notcontains $key) { return }
	$size = 512
	$bmp = New-Object System.Drawing.Bitmap $size, $size
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
	$rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
	$c1 = [System.Drawing.Color]::FromArgb($top[0], $top[1], $top[2])
	$c2 = [System.Drawing.Color]::FromArgb($bottom[0], $bottom[1], $bottom[2])
	$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $c1, $c2, 90
	$g.FillRectangle($brush, $rect)
	$glow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(45, 255, 255, 255))
	$g.FillEllipse($glow, 56, 40, 400, 400)
	$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), 14
	$g.DrawRectangle($pen, 7, 7, $size - 14, $size - 14)

	$fmt = New-Object System.Drawing.StringFormat
	$fmt.Alignment = [System.Drawing.StringAlignment]::Center
	$fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
	$bigSize = if ($big.Length -le 2) { 190 } elseif ($big.Length -le 3) { 160 } elseif ($big.Length -le 4) { 128 } else { 104 }
	$fontBig = New-Object System.Drawing.Font "Malgun Gothic", $bigSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
	$fontSmall = New-Object System.Drawing.Font "Malgun Gothic", 66, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
	$shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, 0, 0, 0))
	$white = [System.Drawing.Brushes]::White
	$g.DrawString($big, $fontBig, $shadow, (New-Object System.Drawing.RectangleF 7, 68, $size, 290), $fmt)
	$g.DrawString($big, $fontBig, $white, (New-Object System.Drawing.RectangleF 0, 60, $size, 290), $fmt)
	$g.DrawString($small, $fontSmall, $shadow, (New-Object System.Drawing.RectangleF 5, 365, $size, 110), $fmt)
	$g.DrawString($small, $fontSmall, $white, (New-Object System.Drawing.RectangleF 0, 360, $size, 110), $fmt)
	$g.Dispose()
	$bmp.Save((Join-Path $out "$key.png"), [System.Drawing.Imaging.ImageFormat]::Png)
	$bmp.Dispose()
}

# Power multiplier game passes (red -> dark red, a little different per step so every file is unique)
$i = 0
foreach ($m in 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048) {
	New-Icon "power_$m" "x$m" $POWER @((255 - $i * 4), (90 + $i * 6), (60 + $i * 3)) @((190 - $i * 5), (30 + $i * 2), (40 + $i * 6))
	$i++
}
# Money x2 game pass (green)
New-Icon "money_2" "x2" $MONEY @(90, 210, 110) @(20, 130, 70)

Get-ChildItem $out -Filter *.png | Measure-Object | ForEach-Object { "icons: $($_.Count) in $out" }
