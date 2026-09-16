<#
  후보 모델들을 같은 조건으로 돌려 "이 카드에 뭘 올릴지"를 고릅니다.
  ctx-sweep 이 한 모델의 context 한계를 찾는다면, 이건 모델끼리 비교합니다.

  각 모델마다: VRAM 적재율, 생성 속도, 프롬프트 처리 속도, 로딩 시간을 재고
  100% GPU 로 올라간 것만 후보로 남깁니다.

  사용법:
    pwsh -File bench/model-pick.ps1
    pwsh -File bench/model-pick.ps1 -Models ornith-1.5:9b,granite4.2:8b-q8_0 -Ctx 16384
#>
param(
    # pwsh -File 로 부르면 인자가 문자열로 들어옵니다. [string[]] 로 받으면 콤마 목록이 안 쪼개집니다.
    [string]$Models = 'ornith-1.5:9b,granite4.2:8b-q8_0,ornith:9b-q8_0,granite4.2:30b-q2_K',
    [int]$Ctx     = 16384,
    [int]$Tokens  = 400,
    [int]$Runs    = 2,
    [string]$Out  = 'model-pick.json'
)

. (Join-Path $PSScriptRoot 'prompt-gen.ps1')

$prompt = 'C++로 스레드 안전한 LRU 캐시를 구현하고, 설계 이유를 설명해줘.'
$api    = 'http://127.0.0.1:11434'

function Invoke-Gen($model, $seed, $ctx, $text = $prompt, $predict = $Tokens) {
    $body = @{
        model      = $model
        prompt     = $text
        stream     = $false
        think      = $false
        keep_alive = '5m'
        options    = @{ num_predict = $predict; num_ctx = $ctx; seed = $seed }
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$api/api/generate" -Method Post `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 1800
}

# ollama ps 표를 파싱하는 대신 /api/ps 를 씁니다. size_vram/size 로 적재율이 정확히 나옵니다.
function Get-Loaded($model) {
    $ps = Invoke-RestMethod -Uri "$api/api/ps" -TimeoutSec 60
    $ps.models | Where-Object { $_.name -eq $model -or $_.model -eq $model } | Select-Object -First 1
}

$ModelList = $Models -split '[,\s]+' | Where-Object { $_ }

$rows = @()
foreach ($m in $ModelList) {
    Write-Host "`n==> $m" -ForegroundColor Cyan

    # 앞 모델을 내려 VRAM 을 비웁니다. 안 그러면 뒤 모델이 CPU 로 밀립니다.
    foreach ($prev in (Invoke-RestMethod -Uri "$api/api/ps").models) {
        $b = @{ model = $prev.name; keep_alive = 0 } | ConvertTo-Json
        try { Invoke-RestMethod -Uri "$api/api/generate" -Method Post -Body $b -ContentType 'application/json' -TimeoutSec 120 | Out-Null } catch {}
    }

    try { $first = Invoke-Gen $m 1 $Ctx } catch { Write-Warning "$m 실패: $($_.Exception.Message)"; continue }

    $loaded = Get-Loaded $m
    $gpuPct = if ($loaded -and $loaded.size) { [math]::Round(100 * $loaded.size_vram / $loaded.size) } else { 0 }

    # 첫 실행은 로딩이 섞이므로 생성 속도는 두 번째부터 집계합니다.
    $gen = @()
    for ($i = 2; $i -le ($Runs + 1); $i++) {
        $r = Invoke-Gen $m $i $Ctx
        $gen += $r.eval_count / ($r.eval_duration / 1e9)
    }

    # 프롬프트 처리 속도는 매번 새 긴 프롬프트로 잽니다. 짧은 걸 반복하면 캐시가 걸립니다.
    $pp = @()
    for ($i = 1; $i -le 2; $i++) {
        $r = Invoke-Gen $m $i $Ctx (New-LongPrompt) 8
        $pp += Get-PromptTokS $r
    }

    $rows += [pscustomobject]@{
        Model      = $m
        Ctx        = $Ctx
        SizeGB     = if ($loaded) { [math]::Round($loaded.size / 1GB, 2) } else { 0 }
        VramGB     = if ($loaded) { [math]::Round($loaded.size_vram / 1GB, 2) } else { 0 }
        GpuPct     = $gpuPct
        GenTokS    = [math]::Round(($gen | Measure-Object -Average).Average, 1)
        PromptTokS = if ($pp) { [math]::Round(($pp | Measure-Object -Average).Average, 1) } else { 0 }
        LoadSec    = [math]::Round($first.load_duration / 1e9, 1)
    }
    $rows[-1] | Format-List | Out-String | Write-Host -NoNewline
}

Write-Host "`n=== 결과 (ctx=$Ctx) ===" -ForegroundColor Cyan
$rows | Sort-Object GenTokS -Descending | Format-Table -AutoSize

$fit = $rows | Where-Object GpuPct -ge 100
if ($fit) {
    $best = $fit | Sort-Object GenTokS -Descending | Select-Object -First 1
    Write-Host "100% GPU 로 올라간 모델: $(($fit.Model) -join ', ')" -ForegroundColor Green
    Write-Host "그 중 제일 빠른 것: $($best.Model) — $($best.GenTokS) tok/s" -ForegroundColor Green
    Write-Host "다음은 bench/ctx-sweep.ps1 -Model $($best.Model) 로 context 한계선을 찾으세요."
} else {
    Write-Host '전부 CPU 로 밀렸습니다. 더 작은 양자화를 쓰세요.' -ForegroundColor Yellow
}

$rows | ConvertTo-Json | Set-Content $Out -Encoding UTF8
Write-Host "저장: $Out"
