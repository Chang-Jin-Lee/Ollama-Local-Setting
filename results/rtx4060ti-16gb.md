# RTX 4060 Ti 16GB — 측정 기록

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 4060 Ti 16GB (Ada, 128bit / 288GB/s), 드라이버 610.88, PCIe x8 |
| CPU / RAM | i9-13900KF (24C/32T) / DDR5-4800 128GB |
| 보드 | Gigabyte Z790 AERO G |
| OS | Windows 11 Pro 26200 |
| Ollama | 0.34.1 |
| 모델 | **Qwen3.8-27B UD-IQ3_S (Unsloth), 12,040,883,104 바이트** |
| 측정일 | 2026-09-16 |

## 결론부터

이 카드에서는 **IQ4_XS가 아니라 IQ3_S를 써야 한다.** 파일이 2GB 작은 쪽이 더 빠르고, context는 3배 길고, 코딩 문제도 더 많이 맞혔다. 전부 이긴다.

| | IQ3_S (11.21 GiB) | IQ4_XS (13.27 GiB) |
|---|---|---|
| 100% GPU 최대 context | **49,152** | 16,384 |
| 생성 속도 | **20.6 tok/s** | 17.8 tok/s |
| 코딩 10문제 | **10 / 10** | 9 / 10 |
| 문제당 평균 | **60초** | 74초 |

VRAM이 같은 16GB라도 RTX 4080과는 답이 다르다. 4080은 IQ4_XS에 24K context가 맞지만, 4060 Ti는 여유 VRAM이 더 빠듯하고 대역폭이 2.5배 낮아 한 단계 내려가는 쪽이 이긴다.

## 최종 설정

```
OLLAMA_FLASH_ATTENTION = 1
OLLAMA_KV_CACHE_TYPE   = q8_0
OLLAMA_CONTEXT_LENGTH  = 49152
num_ctx (Modelfile)    = 49152
```

## `ollama ps`의 100% GPU를 믿으면 안 된다

이 카드에서 제일 오래 잡아먹은 함정이다.

처음에 IQ4_XS를 올렸더니 `ollama ps`가 `100% GPU`라고 찍었다. 그런데 속도가 8.18 tok/s밖에 안 나왔다. 4080의 41 tok/s와 5배 차이인데, 대역폭 차이(2.5배)로는 절반도 설명이 안 됐다.

Windows 성능 카운터를 열어보니 답이 나왔다.

| | |
|---|---|
| 러너(`llama-server`) 전용 VRAM | 12,897 MB |
| 러너 **공유 메모리(시스템 RAM)** | **1,398 MB** |
| 어댑터 total committed | 20,517 MB (VRAM 16,380 초과) |

모델 1.4GB가 시스템 RAM에 얹혀 PCIe x8로 왕복하고 있었다. WDDM이 VRAM 초과분을 조용히 페이징한 것이고, **Ollama는 이걸 전혀 표시하지 않는다.** `ollama ps`는 자기가 의도한 레이어 배치만 말할 뿐, 드라이버가 그 뒤에 무슨 짓을 했는지는 모른다.

그래서 `bench/ctx-sweep.ps1`을 고쳤다. 이제 `llama-server`의 `Shared Usage` 카운터를 같이 읽는다. 직접 확인하려면:

```powershell
(Get-Counter '\GPU Process Memory(*)\Shared Usage').CounterSamples |
  Where-Object { $_.CookedValue -gt 1MB }
```

한 가지 주의. **Shared가 0이어야 한다고 판정하면 안 된다.** WDDM은 context를 2048로 줘도 600~670MB를 항상 공유 메모리에 잡아둔다. 이건 상시 오버헤드지 유출이 아니다. 두 양자화 모두 바닥값이 624~670MB로 같았다. 판정은 **바닥 대비 상승분**으로 해야 한다.

## VRAM 예산

데스크톱이 먹는 양이 결과를 통째로 뒤집는다.

| 상태 | 점유 | Ollama 여유 |
|---|---|---|
| Chrome + Docker + Parsec | 2,780 MiB | 13,330 MiB |
| Parsec만 (원격 제어용) | 1,173 MiB | **14,937 MiB** |

IQ4_XS 파일이 13,593 MiB다. Chrome과 Docker를 켜두면 **모델 가중치만으로 여유 VRAM의 102%**라 KV cache 자리가 아예 없다. 이때가 8.18 tok/s.

Chrome과 Docker를 끄면 1.6GB가 돌아와 17.8 tok/s로 2.2배가 된다. 그래도 IQ4_XS는 여전히 경계선이라, 결국 IQ3_S로 내리는 게 맞았다.

## context 한계선

<img src="../assets/rtx4060ti-context-speed.svg" width="620" alt="context 길이별 생성 속도">

Chrome·Docker를 끄고 Parsec만 켠 상태 기준이다. `Shared`는 러너가 시스템 RAM에 얹은 양.

**IQ3_S** — 절벽은 49K와 57K 사이.

| context | 생성 | Shared | `ollama ps` |
|---|---|---|---|
| 8,192 | 20.8 | 630 MB | 100% GPU |
| 16,384 | 20.7 | 638 MB | 100% GPU |
| 24,576 | 20.8 | 646 MB | 100% GPU |
| 32,768 | 20.8 | 654 MB | 100% GPU |
| 40,960 | 20.7 | 662 MB | 100% GPU |
| **49,152** | **20.7** | **670 MB** | **100% GPU** |
| 57,344 | 16.5 | 1,240 MB | 9% CPU / 91% GPU |
| 65,536 | 14.3 | 1,662 MB | 12% CPU / 88% GPU |

**IQ4_XS** — 절벽은 16K와 20K 사이.

| context | 생성 | Shared | `ollama ps` |
|---|---|---|---|
| 2,048 | 17.9 | 624 MB | 100% GPU |
| 8,192 | 17.9 | 630 MB | 100% GPU |
| **16,384** | **17.9** | **638 MB** | **100% GPU** |
| 20,480 | 15.7 | 972 MB | 6% CPU / 94% GPU |
| 24,576 | 14.1 | 1,340 MB | 9% CPU / 91% GPU |
| 32,768 | 12.7 | 1,710 MB | 11% CPU / 89% GPU |

IQ4_XS는 2K부터 16K까지 속도가 17.9로 완전히 평평하다. 이 구간에서는 context를 늘려도 공짜라는 뜻. 4080에서도 같은 모양이 나왔으니 이건 카드 성질이 아니라 모델 성질로 보인다.

## 속도

`bench/speed.ps1`, 500토큰 3회.

| | IQ3_S | IQ4_XS |
|---|---|---|
| 생성 | **20.6 tok/s** | 17.8 tok/s |
| 프롬프트 처리 (warm) | 251~263 tok/s | 251 tok/s |
| 프롬프트 처리 (cold) | 90 tok/s | 104 tok/s |
| 500토큰 생성 | **24.4초** | 28.2초 |
| 모델 로딩 | 4.3초 | 4.3초 |
| VRAM 점유 | 15,361 / 16,380 MiB | 15,399 / 16,380 MiB |

프롬프트 처리는 둘이 같다. 차이가 나는 건 생성 쪽뿐이고, 이건 읽어야 할 가중치가 2GB 적은 만큼 그대로 나온다.

4080과 비교하면 생성은 20.6 대 41.0으로 절반, 프롬프트 처리는 251 대 820~848로 3분의 1이다. 메모리 대역폭이 288 대 716GB/s니 대체로 예상 범위.

## 코딩 벤치마크

<img src="../assets/rtx4060ti-coding-bench.svg" width="620" alt="코딩 벤치마크 결과">

`bench/run.py`. 모델이 내놓은 코드를 파일로 저장해 숨긴 테스트와 함께 실제로 실행한다.

| 설정 | 통과 | 문제당 평균 | 전체 |
|---|---|---|---|
| **IQ3_S · thinking ON** | **10 / 10** | 60초 | 605초 |
| **IQ3_S · thinking OFF** | **10 / 10** | 26초 | 263초 |
| IQ4_XS · thinking ON | 9 / 10 | 74초 | 743초 |

IQ3_S는 thinking을 켜든 끄든 10문제를 다 풀었다. 끄면 2.3배 빠르다. 4080의 IQ4_XS가 thinking을 끄면 9개에서 6개로 떨어졌던 것과 다르다.

다만 문제가 10개뿐이고 설정당 1회씩만 돌린 결과다. "이 10문제에서는 thinking이 이득이 없었다"까지가 말할 수 있는 범위고, 일반적으로 꺼도 된다는 뜻은 아니다.

### IQ4_XS가 실패한 문제

정수 계산기 파서(단항 마이너스 포함) 하나. 4080 기록에 적힌 것과 **똑같은 실패**가 재현됐다.

| | IQ4_XS | IQ3_S |
|---|---|---|
| thinking 길이 | 16,285자 | 5,070자 |
| 출력 토큰 | 4,096 (한도 소진) | 1,949 |
| 소요 | 227.6초 | 94.2초 |
| 답변 | **0자** | 정상 |
| 결과 | `NameError: evaluate is not defined` | 통과 |

thinking 로그를 열어보면 문법 정의까지는 멀쩡히 가놓고 파서 코드를 thinking 안에서 쓰기 시작해 `if i >= n or s`에서 잘렸다. 답변 영역은 한 글자도 안 나왔다.

같은 카드, 같은 문제, 같은 프롬프트에서 양자화만 바꾸니 통과했다. 이 실패는 하드웨어가 아니라 IQ4_XS에 붙어 있는 성질이다. 4080에서도 IQ4_XS로 같은 문제에서 터졌다는 점이 이걸 뒷받침한다.

### thinking ON 문제별 기록

| 문제 | IQ3_S | IQ4_XS |
|---|---|---|
| LRU 캐시 | PASS 60.2초 | PASS 59.3초 |
| 최장 유효 괄호 | PASS 35.8초 | PASS 36.9초 |
| 두 정렬배열 중앙값 O(log) | PASS 80.6초 | PASS 57.5초 |
| **정수 계산기 파서** | **PASS 94.2초** | **FAIL 227.6초** |
| 이진트리 직렬화 | PASS 18.8초 | PASS 52.9초 |
| k회 주식거래 DP | PASS 160.8초 | PASS 79.4초 |
| 정규식 매칭 | PASS 30.4초 | PASS 105.3초 |
| 위상정렬 | PASS 29.7초 | PASS 37.2초 |
| word break 전체해 | PASS 51.8초 | PASS 68.5초 |
| 스레드 안전 RateLimiter | PASS 42.5초 | PASS 18.5초 |
| thinking 총 문자 | 30,970 | 39,988 |

중앙값 문제는 랜덤 200케이스 교차검증을 통과했고, RateLimiter는 5스레드 100회 동시 호출에서 정확히 50개만 허용했다.

## 설치 중에 걸렸던 것

**다운로드가 65 KB/s로 기어갔다.** 네트워크 문제가 아니었다. 멈춘 `ollama pull`이 16개 연결을 물고 놓지 않아 curl까지 같이 굶고 있었다. 그 프로세스를 죽이니 HF가 바로 11~16 MB/s로 돌아왔다. **GGUF를 curl로 받는 동안 `ollama pull`을 같이 돌리면 안 된다.**

```powershell
Get-CimInstance Win32_Process -Filter "Name='ollama.exe'" |
  Where-Object { $_.CommandLine -match 'pull' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

**`ollama pull`이 blob을 미리 할당만 해놓고 멈췄다.** README에 `hf.co/...` 케이스로 적혀 있던 그 증상이 공식 레지스트리에서도 나왔다. `blobs\sha256-...-partial`이 13GB로 보이는데 실제로는 빈 파일이었고, 옆의 `-partial-0` ~ `-partial-15` 청크가 전부 0바이트면 진행이 아예 안 되는 중이다. 크기만 보고 판단하면 안 된다.

**기본 게이트웨이가 둘이면 속도가 요동친다.** Wi-Fi와 이더넷이 둘 다 metric 0이라 같은 CDN이 0.25 MB/s와 2.6 MB/s 사이를 오갔다. `curl --interface <로컬IP>`로 한쪽에 고정하면 27 MB/s가 나왔다. 8병렬로 붙여도 소용없었으니(0.38 MB/s) 연결 수 문제가 아니라 경로 문제다.

## 안 해본 것

- 이미지 입력(mmproj 0.86GB). IQ3_S 기준으로는 자리가 있지만 재보지 않았다.
- gpt-oss:20b 대조군. 파일이 13GB라 IQ4_XS와 같은 문제에 걸릴 게 뻔해 받다 말았다.
- `reasoning_effort` 조절로 IQ4_XS의 thinking 폭주를 막을 수 있는지.
- Chrome·Docker를 켠 상태에서의 IQ3_S. 여유가 13,330 MiB라 11,483 MiB 모델은 들어갈 것으로 보이지만 확인하지 않았다.
- 여러 번 반복 측정. 코딩 벤치는 설정당 1회씩이다.
