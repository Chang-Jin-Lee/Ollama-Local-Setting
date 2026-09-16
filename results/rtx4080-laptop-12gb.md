# RTX 4080 Laptop 12GB — 측정 기록

같은 "RTX 4080"이라도 노트북용은 데스크톱용과 다른 카드다. VRAM이 16GB가 아니라
12GB이고, 그 차이가 올릴 수 있는 모델을 바꾼다. [rtx4080-16gb.md](rtx4080-16gb.md)와
비교해서 보면 된다.

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 4080 Laptop GPU (Ada, AD104), 12,282 MiB, 드라이버 610.74, CUDA 13.3 |
| CPU | Intel Core i9-14900HX (24C / 32T) |
| RAM | DDR5-5600 32GB (16GB x 2, Samsung) |
| 저장장치 | WD PC SN8000S 1TB NVMe |
| 본체 | Lenovo 83DE |
| OS | Windows 11 Home 10.0.26200 |
| Ollama | 0.33.3 |
| 측정일 | 2026-09-16 |

## 결론부터

| | |
|---|---|
| 쓸 모델 | `ornith-1.5:9b` (Qwen3.5 계열 9B, Q4_K_M, 6.6GB) |
| 100% GPU 최대 context | **126,976** |
| 생성 속도 | 54.6 tok/s |
| 프롬프트 처리 | 2,511 tok/s |
| 코딩 10문제 | 7 / 10 |

코딩 정확도만 놓고 보면 `ornith:9b-q8_0`이 9/10으로 더 낫다. 대신 느리고(41 tok/s)
context가 53,248까지밖에 안 올라간다. 고르는 기준은 아래 "그래서 뭘 쓸까"에 적었다.

## 최종 설정

```
OLLAMA_FLASH_ATTENTION = 1
OLLAMA_KV_CACHE_TYPE   = q8_0
OLLAMA_CONTEXT_LENGTH  = 126976
```

## 1. 어떤 모델을 올릴 수 있나

<img src="../assets/model-pick-12gb.svg" width="620" alt="12GB에서 후보 모델 비교">

`bench/model-pick.ps1`로 네 후보를 같은 조건(context 16,384)에서 돌렸다.

| 모델 | 파일 | 실제 점유 | GPU 적재 | 생성 | 프롬프트 처리 | 로딩 |
|---|---|---|---|---|---|---|
| **ornith-1.5:9b** | 6.6GB | 5.69GB | **100%** | **54.4 tok/s** | 2,790 tok/s | 3.5초 |
| ornith:9b-q8_0 | 9.5GB | 8.51GB | 100% | 41.0 tok/s | 2,653 tok/s | 6.2초 |
| granite4.2:8b-q8_0 | 9.3GB | 11.42GB | 85% | 26.8 tok/s | 2,055 tok/s | 6.5초 |
| granite4.2:30b-q2_K | 10GB | 14.38GB | 68% | 10.4 tok/s | 541 tok/s | 8.3초 |

읽을 것은 세 번째 열이다. **파일 크기가 아니라 실제 점유량이 기준선을 넘는다.**
granite4.2:8b는 파일이 9.3GB로 12GB 안에 들어가는데, 올려보면 11.42GB를 요구해 15%가
CPU로 밀려난다. KV cache와 계산 버퍼가 같이 올라가기 때문이다.

30B을 2비트로 욱여넣는 쪽은 더 나쁘다. 68%만 GPU에 올라가 10.4 tok/s가 나온다.
같은 카드에서 9B을 4비트로 통째로 올리면 54.4 tok/s다. **5배 차이**다.
양자화를 내려서 큰 모델을 넣느니 모델을 줄여 전부 GPU에 올리는 쪽이 맞다.

## 2. context를 어디까지 올릴 수 있나

<img src="../assets/context-speed-12gb.svg" width="620" alt="context 길이별 생성 속도">

| context | 요구량 | GPU 적재 | 생성 속도 |
|---|---|---|---|
| 16,384 | 5.69GB | 100% | 54.7 tok/s |
| 65,536 | 7.14GB | 100% | 55.2 tok/s |
| 98,304 | 8.17GB | 100% | 54.7 tok/s |
| 122,880 | 8.94GB | 100% | 54.9 tok/s |
| **126,976** | **9.07GB** | **100%** | **55.1 tok/s** |
| 129,024 | 9.86GB | 91% | 53.9 tok/s |
| 131,072 | 9.92GB | 92% | 53.8 tok/s |
| 196,608 | 12.77GB | 65% | 19.4 tok/s |
| 262,144 | 15.15GB | 55% | 15.0 tok/s |

절벽은 126,976과 129,024 사이다. 2,048토큰을 더 주는 순간 요구량이 9.07GB에서 9.86GB로
뛴다. 0.79GB가 한 번에 늘어나는 것이니 선형으로 늘다가 넘치는 게 아니라 계단이다.
그래서 "조금씩 올려보며 맞추는" 방식이 통하지 않고, 훑어서 계단 위치를 찾아야 한다.

16GB 데스크톱 쪽이 24,576이었던 것과 비교하면 5.2배다. 카드는 더 작은데 context는 더
길다. 모델이 14GB에서 5.7GB로 줄어 남는 자리가 전부 KV cache로 갔기 때문이다.

준우승 모델도 같이 재봤다.

| 모델 | 100% GPU 최대 context | 그 지점 속도 |
|---|---|---|
| ornith-1.5:9b | 126,976 | 55.1 tok/s |
| ornith:9b-q8_0 | 53,248 | 41.4 tok/s |

## 3. 속도

권장 설정(context 126,976)에서 3회 측정했다.

| 항목 | 값 |
|---|---|
| 생성 속도 | 54.6 tok/s (54.7 / 54.6 / 54.5) |
| 프롬프트 처리 | 2,511 tok/s (2,450 / 2,536 / 2,547) |
| 모델 로딩 | 3.5초 |
| VRAM 점유 | 9.07 / 12.0GB, 100% GPU |

context를 16K에서 127K로 8배 늘려도 생성 속도는 54.7에서 55.1로 그대로다. GPU에 전부
올라가 있는 한 context 길이는 생성 속도에 영향을 주지 않는다.

## 4. 코딩

<img src="../assets/coding-bench-12gb.svg" width="620" alt="코딩 벤치마크 결과">

`bench/run.py`로 쟀다. 모델이 낸 코드를 파일로 저장한 뒤 숨긴 테스트와 함께 실제로
실행해 통과 여부를 본다.

| 모델 / 설정 | 통과 | 문제당 | 비고 |
|---|---|---|---|
| ornith:9b-q8_0 · thinking ON | **9 / 10** | 17초 | |
| ornith-1.5:9b · thinking ON | 7 / 10 | 39초 | 실패 3건 중 2건은 토큰 잘림 |
| ornith-1.5:9b · thinking OFF | 6 / 10 | 13초 | 1건은 채점 불가(아래 참고) |

**빠른 모델이 더 잘 푸는 게 아니었다.** 구세대를 q8로 올린 `ornith:9b-q8_0`이 25% 느리고
context도 절반 이하인데 2문제를 더 푼다. 게다가 답이 짧다. 최대 출력이 1,812토큰으로,
`ornith-1.5:9b`이 4,000토큰을 쓰고도 못 끝낸 문제를 803토큰으로 끝냈다.

`ornith-1.5:9b`이 실패한 3건은 성격이 다르다.

- `median_two_sorted` — 코드를 끝까지 냈는데 이분탐색 경계가 틀렸다. 진짜 오답.
- `regex`, `word_break` — 추론 도중 약 4,000토큰에서 잘렸다. 실력이 아니라 한도 문제다.

16GB 쪽에서 Qwen3.8-27B이 유일하게 실패했던 정수 계산기 파서(`calc`)는 여기서는 통과했다.
3,995토큰을 쓰고 70초가 걸렸으니 아슬아슬하게 한도 안쪽이었다.

## 5. 이미지 입력

16GB 쪽에서는 VRAM이 모자라 빼놓았던 항목인데, 여기서는 된다. `ornith-1.5:9b`에는
CLIP 프로젝터(456M)가 모델에 같이 들어 있어 따로 받을 것이 없다.

막대 3개짜리 차트 PNG를 넣고 제목과 각 막대의 라벨·값을 JSON으로 달라고 했더니
`Quarterly Revenue 2026` / Q1 120 / Q2 180 / Q3 90 을 전부 정확히 읽었다. 이미지는
181토큰으로 들어갔다.

| context | 점유 | GPU 적재 | 속도 | 값 정확도 |
|---|---|---|---|---|
| 126,976 | 9.07GB | 100% | 55.3 tok/s | 정확 |
| 65,536 | 7.14GB | 100% | 55.3 tok/s | 정확 |

권장 설정 그대로 두고 이미지를 넣어도 100% GPU가 유지된다. context를 낮출 필요가 없었다.

## 6. 그래서 뭘 쓸까

| 하려는 일 | 고를 것 | 이유 |
|---|---|---|
| 긴 파일·저장소를 통째로 넣기 | `ornith-1.5:9b` | 127K context가 100% GPU에 올라간다 |
| 이미지가 필요할 때 | `ornith-1.5:9b` | 비전이 포함돼 있고 추가 VRAM이 안 든다 |
| 정답률이 중요한 코딩 | `ornith:9b-q8_0` | 9/10 대 7/10, 답도 짧다 |
| 대화형 응답 속도 | `ornith-1.5:9b` | 54.6 대 41.0 tok/s |

둘 다 받아두고 쓰임에 따라 바꾸는 게 낫다. 합쳐서 16GB고, 디스크는 남는다.

## 겪은 문제

### `ollama pull`이 진행률 0에서 멈춘다

`ollama pull ornith-1.5:9b`가 5.4GB에서 멈춘 뒤 200초 넘게 한 바이트도 늘지 않았다.
`server.log`를 보면 원인이 보인다.

```
level=INFO source=download.go:384 msg="852922174ee4 part 8 stalled; retrying. ..."
level=INFO source=download.go:384 msg="852922174ee4 part 15 stalled; retrying. ..."
```

Ollama는 블롭 하나를 16개 파트로 나눠 병렬로 받는데, 그 16개가 전부 stall에 빠져
재시도만 반복했다. 끊고 다시 `ollama pull`을 해도 같은 자리에서 같은 일이 났다.

회선 문제는 아니었다. 같은 순간 같은 URL을 curl 단일 연결로 받으면 18.9 MB/s가 나왔다.

```
$ curl -r 0-52428799 https://registry.ollama.ai/v2/library/ornith-1.5/blobs/sha256:8529...
  speed=18886271 B/s  code=206
```

`OLLAMA_MAX_TRANSFER_STREAMS`라는 환경변수가 있지만 safetensors 전용이라
GGUF 블롭 다운로드에는 안 먹는다. 파트 수를 줄이는 방법이 없다.

그래서 [`setup/pull-curl.ps1`](../setup/pull-curl.ps1)을 만들었다. 레지스트리 매니페스트를
직접 읽어 블롭을 curl 단일 연결로 받고 Ollama의 블롭 저장소에 넣은 뒤 매니페스트를
써주는 스크립트다. 같은 회선에서 21.7 MB/s로 끝까지 받았다.

```powershell
pwsh -File setup/pull-curl.ps1 -Model ornith-1.5:9b
```

### 다운로드 진행 상황을 파일 크기로 보면 안 된다

받는 도중 `Get-ChildItem`으로 블롭 크기를 보면 계속 0바이트로 나온다. 멈춘 줄 알고
6분을 헤맸는데, Windows가 열려 있는 핸들에 대해 디렉터리 항목의 크기를 갱신하지 않기
때문이었다. 실제로는 그동안 8.47GB가 쓰이고 있었다. 핸들을 열어서 봐야 진짜 크기가 나온다.

```powershell
$fs = [IO.File]::Open($blob, 'Open', 'Read', 'ReadWrite'); $fs.Length; $fs.Close()
```

### thinking이 `thinking` 필드로 안 온다

Ollama 0.33.3에서 `"think": true`로 요청하면 추론이 별도 필드로 분리되지 않고
`response` 안에 섞여 나온다. 그것도 여는 태그 없이 닫는 태그만 붙은 채로.

| 모델 | 아키텍처 | `thinking` 필드 | `response` 안에 닫는 태그 |
|---|---|---|---|
| ornith-1.5:9b | qwen35 | 0자 | 있음 |
| granite4.2:8b-q8_0 | granite | 0자 | 있음 |

아키텍처가 다른 두 모델에서 똑같이 나오니 모델이 아니라 Ollama 쪽 동작으로 보인다.
16GB 쪽 기록(Ollama 0.32.15)에는 `think_chars`가 정상적으로 찍혀 있으니 그 사이에
바뀐 것 같다.

채점에 영향이 있다. `bench/run.py`는 응답에서 제일 긴 ```python 블록을 답으로 뽑는데,
추론이 섞여 들어오면 추론 중에 써본 긴 초안을 최종 답으로 착각한다. 닫는 태그가 있으면
그 뒤만 보도록 `strip_thinking()`을 넣어 고쳤다. thinking을 정상적으로 분리해 보내는
모델에서는 동작이 그대로다.

### ornith-1.5:9b 은 약 4,000토큰 넘게 못 쓴다

`num_predict`를 아무리 올려도 생성이 4,000토큰 언저리에서 `done_reason: length`로 끊긴다.
같은 프롬프트, 같은 시드로 세 번 재봤는데 출력이 토큰 하나까지 똑같았다.

| num_predict | eval_count | done_reason |
|---|---|---|
| 2,048 | 2,048 | length |
| 4,096 | 4,009 | length |
| 8,192 | 4,009 | length |
| 12,288 | 4,009 | length |

2,048은 정확히 지켜지니 값이 무시되는 게 아니라 `min(num_predict, 약 4,096)`로 잘리는 것이다.

Ollama 문제는 아니다. 같은 서버에서 `granite4.2:8b-q8_0`에 8,192를 주면 정확히 8,192가 나온다.
thinking 문제도 아니다. `think: false`로 숫자를 5,000개 출력시켜도 4,036에서 끊겼다.

원인으로 의심한 것이 하나 있었다. 이 모델의 레지스트리 매니페스트에는 `params` 레이어가
아예 없다.

| 모델 | 매니페스트 레이어 |
|---|---|
| ornith-1.5:9b | model, projector |
| ornith:9b-q8_0 | model, system, license, **params** |
| granite4.2:8b-q8_0 | model, license, **params** |

그래서 `ollama show --modelfile`에 `PARAMETER`가 한 줄도 안 나온다. stop 토큰도, 온도도 없다.
같은 계열인 `ornith:9b-q8_0`의 값(`stop <|im_end|>`, temperature 0.6, top_k 20, top_p 0.95)을
Modelfile로 채워 다시 만들어봤지만 **4,009에서 똑같이 잘렸다.** 원인은 다른 데 있다.
못 고쳤으니 그 Modelfile은 저장소에 넣지 않았다.

실질적인 영향은 이렇다. 긴 추론이 필요한 문제에서 답을 못 낸다. 코딩 10문제 중 2문제가
이것 때문에 실패했다. 에이전트로 돌릴 때 한 번에 긴 코드를 뽑아내는 용도로는 주의해야 한다.

### Ollama를 강제 종료하면 VRAM이 안 돌아온다

환경변수를 적용하려고 `ollama`와 `ollama app` 프로세스를 죽이고 다시 띄웠더니 VRAM
여유가 1,612 MiB밖에 안 됐다. `ollama ps`에는 올라온 모델이 없다고 나오는데도 그랬다.

자식 프로세스인 `llama-server.exe`가 안 죽고 남아 10.4GB를 쥐고 있었다. 새로 뜬 서버는
그 프로세스를 모르니 계속 남는다.

```powershell
Get-Process -Name 'llama-server' -EA SilentlyContinue | Stop-Process -Force
```

이걸 같이 죽여야 11,995 MiB가 돌아온다. 벤치마크 전에 확인할 것.

### 프롬프트 캐시가 속도 측정을 망친다

같은 프롬프트를 반복해서 프롬프트 처리 속도를 재면 안 된다. 2회차부터 캐시가 걸린다.

```
1회차: prompt_eval_count=33, cached=0
2회차: prompt_eval_count=33, cached=29
```

`count / duration`으로 계산하면 실제 처리 속도가 아니라 캐시 히트율이 나온다. 처음 재본
값은 이 때문에 691 tok/s로 나왔는데, 제대로 재니 2,790 tok/s였다. 4배 차이다.

고유 문자열을 프롬프트 맨 앞에 붙이는 것으로는 부족했다. Ollama 0.33.3의 캐시는 접두사가
달라도 재사용한다.

| 방식 | 1회차 | 2회차 | 3회차 |
|---|---|---|---|
| 맨 앞줄에만 고유값 | cached=0 · 2,042 tok/s | cached=2,046 · 67 tok/s | cached=2,046 · 82 tok/s |
| 모든 줄에 고유값 | cached=0 · 2,492 tok/s | cached=0 · 2,500 tok/s | cached=0 · 2,601 tok/s |

`bench/prompt-gen.ps1`이 모든 줄에 고유값을 섞은 2,050토큰짜리 프롬프트를 만들고,
`prompt_eval_cached_count`를 빼고 계산한다.

### `pwsh -File` 로는 콤마 목록을 못 넘긴다

`bench/ctx-sweep.ps1 -Sizes 8192,16384`처럼 쓰라고 문서에 적혀 있었는데 실행하면 이렇게 된다.

```
'Sizes' 매개 변수에 대한 인수 변환을 처리할 수 없습니다.
"8192,16384"을(를) 형식 "System.Int32[]"(으)로 변환할 수 없습니다.
```

`-File`로 실행하면 인자가 전부 문자열로 들어와서 `[int[]]`로 못 받는다. `-Command`로
부르면 되지만 문서화된 사용법이 안 되는 건 버그다. `[string]`으로 받아 직접 쪼개도록
`ctx-sweep.ps1`과 `model-pick.ps1`을 고쳤다.

### 생성이 도중에 끊기는 경우가 있다

`median_two_sorted`를 thinking OFF로 돌리면 응답이 792자에서 잘려 돌아온다. 그것도
`done: false`에 `eval_count`, `done_reason` 같은 통계 필드가 아예 없는 채로.

```
keys: ['created_at', 'done', 'model', 'response']
done = False
```

스트리밍이 아닌 `/api/generate` 호출인데 완료되지 않은 응답이 돌아온 것이다. 시드를 고정하면
매번 같은 자리에서 재현된다. 채점기 입장에서는 잘린 코드가 오니 SyntaxError로 떨어지는데,
이건 모델이 틀린 게 아니라 측정이 실패한 것이다. `bench/run.py`가 `done`을 확인해
`ABORTED`로 따로 표시하도록 고쳤다.

## 안 해본 것

- 원인을 못 찾은 4,000토큰 한도. GGUF 메타데이터를 뜯어보면 나올 수도 있다.
- `reasoning_effort`. `granite4.2`가 이 파라미터를 지원한다고 문서에 적혀 있는데 안 써봤다.
- 노트북 전원 프로필별 차이. 전부 어댑터 연결·성능 모드에서 쟀다. 배터리로 돌리면
  GPU 클럭이 떨어져 다른 값이 나올 것이다.
- 여러 모델 동시 적재(`OLLAMA_MAX_LOADED_MODELS`). 12GB로는 9B 두 개가 안 들어간다.
- OpenCode + Superpowers 연동. 16GB 쪽에서는 확인했지만 여기서는 안 돌려봤다.
