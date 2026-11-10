# 로벅스 상품 아이콘 36개 만들기 (512x512 PNG) — assets\product-icons\<key>.png
# 쓰는 법: powershell -ExecutionPolicy Bypass -File tools\make-product-icons.ps1
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "assets\product-icons"
New-Item -ItemType Directory -Force $out | Out-Null

function New-Icon([string]$key, [string]$big, [string]$small, [int[]]$top, [int[]]$bottom) {
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
	# 밝은 동그라미
	$glow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(45, 255, 255, 255))
	$g.FillEllipse($glow, 56, 40, 400, 400)
	# 테두리
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
	$bigRect = New-Object System.Drawing.RectangleF 0, 60, $size, 290
	$bigShadow = New-Object System.Drawing.RectangleF 7, 68, $size, 290
	$smallRect = New-Object System.Drawing.RectangleF 0, 360, $size, 110
	$smallShadow = New-Object System.Drawing.RectangleF 5, 365, $size, 110
	$g.DrawString($big, $fontBig, $shadow, $bigShadow, $fmt)
	$g.DrawString($big, $fontBig, $white, $bigRect, $fmt)
	$g.DrawString($small, $fontSmall, $shadow, $smallShadow, $fmt)
	$g.DrawString($small, $fontSmall, $white, $smallRect, $fmt)
	$g.Dispose()
	$bmp.Save((Join-Path $out "$key.png"), [System.Drawing.Imaging.ImageFormat]::Png)
	$bmp.Dispose()
}

# 스피드 배수 (게임패스) — 주황
foreach ($m in 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048) {
	New-Icon "boost_$m" "x$m" "스피드" @(255, 170, 40) @(230, 80, 20)
}
# 코인 2배 (게임패스) — 초록
New-Icon "money_pass" "x2" "코인 영원히" @(90, 210, 110) @(20, 130, 70)
# 러닝머신 레벨 (개발자 상품) — 파랑
foreach ($l in 1..20) {
	New-Icon "tskip_$l" "Lv$l" "러닝머신" @(80, 170, 255) @(40, 80, 200)
}
# 코인 (개발자 상품) — 노랑
New-Icon "coins_1m" "1M" "코인" @(255, 215, 70) @(225, 150, 20)
New-Icon "coins_1b" "1B" "코인" @(255, 215, 70) @(225, 150, 20)
# 속도 (개발자 상품) — 빨강
New-Icon "speed_10m" "10M" "속도" @(255, 110, 110) @(200, 40, 60)
New-Icon "speed_100m" "100M" "속도" @(255, 110, 110) @(200, 40, 60)

(Get-ChildItem $out -Filter *.png | Measure-Object).Count
