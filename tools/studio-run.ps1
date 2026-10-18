# 스튜디오에서 Luau 파일(또는 문자열)을 실행하고 결과를 출력.
# 사용: tools\studio-run.ps1 -File check.luau -DataModel Server
#       tools\studio-run.ps1 -Code "return 1+1" -DataModel Client
# 줄바꿈은 LF 로 통일(CRLF 는 스튜디오 쪽 BindCodeAsync 가 거부함).
param(
  [string]$File = "",
  [string]$Code = "",
  [ValidateSet("Edit","Client","Server")][string]$DataModel = "Server",
  [string]$StudioId = "",
  [int]$TimeoutMs = 90000,
  [int]$Retries = 3
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($File) { $Code = Get-Content -Raw -Encoding UTF8 $File }
$Code = $Code -replace "`r`n", "`n"
if (-not $StudioId) {
  $list = & "$here\studio-mcp.ps1" -Method tools/call -Tool list_roblox_studios -ArgsJson '{}' -TimeoutMs 60000
  $StudioId = (($list | ConvertFrom-Json).studios | Select-Object -First 1).id
  if (-not $StudioId) { throw "연결된 스튜디오가 없습니다." }
}
$json = @{ code = $Code; datamodel_type = $DataModel; studio_id = $StudioId } | ConvertTo-Json -Compress -Depth 3
for ($i = 1; $i -le $Retries; $i++) {
  try {
    & "$here\studio-mcp.ps1" -Method tools/call -Tool execute_luau -ArgsJson $json -TimeoutMs $TimeoutMs
    exit $LASTEXITCODE
  } catch {
    if ($i -eq $Retries) { throw }
    Start-Sleep -Seconds 3
  }
}
