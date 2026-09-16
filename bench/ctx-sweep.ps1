<#
  context 길이를 훑으면서 100% GPU 유지 한계선을 찾습니다.
  자기 GPU에서 이것만 돌려도 최적 num_ctx 가 나옵니다.

  판정은 두 가지를 같이 봅니다.

  1) Ollama 가 말하는 적재율. `ollama ps` 표를 파싱하지 않고 `/api/ps` 의
     size_vram / size 로 계산합니다. 표는 반올림된 문자열이라 92% 와 100% 가
     구분이 안 되는 경우가 있습니다.

  2) 러너 프로세스의 공유 메모리. Windows(WDDM)에서는 Ollama 가 100% 라고
     해도 실제로는 모델 일부가 시스템 RAM 으로 페이징되어 있을 수 있습니다.
     Ollama 는 이걸 표시하지 않고 속도만 몇 배씩 떨어집니다. 그래서
     llama-server 의 Shared Usage 카운터를 같이 읽습니다.

  둘 다 통과한 구간만 "진짜 100% GPU" 로 봅니다.

  사용법:
    pwsh -File bench/ctx-sweep.ps1
    pwsh -File bench/ctx-sweep.ps1 -Model qwen3.8-iq4 -Sizes 8192,16384,24576,32768
#>
param(
    [string]$Model = 'qwen3.8-iq4',
    # pwsh -File 로 부르면 인자가 전부 문자열로 들어와 [int[]] 로 못 받습니다.
    # 문자열로 받아 직접 쪼개야 -File / -Command 양쪽에서 똑같이 동작합니다.
    [string]$Sizes = '8192,16384,20480,24576,28672,32768,40960',
    [int]$Tokens   = 300
)

. (Join-Path $PSScriptRoot 'prompt-gen.ps1')

$api      = 'http://127.0.0.1:11434'
$prompt   = 'C++로 스레드 안전한 LRU 캐시를 구현하고, 설계 이유를 설명해줘.'
$SizeList = $Sizes -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ }

# 러너(llama-server)가 쓰는 전용/공유 GPU 메모리를 MB 로 돌려줍니다.
# Shared 가 바닥값보다 뚜렷하게 크면 그만큼 PCIe 너머 시스템 RAM 에서 읽고 있다는 뜻입니다.
function Get-RunnerMemory {
    $local = 0.0; $shared = 0.0
    $runners = @(Get-Process -Name 'llama-server', 'ollama_llama_server' -ErrorAction SilentlyContinue |
                 Select-Object -ExpandProperty Id)
    if (-not $runners) { return [pscustomobject]@{ LocalMB = 0; SharedMB = 0 } }

    foreach ($counter in 'Local Usage', 'Shared Usage') {
        $samples = (Get-Counter "\GPU Process Memory(*)\$counter" -ErrorAction SilentlyContinue).CounterSamples
        foreach ($s in $samples) {
            if ($s.CookedValue -le 0) { continue }
            # 인스턴스 이름은 pid_<PID>_luid_... 형식입니다.
            $procId = ($s.InstanceName -split '_')[1]
            if ($runners -notcontains [int]$procId) { continue }
            if ($counter -eq 'Local Usage') { $local += $s.CookedValue } else { $shared += $s.CookedValue }
        }
    }
    [pscustomobject]@{ LocalMB = [math]::Round($local / 1MB, 0); SharedMB = [math]::Round($shared / 1MB, 0) }
}

# 언로드 요청이 돌아와도 러너가 VRAM 을 바로 놓지는 않습니다. 안 기다리고 다음
# context 를 올리면 앞 할당이 남은 채로 겹쳐 올라가 한 지점만 공유 메모리로 새고
# 속도가 3분의 1로 떨어집니다(122,880 에서 2,314MB / 15.3 tok/s 를 한 번 봤는데,
# 다시 재보니 762MB / 54.8 tok/s 였습니다). 러너가 정리될 때까지 기다립니다.
function Wait-RunnerGone {
    param([int]$TimeoutSec = 60)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $loaded = (Invoke-RestMethod -Uri "$api/api/ps").models
        $procs  = Get-Process -Name 'llama-server', 'ollama_llama_server' -ErrorAction SilentlyContinue
        if (-not $loaded -and -not $procs) { Start-Sleep -Milliseconds 500; return }
        Start-Sleep -Milliseconds 500
    }
    Write-Warning "러너가 $TimeoutSec 초 안에 정리되지 않았습니다. 이번 측정은 앞 할당과 겹칠 수 있습니다."
}

function Invoke-Gen($text, $predict, $ctx) {
    $body = @{
        model      = $Model
        prompt     = $text
        stream     = $false
        think      = $false
        keep_alive = '2m'
        options    = @{ num_predict = $predict; num_ctx = $ctx }
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$api/api/generate" -Method Post `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 3600
}

$rows = @()

foreach ($ctx in $SizeList) {
    # 앞 설정을 내려야 새 num_ctx 로 다시 올라갑니다.
    foreach ($prev in (Invoke-RestMethod -Uri "$api/api/ps").models) {
        $b = @{ model = $prev.name; keep_alive = 0 } | ConvertTo-Json
        try { Invoke-RestMethod -Uri "$api/api/generate" -Method Post -Body $b -ContentType 'application/json' -TimeoutSec 120 | Out-Null } catch {}
    }
    Wait-RunnerGone

    try {
        $r = Invoke-Gen $prompt $Tokens $ctx
    } catch {
        Write-Warning "ctx=$ctx 실패: $($_.Exception.Message)"
        continue
    }

    $mem = Get-RunnerMemory
    $m   = (Invoke-RestMethod -Uri "$api/api/ps").models |
           Where-Object { $_.name -eq $Model -or $_.model -eq $Model } | Select-Object -First 1

    # 프롬프트 처리 속도는 매번 새 긴 프롬프트로 잽니다. 짧은 걸 쓰면 캐시가 걸립니다.
    $p = Invoke-Gen (New-LongPrompt) 8 $ctx

    $rows += [pscustomobject]@{
        Ctx        = $ctx
        TotalGB    = if ($m) { [math]::Round($m.size / 1GB, 2) } else { 0 }
        VramGB     = if ($m) { [math]::Round($m.size_vram / 1GB, 2) } else { 0 }
        GpuPct     = if ($m -and $m.size) { [math]::Round(100 * $m.size_vram / $m.size) } else { 0 }
        SharedMB   = $mem.SharedMB
        TokPerSec  = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1)
        PromptTokS = Get-PromptTokS $p
    }
    $rows[-1] | Format-Table -AutoSize | Out-String | Write-Host -NoNewline
}

Write-Host "`n=== 결과 ===" -ForegroundColor Cyan
$rows | Format-Table -AutoSize

# 판정에 SharedMB 절대값을 쓰면 안 됩니다. WDDM 은 ctx 를 최소로 줘도 수백 MB 를
# 항상 공유 메모리에 잡아둡니다(이 값이 "바닥"). 모델이 실제로 새는 구간은
# 바닥보다 뚜렷하게 올라가는 지점입니다. 그래서 바닥 대비 상승분으로 판정합니다.
$floor = ($rows | Measure-Object SharedMB -Minimum).Minimum
$limit = [math]::Max($floor * 1.15, $floor + 100)
$best  = $rows | Where-Object { $_.GpuPct -ge 100 -and $_.SharedMB -le $limit } |
         Sort-Object Ctx -Descending | Select-Object -First 1

Write-Host ("공유 메모리 바닥값: {0} MB (이 이하는 WDDM 상시 오버헤드)" -f $floor) -ForegroundColor DarkGray
if ($best) {
    Write-Host "시스템 RAM 유출 없이 유지되는 최대 context: $($best.Ctx) ($($best.TokPerSec) tok/s)" -ForegroundColor Green
    Write-Host "이 값을 Modelfile 의 num_ctx 와 OLLAMA_CONTEXT_LENGTH 에 넣으세요."
} else {
    $fake = $rows | Where-Object { $_.GpuPct -ge 100 -and $_.SharedMB -gt $limit }
    if ($fake) {
        Write-Host '모든 구간에서 시스템 RAM 으로 새고 있습니다.' -ForegroundColor Yellow
        Write-Host 'Ollama 는 100% GPU 라고 하지만 믿으면 안 됩니다. 더 작은 양자화를 쓰세요.' -ForegroundColor Yellow
    } else {
        Write-Host '100% GPU 로 올라간 설정이 없습니다. 더 작은 양자화를 쓰세요.' -ForegroundColor Yellow
    }
}
$rows | ConvertTo-Json | Set-Content "ctx-sweep-$($Model -replace '[:/]','_').json" -Encoding UTF8
