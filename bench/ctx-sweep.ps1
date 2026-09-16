<#
  context 길이를 훑으면서 100% GPU 유지 한계선을 찾습니다.
  자기 GPU에서 이것만 돌려도 최적 num_ctx 가 나옵니다.

  사용법:
    pwsh -File bench/ctx-sweep.ps1
    pwsh -File bench/ctx-sweep.ps1 -Model ornith-1.5:9b -Sizes 16384,32768,65536
#>
param(
    [string]$Model = 'ornith-1.5:9b',
    # pwsh -File 로 부르면 인자가 전부 문자열로 들어와 [int[]] 로 못 받습니다.
    # 문자열로 받아 직접 쪼개야 -File / -Command 양쪽에서 똑같이 동작합니다.
    [string]$Sizes = '16384,32768,65536,98304,131072,196608,262144',
    [int]$Tokens   = 300
)

$SizeList = $Sizes -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ }

$api    = 'http://127.0.0.1:11434'
$prompt = 'C++로 스레드 안전한 LRU 캐시를 구현하고, 설계 이유를 설명해줘.'
$rows   = @()

foreach ($ctx in $SizeList) {
    # 앞 설정을 내려야 새 num_ctx 로 다시 올라갑니다.
    foreach ($prev in (Invoke-RestMethod -Uri "$api/api/ps").models) {
        $b = @{ model = $prev.name; keep_alive = 0 } | ConvertTo-Json
        try { Invoke-RestMethod -Uri "$api/api/generate" -Method Post -Body $b -ContentType 'application/json' -TimeoutSec 120 | Out-Null } catch {}
    }

    $body = @{
        model      = $Model
        prompt     = $prompt
        stream     = $false
        think      = $false
        keep_alive = '2m'
        options    = @{ num_predict = $Tokens; num_ctx = $ctx }
    } | ConvertTo-Json -Depth 5

    try {
        $r = Invoke-RestMethod -Uri "$api/api/generate" -Method Post `
             -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 3600
    } catch {
        Write-Warning "ctx=$ctx 실패: $($_.Exception.Message)"
        $rows += [pscustomobject]@{ Ctx = $ctx; TotalGB = 0; VramGB = 0; GpuPct = 0; TokPerSec = 0 }
        continue
    }

    # ollama ps 표를 파싱하지 않고 /api/ps 를 씁니다. 적재율이 정확히 나옵니다.
    $m = (Invoke-RestMethod -Uri "$api/api/ps").models |
         Where-Object { $_.name -eq $Model -or $_.model -eq $Model } | Select-Object -First 1

    $rows += [pscustomobject]@{
        Ctx       = $ctx
        TotalGB   = if ($m) { [math]::Round($m.size / 1GB, 2) } else { 0 }
        VramGB    = if ($m) { [math]::Round($m.size_vram / 1GB, 2) } else { 0 }
        GpuPct    = if ($m -and $m.size) { [math]::Round(100 * $m.size_vram / $m.size) } else { 0 }
        TokPerSec = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1)
    }
    $rows[-1] | Format-Table -AutoSize | Out-String | Write-Host -NoNewline
}

Write-Host "`n=== 결과 ===" -ForegroundColor Cyan
$rows | Format-Table -AutoSize
$best = $rows | Where-Object GpuPct -ge 100 | Sort-Object Ctx -Descending | Select-Object -First 1
if ($best) {
    Write-Host "100% GPU 를 유지하는 최대 context: $($best.Ctx) ($($best.TokPerSec) tok/s)" -ForegroundColor Green
    Write-Host "이 값을 OLLAMA_CONTEXT_LENGTH 에 넣으세요."
} else {
    Write-Host '100% GPU 로 올라간 설정이 없습니다. 더 작은 양자화를 쓰세요.' -ForegroundColor Yellow
}
$rows | ConvertTo-Json | Set-Content "ctx-sweep-$($Model -replace '[:/]','_').json" -Encoding UTF8
