param([string]$Model = 'qwen3.8-iq4', [int]$Runs = 3, [int]$Tokens = 500)

$prompt = 'C++로 스레드 안전한 LRU 캐시를 구현하고, 설계 이유를 설명해줘.'

for ($i = 1; $i -le $Runs; $i++) {
    $body = @{
        model   = $Model
        prompt  = $prompt
        stream  = $false
        think   = $false
        options = @{ num_predict = $Tokens; seed = $i }
    } | ConvertTo-Json -Depth 5

    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/generate' -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 900

    [pscustomobject]@{
        Run           = $i
        LoadSec       = [math]::Round($r.load_duration / 1e9, 1)
        PromptTokS    = if ($r.prompt_eval_duration) { [math]::Round($r.prompt_eval_count / ($r.prompt_eval_duration / 1e9), 1) } else { 0 }
        OutTokens     = $r.eval_count
        GenTokS       = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1)
        TotalSec      = [math]::Round($r.total_duration / 1e9, 1)
    }
}

ollama ps
nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv
