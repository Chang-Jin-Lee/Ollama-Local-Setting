"""OpenAI 호환 서버(Strata, llama.cpp server 등)의 프롬프트 처리 속도와 생성 속도를 길이별로 잽니다.

Strata README 의 표와 같은 방식입니다: 길이마다 코드 프롬프트 하나, 256토큰 생성.
서버가 llama.cpp 형식의 timings 를 돌려줘야 프롬프트/생성 시간을 나눠 볼 수 있습니다.

  python bench/speed_openai.py
  python bench/speed_openai.py --base-url http://127.0.0.1:8080/v1 --lengths 1000,4000,32000,60000
"""
import argparse, json, pathlib, time, urllib.request, uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent


def source_text():
    """저장소 안의 코드와 문서를 이어 붙인 텍스트. MoE 는 내용에 따라 쓰는 expert 가 달라
    속도가 바뀌므로, 공식 측정처럼 실제 코드를 씁니다."""
    parts = []
    for p in sorted(ROOT.rglob("*")):
        if p.suffix in (".py", ".ps1", ".md") and "out" not in p.parts and ".git" not in p.parts:
            parts.append(f"\n# ===== {p.relative_to(ROOT)} =====\n" + p.read_text(encoding="utf-8", errors="ignore"))
    return "".join(parts)


def build_prompt(src, approx_tokens):
    # 이 저장소의 텍스트(코드 + 한국어 문서)는 Qwen 토크나이저로 약 2.3자당 1토큰이었습니다.
    # 실제 길이는 응답의 usage 로 확인합니다.
    need = int(approx_tokens * 2.3)
    body = (src * (need // len(src) + 1))[:need]
    # 맨 앞에 매번 다른 값을 넣어 서버의 대화 캐시가 이전 측정의 앞부분을 재사용하지 못하게 합니다.
    return f"[run {uuid.uuid4()}]\n{body}\n\n위 코드에서 가장 위험해 보이는 부분 하나를 골라 이유를 설명해줘."


def measure(base_url, key, prompt, tokens):
    body = json.dumps({"model": "bench", "messages": [{"role": "user", "content": prompt}],
                       "max_tokens": tokens, "stream": False, "reasoning_effort": "none"}).encode()
    req = urllib.request.Request(base_url.rstrip("/") + "/chat/completions", body,
                                 {"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    t0 = time.time()
    r = json.load(urllib.request.urlopen(req, timeout=3600))
    wall = time.time() - t0
    t, u = r.get("timings") or {}, r.get("usage") or {}
    return {"prompt_tokens": u.get("prompt_tokens"), "completion_tokens": u.get("completion_tokens"),
            "prompt_tps": t.get("prompt_per_second"), "gen_tps": t.get("predicted_per_second"),
            "draft_accept": (round(t["draft_n_accepted"] / t["draft_n"], 2) if t.get("draft_n") else None),
            "wall_s": round(wall, 1)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:8080/v1")
    ap.add_argument("--api-key", default="none")
    ap.add_argument("--lengths", default="1000,4000,32000,60000")
    ap.add_argument("--tokens", type=int, default=256)
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    src = source_text()
    # 첫 요청은 모델을 깨우는 비용이 섞이니 버립니다.
    measure(a.base_url, a.api_key, build_prompt(src, 200), 16)

    rows = []
    print(f"{'목표':>7} {'실제 프롬프트':>12} {'프롬프트 tok/s':>14} {'생성 tok/s':>10} {'MTP 적중':>8} {'벽시계':>7}")
    for n in (int(x) for x in a.lengths.split(",")):
        row = {"target": n, **measure(a.base_url, a.api_key, build_prompt(src, n), a.tokens)}
        rows.append(row)
        print(f"{n:>7} {row['prompt_tokens'] or '-':>12} {row['prompt_tps'] or '-':>14} "
              f"{row['gen_tps'] or '-':>10} {row['draft_accept'] or '-':>8} {row['wall_s']:>6}s", flush=True)
    if a.out:
        pathlib.Path(a.out).write_text(json.dumps(rows, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
