<#
  생성 속도, 프롬프트 처리 속도, 로딩 시간을 잽니다.

  프롬프트 처리는 매번 새로 만든 긴 프롬프트로 잽니다. 짧은 프롬프트를 반복하면
  Ollama 의 프롬프트 캐시가 걸려(33토큰 중 29토큰 cached) 실제 처리 속도가 아니라
  캐시 히트율을 재게 됩니다. 자세한 건 bench/prompt-gen.ps1 주석 참고.

  사용법:
    pwsh -File bench/speed.ps1 -Model ornith-1.5:9b
#>
param([string]$Model = 'ornith-1.5:9b', [int]$Runs = 3, [int]$Tokens = 500, [int]$Ctx = 0)

. (Join-Path $PSScriptRoot 'prompt-gen.ps1')

$api    = 'http://127.0.0.1:11434'
$prompt = 'C++로 스레드 안전한 LRU 캐시를 구현하고, 설계 이유를 설명해줘.'

function Invoke-Gen($text, $predict, $seed) {
    $opt = @{ num_predict = $predict; seed = $seed }
    if ($Ctx -gt 0) { $opt.num_ctx = $Ctx }
    $body = @{ model = $Model; prompt = $text; stream = $false; think = $false
               keep_alive = '10m'; options = $opt } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$api/api/generate" -Method Post `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 1800
}

$rows = @()
for ($i = 1; $i -le $Runs; $i++) {
    $g = Invoke-Gen $prompt $Tokens $i                 # 생성 속도 (짧은 프롬프트)
    $p = Invoke-Gen (New-LongPrompt) 8 $i              # 프롬프트 처리 속도 (매번 새 긴 프롬프트)

    $rows += [pscustomobject]@{
        Run          = $i
        LoadSec      = [math]::Round($g.load_duration / 1e9, 1)
        OutTokens    = $g.eval_count
        GenTokS      = [math]::Round($g.eval_count / ($g.eval_duration / 1e9), 1)
        PromptTokens = $p.prompt_eval_count
        PromptTokS   = Get-PromptTokS $p
        TotalSec     = [math]::Round($g.total_duration / 1e9, 1)
    }
    $rows[-1] | Format-Table -AutoSize | Out-String | Write-Host -NoNewline
}

Write-Host "`n=== 평균 ===" -ForegroundColor Cyan
'{0,-14}: {1} tok/s' -f '생성',        [math]::Round((($rows.GenTokS)    | Measure-Object -Average).Average, 1)
'{0,-14}: {1} tok/s' -f '프롬프트 처리', [math]::Round((($rows.PromptTokS) | Measure-Object -Average).Average, 0)

ollama ps
nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv
