<#
  ollama pull 이 stall 될 때 쓰는 우회 경로입니다.

  Ollama 는 블롭 하나를 16개 파트로 병렬 다운로드하는데, 회선에 따라 전부
  stall 에 빠져 진행률이 멈춘 채 재시도만 반복하는 경우가 있습니다
  (server.log 에 "part N stalled; retrying" 가 쌓입니다).
  같은 회선에서 curl 단일 연결은 멀쩡히 나오므로, 매니페스트를 직접 읽어
  블롭을 curl 로 받고 Ollama 의 저장소에 그대로 넣어줍니다.

  사용법:
    pwsh -File setup/pull-curl.ps1 -Model ornith-1.5:9b
    pwsh -File setup/pull-curl.ps1 -Model granite4.2:8b-q8_0
#>
param(
    [Parameter(Mandatory)][string]$Model,
    [string]$Registry = 'registry.ollama.ai'
)

$ErrorActionPreference = 'Stop'

# ornith-1.5:9b -> library/ornith-1.5 + 9b  /  user/model:tag 도 받습니다.
$name, $tag = $Model -split ':', 2
if (-not $tag) { $tag = 'latest' }
if ($name -notmatch '/') { $name = "library/$name" }

$root      = if ($env:OLLAMA_MODELS) { $env:OLLAMA_MODELS } else { Join-Path $env:USERPROFILE '.ollama\models' }
$blobDir   = Join-Path $root 'blobs'
$manDir    = Join-Path $root "manifests\$Registry\$($name -replace '/', '\')"
New-Item -ItemType Directory -Force $blobDir, $manDir | Out-Null

Write-Host "==> 매니페스트: $Registry/$name`:$tag" -ForegroundColor Cyan
$manUrl = "https://$Registry/v2/$name/manifests/$tag"
$manRaw  = curl.exe -sSL -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' $manUrl
$man     = $manRaw | ConvertFrom-Json
if (-not $man.layers) { throw "매니페스트를 읽지 못했습니다: $manRaw" }

$items = @($man.config) + @($man.layers)
$total = ($items | Measure-Object -Property size -Sum).Sum
Write-Host ("    레이어 {0}개, 합계 {1:N2} GB" -f $items.Count, ($total / 1GB))

foreach ($l in $items) {
    $digest = $l.digest -replace '^sha256:', ''
    $dest   = Join-Path $blobDir "sha256-$digest"

    if ((Test-Path $dest) -and (Get-Item $dest).Length -eq $l.size) {
        Write-Host ("    [skip] {0} ({1:N2} GB) 이미 있음" -f $digest.Substring(0, 12), ($l.size / 1GB))
        continue
    }
    # ollama 가 남긴 파트 조각이 있으면 치웁니다. 이어받기와 섞이면 크기가 안 맞습니다.
    Get-ChildItem $blobDir -Filter "sha256-$digest-partial*" -EA SilentlyContinue | Remove-Item -Force

    Write-Host ("    [get ] {0} ({1:N2} GB)" -f $digest.Substring(0, 12), ($l.size / 1GB))
    curl.exe -L -C - --retry 20 --retry-delay 3 --retry-all-errors --progress-bar `
        -o $dest "https://$Registry/v2/$name/blobs/$($l.digest)"

    $got = (Get-Item $dest).Length
    if ($got -ne $l.size) { throw "크기 불일치 $digest`: $got (기대값 $($l.size))" }
}

# 매니페스트는 블롭이 다 있는 뒤에 씁니다. 먼저 쓰면 ollama 가 깨진 모델로 봅니다.
$manPath = Join-Path $manDir $tag
[IO.File]::WriteAllText($manPath, $manRaw)
Write-Host "==> 등록: $manPath" -ForegroundColor Green

ollama show $Model --modelfile | Select-String -Pattern '^FROM|^PARAMETER' | Select-Object -First 8
Write-Host "완료: $Model" -ForegroundColor Green
