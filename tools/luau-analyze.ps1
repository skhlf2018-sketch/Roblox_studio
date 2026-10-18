# Luau 타입 검사 (--!strict) 도구: 설치 + src 전체 검사 + 결과 정리
#
# 사용 (저장소 아무 데서나):
#   powershell -ExecutionPolicy Bypass -File tools\luau-analyze.ps1                 # 설치(처음 한 번) + src 검사
#   powershell -ExecutionPolicy Bypass -File tools\luau-analyze.ps1 -InstallOnly    # 도구만 받기
#   powershell -ExecutionPolicy Bypass -File tools\luau-analyze.ps1 -Ref HEAD       # 커밋된 코드만 검사 (작업 중인 파일 무시)
#   powershell -ExecutionPolicy Bypass -File tools\luau-analyze.ps1 -Path src\server -Report build\typecheck.md
#
# 왜 luau-lsp 인가:
#   luau-analyze.exe(luau-lang/luau 릴리스)는 --defs 옵션이 없어서 로블록스 전역(game, Instance.new ...)과
#   Rojo 경로 require(script.Parent.X) 를 못 읽습니다 (받아서 확인함). 같은 Luau 엔진을 쓰면서
#   --definitions(로블록스 전역 타입) + --sourcemap(Rojo 트리) 을 받는 `luau-lsp analyze` 로 검사합니다.
#   luau-analyze.exe 도 같이 설치해 둡니다 (순수 Luau 파일 빠른 검사용: luau-analyze --mode=strict 파일).
#
# 설치 위치: $Dest\luau\{analyze,lsp,defs}   (기본 $env:LOCALAPPDATA\roblox-tools — setup-roblox-tools.ps1 과 같은 폴더)
# rojo.exe 는 setup-roblox-tools.ps1 로 먼저 받아 두세요 ($Dest\bin 또는 PATH).
#
# 결과 분류:
#   type    진짜 타입 오류 후보 (종료 코드 1)   ← 사람이 읽고 "진짜"인지 "검사기 한계"인지 판단해야 함
#   require require 해석 실패 (환경 문제) — 따로 센다, 종료 코드에 영향 없음
#   lint    경고 (DeprecatedApi 등)
#   syntax  문법 오류 (종료 코드 1)
#
# 한글 경로 주의: luau-lsp 는 한글이 든 경로를 못 읽습니다. 저장소 경로에 한글이 있으면
#   $Dest\repo-link 에 ASCII 이름의 바로가기(junction) 를 만들어 거기서 실행합니다 (관리자 권한 필요 없음).

param(
	[string]$Dest = "$env:LOCALAPPDATA\roblox-tools",
	[string[]]$Path = @("src"),
	[string]$Ref = "",
	[string]$Report = "",
	[string]$Raw = "",
	[switch]$InstallOnly,
	[switch]$NoFail
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# 버전은 여기 고정 (올리려면 숫자만 바꾸고 다시 실행)
$LUAU_VERSION = "0.743"
$LSP_VERSION = "1.70.1"
$LUAU_ZIP = "https://github.com/luau-lang/luau/releases/download/$LUAU_VERSION/luau-windows.zip"
$LSP_ZIP = "https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LSP_VERSION/luau-lsp-win64.zip"
# 일반 스크립트용 로블록스 전역 타입 (RobloxScriptSecurity 같은 내부 API 는 빠진 버전)
$DEFS_URL = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$LSP_VERSION/scripts/globalTypes.None.d.luau"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$luauDir = Join-Path $Dest "luau"
$analyzeExe = Join-Path $luauDir "analyze\luau-analyze.exe"
$lspExe = Join-Path $luauDir "lsp\luau-lsp.exe"
$defsFile = Join-Path $luauDir "defs\globalTypes.None.d.luau"

function Get-File($url, $out) {
	Write-Host "  받는 중: $url"
	Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

function Install-LuauTools {
	New-Item -ItemType Directory -Force (Join-Path $luauDir "dl"), (Join-Path $luauDir "analyze"), (Join-Path $luauDir "lsp"), (Join-Path $luauDir "defs") | Out-Null
	if (-not (Test-Path $analyzeExe)) {
		Write-Host ">> luau-analyze $LUAU_VERSION"
		$zip = Join-Path $luauDir "dl\luau-windows.zip"
		Get-File $LUAU_ZIP $zip
		Expand-Archive -Path $zip -DestinationPath (Join-Path $luauDir "analyze") -Force
	}
	if (-not (Test-Path $lspExe)) {
		Write-Host ">> luau-lsp $LSP_VERSION"
		$zip = Join-Path $luauDir "dl\luau-lsp-win64.zip"
		Get-File $LSP_ZIP $zip
		Expand-Archive -Path $zip -DestinationPath (Join-Path $luauDir "lsp") -Force
	}
	if (-not (Test-Path $defsFile)) {
		Write-Host ">> 로블록스 전역 타입 (globalTypes.None.d.luau)"
		Get-File $DEFS_URL $defsFile
	}
}

function Find-Rojo {
	$candidate = Join-Path $Dest "bin\rojo.exe"
	if (Test-Path $candidate) { return $candidate }
	$cmd = Get-Command rojo -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	throw "rojo.exe 를 못 찾았어요. 먼저 tools\setup-roblox-tools.ps1 을 실행하거나 -Dest 로 rojo 가 있는 폴더(bin 의 부모)를 알려 주세요."
}

function Find-Git {
	$cmd = Get-Command git -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	$guess = "C:\Program Files\Git\cmd\git.exe"
	if (Test-Path $guess) { return $guess }
	throw "git 을 못 찾았어요 (-Ref 를 쓰려면 필요)."
}

# PowerShell 5.1 의 Start-Process 는 공백이 든 인자를 알아서 따옴표로 안 묶어 줌
function Quote($s) {
	if ($s -match '\s') { return '"' + $s + '"' }
	return $s
}

Write-Host "== Luau 타입 검사 도구 =="
Install-LuauTools
Write-Host "  luau-analyze : $analyzeExe"
Write-Host "  luau-lsp     : $lspExe"
Write-Host "  전역 타입    : $defsFile"
if ($InstallOnly) { return }

# 검사할 코드의 위치 (작업 폴더 또는 커밋 스냅샷)
$root = $repoRoot
$label = "작업 폴더"
if ($Ref -ne "") {
	$git = Find-Git
	$snap = Join-Path $Dest "snapshot"
	if (Test-Path $snap) { Remove-Item -Recurse -Force $snap }
	New-Item -ItemType Directory -Force $snap | Out-Null
	$tar = Join-Path $Dest "snapshot.tar"
	& $git -C $repoRoot archive $Ref src default.project.json .luaurc -o $tar
	if ($LASTEXITCODE -ne 0) { throw "git archive 실패 ($Ref)" }
	& tar -xf $tar -C $snap
	$hash = (& $git -C $repoRoot rev-parse --short $Ref).Trim()
	$root = $snap
	$label = "커밋 $hash ($Ref)"
}

# 한글 등 ASCII 아닌 글자가 경로에 있으면 바로가기(junction)로 우회
$runRoot = $root
if ($root -match '[^\x00-\x7F]') {
	$link = Join-Path $Dest "repo-link"
	if (Test-Path $link) { [System.IO.Directory]::Delete($link) }
	New-Item -ItemType Junction -Path $link -Target $root | Out-Null
	$runRoot = $link
	Write-Host "  (경로에 한글이 있어 $link 바로가기로 실행)"
}

$rojo = Find-Rojo
$sourcemap = Join-Path $Dest "sourcemap.json"
Push-Location $runRoot
try {
	& $rojo sourcemap default.project.json --output $sourcemap | Out-Null
	if ($LASTEXITCODE -ne 0) { throw "rojo sourcemap 실패" }

	$outFile = Join-Path $Dest "analyze_out.txt"
	$errFile = Join-Path $Dest "analyze_err.txt"
	$argList = @("analyze", "--sourcemap", (Quote $sourcemap), "--definitions", (Quote $defsFile), "--base-luaurc", ".luaurc", "--formatter", "plain") + ($Path | ForEach-Object { Quote $_ })
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$proc = Start-Process -FilePath $lspExe -ArgumentList $argList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
	$sw.Stop()
	if ($Raw -ne "") { Copy-Item $outFile $Raw -Force }
}
finally {
	Pop-Location
}

# ---- 결과 읽기 ----------------------------------------------------------
$rx = '^(?<file>(?:[A-Za-z]:\\|src[\\/]|tests[\\/]).*?\.luau)(?: \[[^\]]*\])?:(?<line>\d+):(?<col>\d+)-(?<col2>\d+): \((?<code>\w+)\) (?<kind>\w+): (?<msg>.*)$'
$diags = New-Object System.Collections.Generic.List[object]
$seen = @{}
$cur = $null
foreach ($ln in (Get-Content $outFile -Encoding UTF8)) {
	if ($ln -match $rx) {
		# 절대 경로 → 저장소 기준 상대 경로 (대소문자·슬래시 모양이 달라도 맞게)
		$f = $Matches.file.Replace("\", "/")
		$prefix = $runRoot.Replace("\", "/").TrimEnd("/") + "/"
		if ($f.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $f = $f.Substring($prefix.Length) }
		$kind = $Matches.kind
		$msg = $Matches.msg
		$category = "lint"
		if ($kind -eq "TypeError") {
			if ($msg -match "(?i)unknown require|cannot find module|could not resolve|failed to resolve|not found in table 'Instance'") { $category = "require" } else { $category = "type" }
		}
		elseif ($kind -match "Syntax") { $category = "syntax" }
		$key = "$f|$($Matches.line)|$($Matches.col)|$kind|$msg"
		if ($seen.ContainsKey($key)) { $cur = $null; continue }
		$cur = [pscustomobject]@{ File = $f; Line = [int]$Matches.line; Kind = $kind; Category = $category; Message = $msg; Detail = "" }
		$seen[$key] = $true
		$diags.Add($cur)
	}
	elseif ($cur) {
		$cur.Detail += " ~~ " + $ln.Trim()
	}
}

# 여러 줄짜리 오류 글은 한 줄로 줄여서 보여 줌 (Expected this to be ... but got ... 가 잘리지 않게)
foreach ($d in $diags) {
	$one = ($d.Message + " " + $d.Detail) -replace '\s*~~\s*', ' ' -replace '\s+', ' '
	if ($one.Length -gt 210) { $one = $one.Substring(0, 207) + "..." }
	$d | Add-Member -NotePropertyName Summary -NotePropertyValue $one.Trim()
}

$byCat = @{ type = 0; require = 0; lint = 0; syntax = 0 }
foreach ($d in $diags) { $byCat[$d.Category] += 1 }

Write-Host ""
Write-Host "== 결과 ($label, luau-lsp $LSP_VERSION, $([math]::Round($sw.Elapsed.TotalSeconds, 1))초) =="
if ($diags.Count -eq 0) {
	Write-Host "  오류/경고 없음"
}
else {
	$diags | Group-Object File | Sort-Object Count -Descending | ForEach-Object {
		Write-Host ("  {0,3}  {1}" -f $_.Count, $_.Name)
	}
	Write-Host ""
	foreach ($d in ($diags | Sort-Object File, Line)) {
		Write-Host ("  {0}:{1} [{2}] {3}" -f $d.File, $d.Line, $d.Category, $d.Summary)
	}
}
Write-Host ""
Write-Host ("합계: type {0}, require {1}, lint {2}, syntax {3}" -f $byCat.type, $byCat.require, $byCat.lint, $byCat.syntax)
if ($byCat.require -gt 0) {
	Write-Host "  (require 해석 실패는 검사 환경 문제일 수 있어 따로 셈: Rojo 경로 require 는 sourcemap 으로 풀립니다)"
}

if ($Report -ne "") {
	$lines = New-Object System.Collections.Generic.List[string]
	$lines.Add("검사: $label, luau-lsp $LSP_VERSION (Luau $LUAU_VERSION 엔진), 경로: $($Path -join ', ')")
	$lines.Add("합계: type $($byCat.type), require $($byCat.require), lint $($byCat.lint), syntax $($byCat.syntax)")
	$lines.Add("")
	foreach ($g in ($diags | Group-Object File | Sort-Object Name)) {
		$lines.Add("### $($g.Name) ($($g.Count))")
		foreach ($d in ($g.Group | Sort-Object Line)) {
			$lines.Add("- 줄 $($d.Line) [$($d.Category)] $($d.Summary)")
		}
		$lines.Add("")
	}
	$dir = Split-Path -Parent $Report
	if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
	Set-Content -Path $Report -Value $lines -Encoding UTF8
	Write-Host "정리 파일: $Report"
}

if (($byCat.type + $byCat.syntax) -gt 0 -and -not $NoFail) { exit 1 }
exit 0
