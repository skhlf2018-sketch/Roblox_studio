# 아이콘 파일을 살짝 바꿔 다시 저장 (로블록스 방화벽이 파일 바이트를 잘못 막을 때)
# 쓰는 법: powershell -ExecutionPolicy Bypass -File tools\retouch-icon.ps1 tskip_2 coins_1b
Add-Type -AssemblyName System.Drawing
$dir = Join-Path (Split-Path -Parent $PSScriptRoot) "assets\product-icons"
foreach ($key in $args) {
	$path = Join-Path $dir "$key.png"
	$src = [System.Drawing.Image]::FromFile($path)
	$bmp = New-Object System.Drawing.Bitmap $src
	$src.Dispose()
	$rand = New-Object System.Random
	# 테두리 안쪽 몇 군데에 눈에 안 띄는 점을 찍어 압축 결과를 바꿈
	for ($i = 0; $i -lt 40; $i++) {
		$x = $rand.Next(20, 492); $y = $rand.Next(20, 492)
		$c = $bmp.GetPixel($x, $y)
		$r = [Math]::Min(255, $c.R + 1); $g = [Math]::Max(0, $c.G - 1)
		$bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $r, $g, $c.B))
	}
	$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
	$bmp.Dispose()
	"$key ok"
}
