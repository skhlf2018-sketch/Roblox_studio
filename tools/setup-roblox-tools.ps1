# 윈도우에서 로블록스 개발 도구(Rojo·Lune·Selene·StyLua)를 한 번에 받는 스크립트.
# 사용: powershell -ExecutionPolicy Bypass -File tools\setup-roblox-tools.ps1 [설치_폴더]
#   기본 설치 폴더: $env:LOCALAPPDATA\roblox-tools
param([string]$Dest = "$env:LOCALAPPDATA\roblox-tools")

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force "$Dest\bin" | Out-Null
New-Item -ItemType Directory -Force "$Dest\dl"  | Out-Null

$items = [ordered]@{
  rojo   = "https://github.com/rojo-rbx/rojo/releases/download/v7.5.1/rojo-7.5.1-windows-x86_64.zip"
  lune   = "https://github.com/lune-org/lune/releases/download/v0.10.4/lune-0.10.4-windows-x86_64.zip"
  selene = "https://github.com/Kampfkarren/selene/releases/download/0.29.0/selene-0.29.0-windows.zip"
  stylua = "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.3.1/stylua-windows-x86_64.zip"
}

foreach ($name in $items.Keys) {
  Write-Host ">> $name"
  $zip = "$Dest\dl\$name.zip"
  Invoke-WebRequest -Uri $items[$name] -OutFile $zip -UseBasicParsing
  Expand-Archive -Path $zip -DestinationPath "$Dest\bin" -Force
}

Write-Host ""
Write-Host "done. PATH에 추가:  `$env:PATH = `"$Dest\bin;`$env:PATH`""
& "$Dest\bin\rojo.exe"   --version
& "$Dest\bin\lune.exe"   --version
& "$Dest\bin\selene.exe" --version
& "$Dest\bin\stylua.exe" --version
