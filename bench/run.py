import json, re, subprocess, sys, time, urllib.request, os, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from tasks import TASKS

MODEL = sys.argv[1] if len(sys.argv) > 1 else "qwen3.8-iq4"
# 추론이 response 안에 섞여 오는 모델은 이 한도를 추론과 답변이 나눠 씁니다.
# 한도에 걸려 잘린 것과 틀린 답을 구분하려고 done_reason 을 같이 기록합니다.
PREDICT = int(os.environ.get("PREDICT", "4096"))
OUT = (pathlib.Path(__file__).parent / "out" / (MODEL.replace(":", "_") + ("" if os.environ.get("THINK","1")=="1" else "-nothink") + f"-p{PREDICT}"))
OUT.mkdir(parents=True, exist_ok=True)

def gen(prompt, think=(os.environ.get("THINK","1")=="1")):
    body = json.dumps({
        "model": MODEL, "prompt": prompt, "stream": False, "think": think,
        "keep_alive": "20m", "options": {"num_predict": PREDICT, "seed": 7},
    }).encode()
    req = urllib.request.Request("http://127.0.0.1:11434/api/generate", body,
                                 {"Content-Type": "application/json"})
    t0 = time.time()
    r = json.load(urllib.request.urlopen(req, timeout=1800))
    return r, time.time() - t0

def strip_thinking(text):
    """thinking 을 별도 필드로 안 보내고 response 안에 섞어 보내는 모델이 있습니다.
    (ornith-1.5:9b + Ollama 0.33.3: 여는 태그 없이 닫는 태그만 붙어 나옵니다.)
    닫는 태그 뒤만 남겨야 추론 중의 초안 코드를 답으로 착각하지 않습니다."""
    marker = chr(60) + '/think' + chr(62)
    return text.rsplit(marker, 1)[-1] if marker in text else text

def extract_code(text):
    blocks = re.findall(r"```(?:python)?\s*\n(.*?)```", strip_thinking(text), re.S)
    return max(blocks, key=len) if blocks else text

results = []
for tid, prompt, test in TASKS:
    r, wall = gen(prompt)
    code = extract_code(r.get("response", ""))
    script = OUT / f"{tid}.py"
    script.write_text(code + "\n\n# ---- tests ----\n" + test, encoding="utf-8")
    (OUT / f"{tid}.raw.txt").write_text(
        "THINKING:\n" + (r.get("thinking") or "") + "\n\nRESPONSE:\n" + r.get("response", ""),
        encoding="utf-8")
    try:
        p = subprocess.run([sys.executable, str(script)], capture_output=True,
                           text=True, timeout=60)
        ok = p.returncode == 0
        err = (p.stderr or "").strip().splitlines()[-1][:120] if not ok else ""
    except subprocess.TimeoutExpired:
        ok, err = False, "TIMEOUT(60s)"
    toks = r.get("eval_count", 0)
    tps = toks / (r.get("eval_duration", 1) / 1e9)
    resp_raw = r.get("response", "")
    marker = chr(60) + '/think' + chr(62)
    inline_think = resp_raw.split(marker)[0] if marker in resp_raw else ""
    # Ollama 가 생성을 도중에 끊고 done:false 에 통계 필드 없이 돌려주는 경우가 있습니다.
    # 틀린 답이 아니라 측정 실패이므로 따로 표시합니다.
    aborted = not r.get("done", True)
    truncated = r.get("done_reason") == "length"
    if aborted:
        err = f"ABORTED (done:false, {len(r.get('response', ''))}자에서 끊김)"
    elif truncated and not ok:
        err = f"TRUNCATED at {toks} tok (PREDICT={PREDICT})"
    results.append({"id": tid, "pass": ok, "err": err, "sec": round(wall, 1),
                    "out_tokens": toks, "tps": round(tps, 1),
                    "done_reason": r.get("done_reason"), "truncated": truncated,
                    "aborted": aborted,
                    "think_chars": len(r.get("thinking") or "") + len(inline_think)})
    print(f"{'PASS' if ok else 'FAIL'}  {tid:22s} {wall:6.1f}s  {toks:5d}tok  {tps:5.1f}t/s  {err}", flush=True)

passed = sum(r["pass"] for r in results)
trunc = sum(r["truncated"] and not r["pass"] for r in results)
abort = sum(r["aborted"] for r in results)
print(f"\n== {MODEL}: {passed}/{len(results)} passed ==")
if abort:
    print(f"   {abort}건은 Ollama 가 생성을 중단해(done:false) 채점 자체가 안 된 것입니다.")
if trunc:
    print(f"   실패 {len(results)-passed}건 중 {trunc}건은 토큰 한도({PREDICT})에 걸려 잘린 것입니다.")
print(f"avg gen speed: {sum(r['tps'] for r in results)/len(results):.1f} tok/s")
print(f"total wall: {sum(r['sec'] for r in results):.0f}s, avg per task: {sum(r['sec'] for r in results)/len(results):.0f}s")
(OUT / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
