# 결과 보내기

다른 GPU에서 돌려본 결과를 모으는 게 이 저장소의 목적이다. 카드 하나당 파일 하나면 된다.

## 1. 자기 GPU의 한계선 찾기

```powershell
pwsh -File bench/ctx-sweep.ps1 -Model <모델명>
```

context를 훑으면서 모델이 100% GPU에 남는 최대값을 찾아준다. 이 값이 곧 그 카드의 설정값이다.
적재율은 `ollama ps` 표를 읽지 않고 `/api/ps`의 `size_vram / size`로 계산한다. 표는 반올림된
문자열이라 92%와 100%가 구분이 안 되는 경우가 있다.

VRAM이 16GB보다 작으면 모델부터 바꿔야 한다. 대략적인 기준은 이렇다.

| VRAM | 해볼 만한 것 |
|---|---|
| 24GB 이상 | Qwen3.8-27B Q4_K_M (18GB), context도 여유 |
| 16GB | Qwen3.8-27B IQ4_XS (14GB) — [측정됨](results/rtx4080-16gb.md) |
| 12GB | 9B급 Q4 (6~7GB). ornith-1.5:9b 로 124K context까지 — [측정됨](results/rtx4080-laptop-12gb.md) |
| 8GB | 9B급 Q4 를 context 낮춰서, 또는 8B급 |

**파일 크기를 VRAM에 맞추면 안 된다.** 가중치만 들어가는 게 아니라 KV cache와 계산
버퍼가 같이 올라가기 때문이다. 12GB 카드에서 재본 값이다.

| 모델 파일 | 실제 점유 (ctx 16K) | 결과 |
|---|---|---|
| 5.7GB | 5.69GB | 100% GPU |
| 8.5GB | 8.51GB | 100% GPU |
| 9.3GB | 11.42GB | 85% — CPU로 밀림 |
| 10GB | 14.38GB | 68% — CPU로 밀림 |

파일이 9.3GB일 때 실제로는 11.4GB를 먹는다. VRAM의 **60% 정도**를 모델 파일에 쓰고
나머지를 남겨두는 게 안전하다. 12GB면 7GB 안팎, 16GB면 9~10GB. 그보다 키우려면
context를 줄여 맞바꿔야 한다.

양자화를 내려 큰 모델을 욱여넣는 것도 답이 아니다. 12GB에서 30B을 Q2_K(10GB)로
올려봤더니 68% GPU에 10.7 tok/s가 나왔다. 같은 카드에서 9B Q4는 100% GPU에 54.8 tok/s다.
**5배 차이**다.

Unsloth의 [GGUF 저장소](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF)에 양자화별 파일이 다 있다.

## 2. 속도와 코딩 능력 재기

```powershell
pwsh -File bench/speed.ps1 -Model <모델명>
python bench/run.py <모델명>
```

`bench/run.py`는 알고리즘 10문제를 풀린 뒤 나온 코드를 실제로 실행해서 채점한다. 답을 채점자가 읽고 판단하는 방식이 아니라 테스트를 돌려 통과 여부를 본다.

## 3. 결과 올리기

`results/<gpu>-<vram>.md`를 만들어 PR을 보내거나, GPU 결과 이슈 템플릿으로 올리면 된다. `results/rtx4080-16gb.md`를 틀로 쓰면 편하다.

넣어주면 좋은 것:

- GPU 이름, VRAM, 드라이버 버전, Ollama 버전
- 쓴 모델과 양자화, 파일 크기
- 100% GPU를 유지하는 최대 context
- 생성 속도와 프롬프트 처리 속도
- 코딩 벤치마크 통과 개수
- 안 되던 것, 이상했던 것

특히 마지막 항목이 제일 쓸모 있다. 잘 된 설정보다 실패한 설정이 다음 사람의 시간을 아껴준다.
