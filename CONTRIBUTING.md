# 결과 보내기

다른 GPU에서 돌려본 결과를 모으는 게 이 저장소의 목적이다. 카드 하나당 파일 하나면 된다.

## 1. 자기 GPU의 한계선 찾기

```powershell
pwsh -File bench/ctx-sweep.ps1 -Model <모델명>
```

context를 훑으면서 `ollama ps`의 PROCESSOR가 `100% GPU`를 유지하는 최대값을 찾아준다. 이 값이 곧 그 카드의 설정값.

VRAM이 16GB보다 작으면 모델부터 바꿔야 한다. 대략적인 기준은 이렇다.

| VRAM | 해볼 만한 것 |
|---|---|
| 24GB 이상 | Qwen3.8-27B Q4_K_M (18GB), context도 여유 |
| 16GB | Qwen3.8-27B IQ4_XS (14GB) — 이 저장소 기본값 |
| 12GB | Qwen3.8-27B UD-IQ3_S (12GB) 또는 gpt-oss:20b |
| 8GB | 14B 이하 |

Unsloth의 [GGUF 저장소](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF)에 양자화별 파일이 다 있다. 파일 크기가 VRAM보다 2~3GB 작은 걸 고르면 KV cache와 계산 버퍼 자리가 남는다.

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
