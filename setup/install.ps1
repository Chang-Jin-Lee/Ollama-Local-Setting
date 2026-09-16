<#
  Ollama-Local-Setting — 원클릭 설치 (Windows / PowerShell 7+)

  하는 일:
    1) Ollama 환경변수 설정 (Flash Attention, q8_0 KV cache, 기본 context)
    2) Qwen3.8-27B IQ4_XS GGUF 다운로드 (이어받기 지원)
    3) Ollama 모델 등록
    4) OpenCode + Superpowers 설치 및 설정

  사용법:
    pwsh -File setup/install.ps1                 # 전체
    pwsh -File setup/install.ps1 -SkipAgent      # 모델만 (OpenCode 제외)
    pwsh -File setup/install.ps1 -Ctx 16384      # context 직접 지정
#>
param(
    [int]$Ctx = 24576,
    [string]$ModelName = 'qwen3.8-iq4',
    [string]$GgufDir = "$env:USERPROFILE\ollama-gguf",
    [switch]$SkipAgent
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$url  = 'https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-IQ4_XS.gguf'
$gguf = Join-Path $GgufDir 'Qwen3.8-27B-UD-IQ4_XS.gguf'

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# --- 0. 사전 확인 ---------------------------------------------------------
Step '사전 확인'
foreach ($cmd in 'ollama', 'curl') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "$cmd 를 찾을 수 없습니다." }
}
ollama --version
$vram = (nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null) -as [int]
if ($vram) { Write-Host "VRAM: $vram MiB" }
if ($vram -and $vram -lt 15000) {
    Write-Warning "VRAM이 15GB 미만입니다. IQ4_XS(13.3GiB)가 다 안 들어갈 수 있습니다."
    Write-Warning "README의 '내 GPU는 VRAM이 다른데요' 항목을 참고하세요."
}

# --- 1. 환경변수 ----------------------------------------------------------
Step '환경변수 설정'
[Environment]::SetEnvironmentVariable('OLLAMA_FLASH_ATTENTION', '1', 'User')
[Environment]::SetEnvironmentVariable('OLLAMA_KV_CACHE_TYPE', 'q8_0', 'User')
[Environment]::SetEnvironmentVariable('OLLAMA_CONTEXT_LENGTH', "$Ctx", 'User')
'OLLAMA_FLASH_ATTENTION=1', 'OLLAMA_KV_CACHE_TYPE=q8_0', "OLLAMA_CONTEXT_LENGTH=$Ctx" | ForEach-Object { Write-Host "  $_" }

# --- 2. GGUF 다운로드 -----------------------------------------------------
Step 'GGUF 다운로드 (약 14GB)'
New-Item -ItemType Directory -Force $GgufDir | Out-Null
$expected = 14252845984
if ((Test-Path $gguf) -and (Get-Item $gguf).Length -eq $expected) {
    Write-Host '  이미 받아져 있습니다. 건너뜁니다.'
} else {
    # ollama pull hf.co/... 는 0%에서 멈추는 사례가 있어 curl 로 직접 받습니다.
    curl.exe -L -C - --retry 20 --retry-delay 5 --retry-all-errors -o $gguf $url
    $size = (Get-Item $gguf).Length
    if ($size -ne $expected) { throw "크기 불일치: $size (기대값 $expected)" }
}

# --- 3. 모델 등록 ---------------------------------------------------------
Step "모델 등록: $ModelName"
$mf = Join-Path $env:TEMP 'Modelfile.qwen3.8-iq4'
(Get-Content (Join-Path $repo 'setup\Modelfile.qwen3.8-iq4') -Raw).
    Replace('./Qwen3.8-27B-UD-IQ4_XS.gguf', $gguf).
    Replace('PARAMETER num_ctx 24576', "PARAMETER num_ctx $Ctx") | Set-Content $mf -Encoding UTF8
ollama create $ModelName -f $mf
Remove-Item $mf

# --- 4. 코딩 에이전트 -----------------------------------------------------
if (-not $SkipAgent) {
    Step 'OpenCode + Superpowers'
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning 'npm이 없어 건너뜁니다. Node.js 설치 후 다시 실행하세요.'
    } else {
        # postinstall 이 막히면 opencode.exe 가 안 깔립니다.
        npm install -g --allow-scripts=opencode-ai opencode-ai
        $cfgDir = "$env:USERPROFILE\.config\opencode"
        New-Item -ItemType Directory -Force $cfgDir | Out-Null
        # --prefix 를 빼면 상위 폴더의 package.json 을 따라가 엉뚱한 곳에 설치됩니다.
        npm install 'superpowers@git+https://github.com/obra/superpowers.git' --prefix $cfgDir
        $cfg = Get-Content (Join-Path $repo 'setup\opencode.json') -Raw
        $cfg = $cfg.Replace('qwen3.8-iq4:latest', "${ModelName}:latest").Replace('24576', "$Ctx")
        $cfg | Set-Content (Join-Path $cfgDir 'opencode.json') -Encoding UTF8
        Write-Host "  설정: $cfgDir\opencode.json"
    }
}

Step '완료'
Write-Host @"
  Ollama를 완전히 종료했다가 다시 켜세요 (환경변수 적용).

  확인:  ollama run $ModelName
  배치:  ollama ps          <- PROCESSOR 가 100% GPU 여야 합니다
  속도:  pwsh -File bench/speed.ps1 -Model $ModelName
  코딩:  python bench/run.py $ModelName
  에이전트: cd <프로젝트> ; opencode
"@
