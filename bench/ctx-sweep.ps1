<#
  context 길이를 훑으면서 100% GPU 유지 한계선을 찾습니다.
  자기 GPU에서 이것만 돌려도 최적 num_ctx 가 나옵니다.

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

    $ps = (ollama ps)[1] -split '\s{2,}'
    $rows += [pscustomobject]@{
        Ctx       = $ctx
        TokPerSec = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1)
        Size      = $ps[2]
        Processor = $ps[3]
    }
    $rows[-1] | Format-Table -HideTableHeaders | Out-String | Write-Host -NoNewline
}

Write-Host "`n=== 결과 ===" -ForegroundColor Cyan
$rows | Format-Table -AutoSize
$best = $rows | Where-Object Processor -eq '100% GPU' | Sort-Object Ctx -Descending | Select-Object -First 1
if ($best) {
    Write-Host "100% GPU 를 유지하는 최대 context: $($best.Ctx) ($($best.TokPerSec) tok/s)" -ForegroundColor Green
    Write-Host "이 값을 Modelfile 의 num_ctx 와 OLLAMA_CONTEXT_LENGTH 에 넣으세요."
} else {
    Write-Host '100% GPU 로 올라간 설정이 없습니다. 더 작은 양자화를 쓰세요.' -ForegroundColor Yellow
}
$rows | ConvertTo-Json | Set-Content "ctx-sweep-$Model.json" -Encoding UTF8
