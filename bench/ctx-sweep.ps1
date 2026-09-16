<#
  context 길이를 훑으면서 100% GPU 유지 한계선을 찾습니다.
  자기 GPU에서 이것만 돌려도 최적 num_ctx 가 나옵니다.

  판정 기준에 주의하세요. Windows(WDDM)에서는 `ollama ps` 의 PROCESSOR 가
  `100% GPU` 라고 나와도 실제로는 모델 일부가 시스템 RAM 으로 페이징되어
  있을 수 있습니다. Ollama 는 이걸 표시하지 않고 속도만 몇 배씩 떨어집니다.
  그래서 러너 프로세스(llama-server)의 Shared Usage 카운터를 같이 읽어
  0 MB 인 구간만 "진짜 100% GPU" 로 판정합니다.

  사용법:
    pwsh -File bench/ctx-sweep.ps1
    pwsh -File bench/ctx-sweep.ps1 -Model qwen3.8-iq4 -Sizes 8192,16384,24576,32768
#>
param(
    [string]$Model = 'qwen3.8-iq4',
    [int[]]$Sizes  = @(8192, 16384, 20480, 24576, 28672, 32768, 40960),
    [int]$Tokens   = 300
)

$prompt = 'C++로 스레드 안전한 LRU 캐시를 구현하고, 설계 이유를 설명해줘.'

# 러너(llama-server)가 쓰는 전용/공유 GPU 메모리를 MB 로 돌려줍니다.
# Shared 가 0 보다 크면 그만큼 PCIe 너머 시스템 RAM 에서 읽고 있다는 뜻입니다.
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

$rows = @()

foreach ($ctx in $Sizes) {
    $body = @{
        model   = $Model
        prompt  = $prompt
        stream  = $false
        think   = $false
        keep_alive = '2m'
        options = @{ num_predict = $Tokens; num_ctx = $ctx }
    } | ConvertTo-Json -Depth 5

    try {
        $r = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/generate' -Method Post `
             -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 1800
    } catch {
        Write-Warning "ctx=$ctx 실패: $($_.Exception.Message)"
        continue
    }

    $mem = Get-RunnerMemory
    $ps = (ollama ps)[1] -split '\s{2,}'
    $rows += [pscustomobject]@{
        Ctx       = $ctx
        TokPerSec = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1)
        PromptTokS= if ($r.prompt_eval_duration) { [math]::Round($r.prompt_eval_count / ($r.prompt_eval_duration / 1e9), 1) } else { 0 }
        LocalMB   = $mem.LocalMB
        SharedMB  = $mem.SharedMB
        Size      = $ps[2]
        Processor = $ps[3]
    }
    $rows[-1] | Format-Table -HideTableHeaders | Out-String | Write-Host -NoNewline
}

Write-Host "`n=== 결과 ===" -ForegroundColor Cyan
$rows | Format-Table -AutoSize

# 판정에 SharedMB 절대값을 쓰면 안 됩니다. WDDM 은 ctx 를 최소로 줘도 수백 MB 를
# 항상 공유 메모리에 잡아둡니다(이 값이 "바닥"). 모델이 실제로 새는 구간은
# 바닥보다 뚜렷하게 올라가는 지점입니다. 그래서 바닥 대비 상승분으로 판정합니다.
$floor = ($rows | Measure-Object SharedMB -Minimum).Minimum
$limit = [math]::Max($floor * 1.15, $floor + 100)
$best = $rows | Where-Object { $_.Processor -eq '100% GPU' -and $_.SharedMB -le $limit } |
        Sort-Object Ctx -Descending | Select-Object -First 1

Write-Host ("공유 메모리 바닥값: {0} MB (이 이하는 WDDM 상시 오버헤드)" -f $floor) -ForegroundColor DarkGray
if ($best) {
    Write-Host "시스템 RAM 유출 없이 유지되는 최대 context: $($best.Ctx) ($($best.TokPerSec) tok/s)" -ForegroundColor Green
    Write-Host "이 값을 Modelfile 의 num_ctx 와 OLLAMA_CONTEXT_LENGTH 에 넣으세요."
} else {
    $fake = $rows | Where-Object { $_.Processor -eq '100% GPU' -and $_.SharedMB -gt $limit }
    if ($fake) {
        Write-Host '모든 구간에서 시스템 RAM 으로 새고 있습니다.' -ForegroundColor Yellow
        Write-Host '`ollama ps` 는 100% GPU 라고 하지만 믿으면 안 됩니다. 더 작은 양자화를 쓰세요.' -ForegroundColor Yellow
    } else {
        Write-Host '100% GPU 로 올라간 설정이 없습니다. 더 작은 양자화를 쓰세요.' -ForegroundColor Yellow
    }
}
$rows | ConvertTo-Json | Set-Content "ctx-sweep-$Model.json" -Encoding UTF8
