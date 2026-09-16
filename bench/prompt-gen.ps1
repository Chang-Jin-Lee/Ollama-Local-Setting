<#
  긴 "고유" 프롬프트를 만듭니다. bench 스크립트들이 공통으로 씁니다.

  왜 필요한가: 짧은 프롬프트를 반복하면 Ollama 의 프롬프트 캐시가 걸려
  prompt_eval_count 33개 중 29개가 cached 로 잡힙니다. 그 상태에서
  count/duration 을 계산하면 실제 처리 속도가 아니라 캐시 히트율을 재게 됩니다.

  주의: 고유 문자열을 맨 앞줄에만 넣는 걸로는 부족합니다. Ollama 0.33.3 의 캐시는
  접두사가 달라도 재사용됩니다. 실제로 재보면 이렇습니다.

    맨 앞줄에만 고유값  -> 1회차 cached=0, 2회차부터 cached=2046 / 2050
    모든 줄에 고유값    -> 매번 cached=0 (2,500 tok/s 로 일정)

  그래서 모든 줄에 고유값을 섞습니다.
#>
function New-LongPrompt {
    param([int]$Lines = 400, [string]$Nonce = [guid]::NewGuid().ToString('N').Substring(0, 8))
    $sb = [Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Lines; $i++) {
        [void]$sb.AppendLine("# 참고 $Nonce-$i`: 캐시 교체 정책, 락 경합, false sharing 에 대한 메모.")
    }
    [void]$sb.AppendLine('위 메모를 참고해 C++로 스레드 안전한 LRU 캐시를 구현하고, 설계 이유를 설명해줘.')
    $sb.ToString()
}

# 캐시된 토큰을 빼고 실제로 처리한 것만 세어야 정직한 수치가 나옵니다.
function Get-PromptTokS {
    param($Response)
    $cached = if ($Response.prompt_eval_cached_count) { $Response.prompt_eval_cached_count } else { 0 }
    $done   = $Response.prompt_eval_count - $cached
    if ($Response.prompt_eval_duration -gt 0 -and $done -gt 0) {
        [math]::Round($done / ($Response.prompt_eval_duration / 1e9), 0)
    } else { 0 }
}
