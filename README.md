# Ollama Local Setting

그래픽카드별로 "이 카드에서는 이 모델을 이 설정으로 돌리면 된다"를 모으는 저장소다.

로컬 LLM을 깔아보면 늘 이 지점에서 막히지 않나. 모델 페이지는 "16GB VRAM 권장"이라고만 적어두고, 정작 내 카드에서 몇 토큰짜리 context까지 GPU에 올라가는지, 거기서 속도가 얼마나 나오는지, 그 속도로 실제 코딩을 시켜보면 쓸 만한지는 직접 재보기 전에는 알 수 없다. 그래서 직접 재봤다. 재는 스크립트와 결과를 같이 올려둔 게 이 저장소.

**같은 카드를 쓴다면** 설치 스크립트 하나로 똑같은 환경이 만들어진다. 명령 세 줄이면 끝. **다른 카드를 쓴다면** 벤치마크를 돌려 자기 카드의 값을 찾고, 그 결과를 여기에 보내주면 된다. 카드별 설정표를 채우는 게 목표다.

## 지금까지 모인 결과

| GPU | VRAM | 모델 | 최대 context (100% GPU) | 생성 속도 | 코딩 10문제 |
|---|---|---|---|---|---|
| [RTX 4080](results/rtx4080-16gb.md) | 16GB | Qwen3.8-27B IQ4_XS | 24,576 | 41.0 tok/s | 9 / 10 |

여기 자기 카드를 추가하려면 [CONTRIBUTING.md](CONTRIBUTING.md)를 보면 된다.

## 설치

Windows / PowerShell 7 기준이다. Ollama와 curl만 있으면 된다.

```powershell
git clone https://github.com/Chang-Jin-Lee/Ollama-Local-Setting.git
cd Ollama-Local-Setting
pwsh -File setup/install.ps1
```

환경변수를 잡고, GGUF 14GB를 받고, Ollama에 등록하고, OpenCode와 Superpowers까지 깐다. 끝나면 Ollama를 완전히 껐다 켜야 환경변수가 먹는다.

모델만 원하면 `-SkipAgent`, context를 직접 정하려면 `-Ctx 16384`을 붙이면 된다.

## RTX 4080 16GB에서 나온 수치

### context를 어디까지 올릴 수 있나

<img src="assets/context-speed.svg" width="620" alt="context 길이별 생성 속도">

VRAM 16GB에 13.3GiB짜리 모델을 올리면 남는 자리가 빠듯하다. 24K까지는 모델도 KV cache도 전부 VRAM에 들어가 41 tok/s가 나온다. 28K부터는 일부가 CPU로 밀려나면서 29 tok/s로 떨어진다. 그 사이가 절벽.

재미있는 건 VRAM을 비워도 소용없다는 점이다. 브라우저와 다른 프로그램을 다 꺼서 6GB를 더 확보한 뒤 32K를 재시도해도 결과는 93% GPU로 똑같았다. Ollama가 계산 버퍼 자리를 따로 떼어놓기 때문.

그러니 "VRAM이 남으니까 context를 더 주자"는 통하지 않는다. 카드마다 직접 훑어서 절벽 위치를 찾아야 한다. `bench/ctx-sweep.ps1`이 그걸 해준다.

### 실제로 코드를 짜게 시켜보면

<img src="assets/coding-bench.svg" width="620" alt="코딩 벤치마크 결과">

문제는 LeetCode Hard급 10개. 채점 방식은 이렇다. 모델이 내놓은 코드를 파일로 저장하고 숨겨둔 테스트와 함께 실제로 실행한다. 사람이나 다른 모델이 답을 읽고 판단하는 방식이 아니라는 뜻.

thinking을 켜면 10문제 중 9개를 통과한다. O(log(min(m,n))) 중앙값 문제는 랜덤 200케이스 교차검증을 통과했고, 스레드 안전 RateLimiter는 5스레드가 100회씩 동시에 때려도 정확히 50개만 허용했다. 대신 문제당 30초.

thinking을 끄면 9초로 줄지만 6개밖에 못 푼다. 품질 차이가 50%. 실제 작업에서는 켜두는 쪽이 맞다.

실패한 건 딱 하나. 단항 마이너스가 들어간 정수 계산기 파서였는데, thinking이 끝나질 않았다. 토큰 한도를 12,000으로 올려줬더니 42,940자를 생각하고도 답을 못 냈다. `--5` 같은 엣지 케이스에서 결론을 못 내고 자기 검증만 반복한 셈. 그런데 thinking을 끄니 41초 만에 통과. 에이전트로 돌리다 이게 터지면 한참 멈춘 것처럼 보이니, 그럴 땐 끊고 문제를 더 잘게 쪼개는 편이 낫다.

### 상용 모델과 비교하면

<img src="assets/tier-comparison.svg" width="620" alt="상용 모델과의 지능 지수 비교">

14GB짜리 파일 하나가 GPT-5.3 Codex와 Claude Opus 4.6 사이에 선다. GPT-5.4나 Opus 4.8에는 못 미치지만 Sonnet 4.6보다는 위.

다만 이건 단발 문제 기준. 여러 파일을 고치며 몇 시간씩 돌아가는 에이전트 작업은 DeepSWE 42.2점으로, Opus 4.8(59)이나 GPT-5.6 Sol(73)과 격차가 크다. 함수 하나 구현, 버그 하나 추적, 코드 리뷰처럼 잘게 쪼갠 일에 쓸 것.

양자화 손실은 걱정할 것 없다. 같은 모델을 양자화별로 비교한 [측정](https://quesma.com/blog/qwen38-27b-quantizations-benchmarked/)에서 4비트는 GPQA Diamond 85%로 BF16의 86%와 거의 같았고, Terminal-Bench는 75%로 동일했다. 무너지는 건 2비트 아래.

## 설치 중에 걸렸던 것들

문서대로 했는데 안 되는 지점이 몇 군데 있었다. 스크립트에는 이미 반영해둔 것들.

**`ollama pull hf.co/...`가 0%에서 멈춘다.** 허깅페이스에서 직접 받는 기능인데 파일을 미리 할당해놓고 그대로 멈춰 있었다. 진행률이 13GB로 보이는 게 함정. 그건 빈 파일 크기였다. `curl -L -C -`로 받아서 `ollama create`로 등록하는 편이 확실하다.

**npm이 OpenCode의 postinstall을 막는다.** `npm install -g opencode-ai`만 하면 `opencode --version`은 뜨는데 네이티브 바이너리가 안 깔린다. `--allow-scripts=opencode-ai`가 필요.

**Superpowers를 `--prefix` 없이 설치하면 엉뚱한 곳으로 간다.** 홈 디렉터리에 `package.json`이 있으면 npm이 거기까지 거슬러 올라가 설치해버리기 때문.

**OpenCode는 로컬 Ollama를 자동으로 찾지 못한다.** 설치 직후 `opencode models`에 Ollama 모델이 하나도 안 나왔다. `setup/opencode.json`처럼 provider를 직접 써줘야 잡히더라.

**공식 `qwen3.8:27b` 태그(18GB)는 16GB 카드에서 쓰면 안 된다.** 가중치만으로 VRAM을 넘겨 CPU로 밀려난다. 결과는 체감될 만큼 느린 속도. 같은 모델의 IQ4_XS(14GB)는 통째로 GPU에 올라가 훨씬 빠르게 돈다. 27B를 16GB에 억지로 욱여넣느니 양자화를 한 단계 내려 전부 GPU에 올리는 편이 낫다.

## 코딩 에이전트로 쓰기

설치 스크립트가 [OpenCode](https://opencode.ai)와 [Superpowers](https://github.com/obra/superpowers)까지 깔아준다. Superpowers는 브레인스토밍, 계획 수립, TDD, 디버깅, 코드 리뷰 워크플로를 스킬로 붙여주는 프레임워크다.

```powershell
cd <프로젝트 폴더>
opencode
```

RTX 4080에서 확인한 것: 스킬 14개 로드, 파일 쓰기와 셸 실행 동작, "TDD로 divide 함수를 추가해라"고 하자 테스트를 먼저 쓰고 실행해서 ImportError로 RED를 확인한 뒤 구현하고 GREEN을 확인하는 사이클이 지시 없이 돌았다. 작업 중에도 100% GPU를 유지했다.

## 이 저장소에 있는 것

```
setup/
  install.ps1                 한 번에 설치
  Modelfile.qwen3.8-iq4       렌더러·파서·샘플링 값이 들어간 Ollama Modelfile
  opencode.json               OpenCode에서 로컬 Ollama를 쓰는 설정
bench/
  ctx-sweep.ps1               context를 훑어 100% GPU 한계선 찾기
  speed.ps1                   생성 속도, 프롬프트 처리 속도, 로딩 시간
  run.py, tasks.py            알고리즘 10문제를 실행 채점
results/
  rtx4080-16gb.md             측정 기록 전문
```

## 참고한 곳

- [Unsloth Qwen3.8-27B GGUF](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF) — 양자화별 파일
- [Qwen3.8-27B 양자화 벤치마크](https://quesma.com/blog/qwen38-27b-quantizations-benchmarked/) — 4비트가 어디까지 버티는지
- [Artificial Analysis 지수](https://benchlm.ai/benchmarks/artificialanalysis) — 상용 모델 점수
- [Superpowers](https://github.com/obra/superpowers) · [OpenCode](https://opencode.ai)

MIT 라이선스다.
