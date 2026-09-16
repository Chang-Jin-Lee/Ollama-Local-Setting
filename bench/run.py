import json, re, subprocess, sys, time, urllib.request, os, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from tasks import TASKS

MODEL = sys.argv[1] if len(sys.argv) > 1 else "qwen3.8-iq4"
OUT = pathlib.Path(__file__).parent / "out" / (MODEL.replace(":", "_") + ("" if os.environ.get("THINK","1")=="1" else "-nothink"))
OUT.mkdir(parents=True, exist_ok=True)

def gen(prompt, think=(os.environ.get("THINK","1")=="1")):
    body = json.dumps({
        "model": MODEL, "prompt": prompt, "stream": False, "think": think,
        "keep_alive": "20m", "options": {"num_predict": 4096, "seed": 7},
    }).encode()
    req = urllib.request.Request("http://127.0.0.1:11434/api/generate", body,
                                 {"Content-Type": "application/json"})
    t0 = time.time()
    r = json.load(urllib.request.urlopen(req, timeout=1800))
    return r, time.time() - t0

def extract_code(text):
    blocks = re.findall(r"```(?:python)?\s*\n(.*?)```", text, re.S)
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
    think_toks = len((r.get("thinking") or "")) // 4
    results.append({"id": tid, "pass": ok, "err": err, "sec": round(wall, 1),
                    "out_tokens": toks, "tps": round(tps, 1), "think_chars": len(r.get("thinking") or "")})
    print(f"{'PASS' if ok else 'FAIL'}  {tid:22s} {wall:6.1f}s  {toks:5d}tok  {tps:5.1f}t/s  {err}", flush=True)

passed = sum(r["pass"] for r in results)
print(f"\n== {MODEL}: {passed}/{len(results)} passed ==")
print(f"avg gen speed: {sum(r['tps'] for r in results)/len(results):.1f} tok/s")
print(f"total wall: {sum(r['sec'] for r in results):.0f}s, avg per task: {sum(r['sec'] for r in results)/len(results):.0f}s")
(OUT / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
