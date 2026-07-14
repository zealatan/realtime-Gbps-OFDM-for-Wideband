#!/usr/bin/env python3
"""
gen_dashboards.py — regenerate the PHASE5 KPI/status + issue dashboards.
Single source of truth : status/dashboard.json
Auto-derived KPIs (when artifacts present, overriding dashboard.json):
    regression <- hil/agent_fsm/latest/rtl_regression_result.json
    Fmax       <- reports/timing_report.rpt
    resources  <- reports/utilization_report.rpt
Usage:  python3 scripts/gen_dashboards.py
"""
import argparse, json, os, re, sys, datetime

CSS = """
:root{--bg:#0d1117;--surf:#161b22;--surf2:#1c2230;--line:#2a313c;--line2:#363f4d;
--tx:#d8dee6;--tx2:#8b949e;--tx3:#636e7b;--teal:#3fd0c9;--green:#56d364;--amber:#e3b341;
--red:#f47067;--gray:#6e7681;--purple:#bc8cff;
--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
--sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,system-ui,sans-serif;}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--tx);font-family:var(--sans);line-height:1.55;
padding:28px 20px 60px;max-width:1180px;margin:0 auto;font-size:14px}
.eyebrow{font-family:var(--mono);font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--teal);margin-bottom:8px}
h1{font-size:21px;font-weight:600;letter-spacing:-.01em}
.goal{color:var(--tx2);margin-top:8px;max-width:780px}.goal b{color:var(--tx);font-weight:600}
.meta{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
.chip{font-family:var(--mono);font-size:11px;color:var(--tx2);border:1px solid var(--line2);border-radius:6px;padding:3px 9px;background:var(--surf2)}
.chip b{color:var(--teal);font-weight:500}
header{border:1px solid var(--line2);background:var(--surf);border-radius:12px;padding:20px 22px;margin-bottom:8px}
section{margin-top:26px}
h2{font-size:12px;font-family:var(--mono);letter-spacing:.12em;text-transform:uppercase;color:var(--tx3);margin-bottom:13px;display:flex;align-items:center;gap:10px}
h2::after{content:"";flex:1;height:1px;background:var(--line)}
.kpis{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.kpi{border:1px solid var(--line);background:var(--surf);border-radius:10px;padding:14px 15px}
.kpi .name{font-size:12.5px;color:var(--tx2);margin-bottom:9px;min-height:2.6em}
.kpi .val{display:flex;align-items:baseline;gap:8px;font-family:var(--mono)}
.kpi .cur{font-size:21px;font-weight:600}.kpi .arrow{color:var(--tx3)}.kpi .tgt{font-size:13px;color:var(--teal)}
.bar{height:5px;border-radius:3px;background:var(--surf2);margin-top:11px;overflow:hidden;border:1px solid var(--line)}
.bar>i{display:block;height:100%;border-radius:3px}
.st{font-family:var(--mono);font-size:10.5px;text-transform:uppercase;letter-spacing:.06em;margin-top:9px;display:inline-block}
.s-done{color:var(--green)}.s-prog{color:var(--amber)}.s-plan{color:var(--gray)}.s-block{color:var(--red)}
.f-green{background:var(--green)}.f-amber{background:var(--amber)}.f-gray{background:var(--gray)}.f-red{background:var(--red)}.f-teal{background:var(--teal)}
.cov{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.covcard{border:1px solid var(--line);background:var(--surf);border-radius:10px;padding:14px 15px}
.covcard h3{font-size:13px;font-weight:600;margin-bottom:4px}
.covcard p{font-size:12px;color:var(--tx3);font-family:var(--mono);margin-bottom:10px}
.covrow{display:flex;justify-content:space-between;font-size:12.5px;padding:4px 0;border-top:1px solid var(--line)}
.covrow span:last-child{font-family:var(--mono);color:var(--tx2)}
.chain{display:flex;align-items:stretch;overflow-x:auto;padding-bottom:6px}
.stage{flex:1;min-width:118px;border:1px solid var(--line);border-radius:9px;background:var(--surf);padding:11px 12px;position:relative}
.stage+.stage{margin-left:18px}
.stage::before{content:"";position:absolute;left:-18px;top:50%;width:18px;height:2px;background:var(--line2)}
.stage:first-child::before{display:none}.stage.lit::before{background:var(--teal)}
.stage .ph{font-family:var(--mono);font-size:10px;color:var(--tx3);letter-spacing:.08em}
.stage .ti{font-size:13px;font-weight:600;margin:3px 0 7px}
.dot{width:8px;height:8px;border-radius:50%;display:inline-block;margin-right:6px;vertical-align:middle}
.d-done{background:var(--green)}.d-prog{background:var(--amber);box-shadow:0 0 7px var(--amber)}.d-plan{background:var(--gray)}.d-block{background:var(--red);box-shadow:0 0 7px var(--red)}
.stage small{font-size:10.5px;font-family:var(--mono);text-transform:uppercase;letter-spacing:.05em}
.levels{display:grid;grid-template-columns:repeat(6,1fr);gap:10px}
.lvl{border:1px solid var(--line);border-radius:9px;background:var(--surf);padding:11px 10px;text-align:center}
.lvl .lid{font-family:var(--mono);font-size:11px;color:var(--teal)}
.lvl .ln{font-size:11.5px;color:var(--tx2);margin:5px 0 8px;min-height:2.6em}
.invhead{display:flex;align-items:center;gap:9px;padding:9px 0 7px}
.tag{font-family:var(--mono);font-size:10px;padding:2px 8px;border-radius:5px;font-weight:600}
.t-keep{background:rgba(86,211,100,.13);color:var(--green);border:1px solid rgba(86,211,100,.3)}
.t-new{background:rgba(63,208,201,.13);color:var(--teal);border:1px solid rgba(63,208,201,.3)}
.t-rewire{background:rgba(227,179,65,.13);color:var(--amber);border:1px solid rgba(227,179,65,.3)}
.t-remove{background:rgba(244,112,103,.13);color:var(--red);border:1px solid rgba(244,112,103,.3)}
.t-review{background:rgba(188,140,255,.13);color:var(--purple);border:1px solid rgba(188,140,255,.3)}
.files{font-family:var(--mono);font-size:11.5px;color:var(--tx2);line-height:1.9;padding:2px 0 10px}
.dec{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.decitem{border:1px solid var(--line);border-left:2px solid var(--teal);background:var(--surf);border-radius:0 8px 8px 0;padding:9px 13px;font-size:12.5px}
.decitem.tbd{border-left-color:var(--amber)}
.decitem b{color:var(--tx);font-family:var(--mono);font-size:11px}.decitem span{color:var(--tx2)}
.note{font-size:11px;color:var(--tx3);font-family:var(--mono);margin-top:8px}
footer{margin-top:34px;padding-top:16px;border-top:1px solid var(--line);font-family:var(--mono);font-size:11px;color:var(--tx3);display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px}
.counts{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0 20px}
.cnt{font-family:var(--mono);font-size:11px;border:1px solid var(--line2);border-radius:6px;padding:5px 11px;background:var(--surf);color:var(--tx2)}
.cnt b{font-size:14px;color:var(--tx);margin-right:5px}
.cnt .dt{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:6px;vertical-align:middle}
.filters{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:16px;align-items:center}
.flabel{font-family:var(--mono);font-size:10.5px;text-transform:uppercase;letter-spacing:.08em;color:var(--tx3)}
.fchip{font-family:var(--mono);font-size:11px;border:1px solid var(--line2);border-radius:14px;padding:4px 12px;background:var(--surf);color:var(--tx2);cursor:pointer;user-select:none;transition:.12s}
.fchip:hover{border-color:var(--tx3);color:var(--tx)}.fchip.on{background:var(--surf2);border-color:var(--teal);color:var(--teal)}
table{width:100%;border-collapse:collapse;font-size:13px}
thead th{font-family:var(--mono);font-size:10.5px;text-transform:uppercase;letter-spacing:.07em;color:var(--tx3);text-align:left;padding:8px 10px;border-bottom:1px solid var(--line2)}
tbody tr{border-bottom:1px solid var(--line)}tbody tr:hover{background:var(--surf)}
td{padding:11px 10px;vertical-align:top}
.id{font-family:var(--mono);font-size:11.5px;color:var(--tx3);white-space:nowrap}
.pill{font-family:var(--mono);font-size:10px;font-weight:600;padding:2px 8px;border-radius:5px;white-space:nowrap;display:inline-block}
.sev-critical{background:rgba(244,112,103,.15);color:var(--red);border:1px solid rgba(244,112,103,.35)}
.sev-high{background:rgba(227,179,65,.15);color:var(--amber);border:1px solid rgba(227,179,65,.35)}
.sev-medium{background:rgba(63,208,201,.13);color:var(--teal);border:1px solid rgba(63,208,201,.3)}
.sev-low{background:rgba(110,118,129,.18);color:var(--gray);border:1px solid rgba(110,118,129,.4)}
.stt{font-family:var(--mono);font-size:11px;white-space:nowrap}
.st-open{color:var(--amber)}.st-analyzed{color:var(--teal)}.st-resolved{color:var(--green)}.st-blocked{color:var(--red)}.st-deferred{color:var(--gray)}
.stt::before{content:"\\25CF";margin-right:6px;font-size:9px;vertical-align:middle}
.area{font-family:var(--mono);font-size:11px;color:var(--tx3)}
.ti2{font-weight:600;color:var(--tx);margin-bottom:3px}.de{font-size:12px;color:var(--tx2)}
.nx{font-size:12px;color:var(--tx2)}.hidden{display:none}
@media(max-width:820px){.kpis,.levels{grid-template-columns:repeat(2,1fr)}.cov,.dec{grid-template-columns:1fr}.col-area,.col-next{display:none}}
"""

FILL = {"done":"f-green","prog":"f-amber","plan":"f-gray","block":"f-red"}
SLAB = {"done":"done","prog":"in progress","plan":"planned","block":"blocked"}
DOT  = {"done":"d-done","prog":"d-prog","plan":"d-plan","block":"d-block"}
SEV_ORDER = {"critical":0,"high":1,"medium":2,"low":3}

def parse_regression(path):
    try:
        with open(path) as f: d = json.load(f)
        gates = d.get("gates") or d.get("results") or d.get("tests")
        if isinstance(gates, dict):
            vals = list(gates.values()); total = len(vals)
            passed = sum(1 for v in vals if str(v).upper() in ("PASS","PASSED","TRUE","OK") or v is True)
        elif isinstance(gates, list):
            # Prefer required-only ratio when any gate is explicitly
            # tagged required=True; otherwise count all gates.
            req = [g for g in gates if g.get("required") is True]
            pool = req if req else gates
            total = len(pool)
            passed = sum(1 for g in pool if str(g.get("status", g.get("result",""))).upper().startswith("PASS"))
        else: return None
        return passed, total
    except Exception: return None

def parse_timing(path):
    try:
        txt = open(path, errors="ignore").read()
        per = re.search(r"(?:Requirement|Clock Period)\s*[:=]?\s*([0-9.]+)\s*ns", txt, re.I)
        wns = re.search(r"WNS\D*([\-0-9.]+)", txt)
        if per and wns:
            ach = float(per.group(1)) - float(wns.group(1))
            if ach > 0: return round(1000.0/ach)
        mf = re.search(r"Max(?:imum)?\s*Frequency\D*([0-9.]+)\s*MHz", txt, re.I)
        if mf: return round(float(mf.group(1)))
    except Exception: pass
    return None

def parse_util(path):
    try:
        txt = open(path, errors="ignore").read(); bits = []
        for label, pat in (("LUT", r"CLB LUTs\D*\|\s*[0-9]+\D*\|\D*\|\s*([0-9.]+)"),
                           ("DSP", r"DSPs?\D*\|\s*[0-9]+\D*\|\D*\|\s*([0-9.]+)")):
            m = re.search(pat, txt)
            if m: bits.append(f"{label} {m.group(1)}%")
        return " · ".join(bits) if bits else None
    except Exception: return None

def parse_inv_count(path):
    """Parse the [INV_COUNT] line from the P5-D-CONT sim log.
    Returns a dict {key: (passed, total)} or None.
    Expected format:
      [INV_COUNT] frame_start=1/1 peak_index=1/1 timing_argmax=1/1 \
                  frac_cfo=1/1 cfo_int=1/1 corrected_stream=1/1
    """
    try:
        txt = open(path, errors="ignore").read()
    except Exception:
        return None
    # Match the LAST occurrence so re-runs override earlier prints.
    matches = re.findall(r"\[INV_COUNT\][^\n]*", txt)
    if not matches:
        return None
    line = matches[-1]
    out = {}
    for k, p, t in re.findall(r"(\w+)=(\d+)/(\d+)", line):
        out[k] = (int(p), int(t))
    return out or None

# Map the [INV_COUNT] keys to the dashboard.json coverage row labels.
INV_ROW_MAP = {
    "frame_start":      "frame start (int)",
    "peak_index":       "|P| & peak index",
    "timing_argmax":    "timing argmax (2|P|-E = ~sq_neg)",
    "frac_cfo":         "frac CFO (sign-corrected)",
    "cfo_int":          "cfo_int (fftshift decode)",
    "corrected_stream": "corrected stream (+1-slot)",
}

def apply_inv_counts(data, root):
    """Update the 'Equivalence invariants' coverage rows from the P5-D-CONT
    sim log [INV_COUNT] line, if present."""
    log_path = os.path.join(root, "vivado_xsim/logs/p5_d_cont_sim.log")
    inv = parse_inv_count(log_path)
    if not inv:
        return False
    for grp in data.get("coverage", []):
        if grp.get("group") != "Equivalence invariants":
            continue
        # Build a label->index map of existing rows so we update in place.
        # Row labels in dashboard.json sometimes use Unicode minus (−);
        # normalize for comparison.
        def norm(s): return s.replace("−", "-").strip()
        label_to_i = {norm(r[0]): i for i, r in enumerate(grp["rows"])}
        for key, (p, t) in inv.items():
            target_label = INV_ROW_MAP.get(key)
            if target_label is None:
                continue
            i = label_to_i.get(norm(target_label))
            if i is None:
                continue
            grp["rows"][i] = [grp["rows"][i][0], f"{p} / {t}"]
        return True
    return False

def apply_artifacts(data, root):
    for k in data["kpis"]:
        src = k.get("source")
        if src == "regression":
            r = parse_regression(os.path.join(root, "hil/agent_fsm/latest/rtl_regression_result.json"))
            if r:
                k["cur"] = f"{r[0]}/{r[1]}"; k["pct"] = round(100*r[0]/r[1]) if r[1] else 0
                k["status"] = "done" if r[0]==r[1] else "prog"
        elif src == "timing_report":
            f = parse_timing(os.path.join(root, "reports/timing_report.rpt"))
            if f:
                k["cur"] = str(f); k["pct"] = min(100, round(100*f/250))
                k["status"] = "done" if f>=250 else "prog"
        elif src == "util_report":
            u = parse_util(os.path.join(root, "reports/utilization_report.rpt"))
            if u: k["cur"] = u
    apply_inv_counts(data, root)
    return data

def esc(s):
    return str(s).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

def render_status(data):
    p = data["project"]
    kpi = "".join(
        f'<div class="kpi"><div class="name">{esc(k["name"])}</div>'
        f'<div class="val"><span class="cur">{esc(k["cur"])}</span><span class="arrow">&rarr;</span>'
        f'<span class="tgt">{esc(k["target"])}</span></div>'
        f'<div class="bar"><i class="{FILL[k["status"]]}" style="width:{k["pct"]}%"></i></div>'
        f'<div class="st s-{k["status"]}">{esc(k["note"])}</div></div>' for k in data["kpis"])
    cov = "".join(
        f'<div class="covcard"><h3>{esc(c["group"])}</h3><p>{esc(c["sub"])}</p>' +
        "".join(f'<div class="covrow"><span>{esc(a)}</span><span>{esc(b)}</span></div>' for a,b in c["rows"]) +
        "</div>" for c in data["coverage"])
    chain = "".join(
        f'<div class="stage{" lit" if s["status"] in ("done","prog") else ""}">'
        f'<div class="ph">{esc(s["id"])}</div><div class="ti">{esc(s["ti"])}</div>'
        f'<small class="s-{s["status"]}"><span class="dot {DOT[s["status"]]}"></span>{SLAB[s["status"]]}</small></div>'
        for s in data["phases"])
    lvl = "".join(
        f'<div class="lvl"><div class="lid">{esc(l["id"])}</div><div class="ln">{esc(l["ti"])}</div>'
        f'<small class="st s-{l["status"]}">{SLAB[l["status"]]}</small></div>' for l in data["levels"])
    inv = "".join(
        f'<div class="invhead"><span class="tag t-{i["tag"]}">{esc(i["label"])}</span></div>'
        f'<div class="files">{esc(i["files"])}</div>' for i in data["inventory"])
    dec = "".join(
        f'<div class="decitem{" tbd" if d["tbd"] else ""}"><b>{esc(d["k"])}</b> <span>{esc(d["v"])}</span></div>'
        for d in data["decisions"])
    return f"""<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{esc(p["name"])} — KPI &amp; status</title><style>{CSS}</style></head><body>
<header><div class="eyebrow">{esc(p["name"])} · 5G/NR OFDM frame synchronizer · ZCU102</div>
<h1>Synchronizer bring-up — KPI &amp; status</h1>
<p class="goal">Final goal: {esc(p["goal"])}</p>
<div class="meta"><span class="chip">part <b>{esc(p["part"])}</b></span>
<span class="chip">scope <b>synchronizer only</b></span><span class="chip">meyr <b>FFT-correlation</b></span>
<span class="chip">arch <b>continuous · option B</b></span><span class="chip">ref <b>receiver.c</b></span></div></header>
<section><h2>KPI tracking</h2><div class="kpis">{kpi}</div>
<p class="note">Bars show progress toward target. "—" = not yet measured. KPIs with a source are auto-filled from artifacts.</p></section>
<section><h2>Verification goals &amp; coverage</h2><div class="cov">{cov}</div></section>
<section><h2>Roadmap</h2><div class="chain">{chain}</div></section>
<section><h2>Verification levels</h2><div class="levels">{lvl}</div></section>
<section><h2>RTL consolidation — one DUT, deduplicated</h2>{inv}
<p class="note">complex_mult (16b) and complex_mult_32 (32b) are NOT duplicates. The single DUT uses exactly one Meyr (the FFT-correlation core).</p></section>
<section><h2>Decisions</h2><div class="dec">{dec}</div></section>
<footer><span>{esc(p["name"])} · {esc(p["root"])}</span><span>generated {datetime.date.today().isoformat()}</span></footer>
</body></html>"""

def render_issues(data):
    p = data["project"]
    issues = sorted(data["issues"], key=lambda i: SEV_ORDER.get(i["sev"], 9))
    counts = {s: sum(1 for i in issues if i["stt"]==s) for s in ("open","analyzed","resolved","blocked","deferred")}
    cdot = {"open":"var(--amber)","analyzed":"var(--teal)","resolved":"var(--green)","blocked":"var(--red)","deferred":"var(--gray)"}
    cnt = f'<span class="cnt"><b>{len(issues)}</b>total</span>' + "".join(
        f'<span class="cnt"><span class="dt" style="background:{cdot[s]}"></span><b>{counts[s]}</b>{s}</span>'
        for s in ("open","analyzed","resolved","blocked","deferred"))
    rows = "".join(
        f'<tr class="row" data-sev="{i["sev"]}" data-stt="{i["stt"]}">'
        f'<td class="id">{esc(i["id"])}</td><td><span class="pill sev-{i["sev"]}">{i["sev"]}</span></td>'
        f'<td class="stt st-{i["stt"]}">{i["stt"]}</td><td class="area col-area">{esc(i["area"])}</td>'
        f'<td><div class="ti2">{esc(i["ti"])}</div><div class="de">{esc(i["de"])}</div></td>'
        f'<td class="nx col-next">{esc(i["nx"])}</td></tr>' for i in issues)
    js = """
const setF=(cls)=>document.querySelectorAll(cls).forEach(c=>c.onclick=()=>{
 document.querySelectorAll(cls).forEach(x=>x.classList.remove('on'));c.classList.add('on');apply();});
function apply(){const sv=document.querySelector('.sevf.on').dataset.sev,st=document.querySelector('.sttf.on').dataset.stt;
 document.querySelectorAll('.row').forEach(r=>{const h=(sv!=='all'&&r.dataset.sev!==sv)||(st!=='all'&&r.dataset.stt!==st);r.classList.toggle('hidden',h);});}
setF('.sevf');setF('.sttf');"""
    def chips(cls, vals):
        return "".join(f'<span class="fchip {cls}{" on" if v=="all" else ""}" data-{cls[:3]}="{v}">{v}</span>' for v in vals)
    return f"""<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{esc(p["name"])} — issue tracker</title><style>{CSS}</style></head><body>
<div class="eyebrow">{esc(p["name"])} · issue tracker</div><h1>Open issues &amp; blockers</h1>
<div class="counts">{cnt}</div>
<div class="filters"><span class="flabel">sev</span>{chips("sevf", ["all","critical","high","medium","low"])}
<span class="flabel" style="margin-left:12px">status</span>{chips("sttf", ["all","open","analyzed","resolved","blocked","deferred"])}</div>
<table><thead><tr><th>ID</th><th>sev</th><th>status</th><th class="col-area">area</th><th>issue</th><th class="col-next">next action</th></tr></thead>
<tbody>{rows}</tbody></table>
<footer><span>{len(issues)} issues · generated {datetime.date.today().isoformat()}</span><span>single source of truth for PHASE5 blockers</span></footer>
<script>{js}</script></body></html>"""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="."); ap.add_argument("--data", default=None); ap.add_argument("--out", default=None)
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    data_path = a.data or os.path.join(root, "status", "dashboard.json")
    out_dir = a.out or root
    if not os.path.exists(data_path): sys.exit(f"[gen_dashboards] data not found: {data_path}")
    with open(data_path) as f: data = json.load(f)
    apply_artifacts(data, root)
    sp = os.path.join(out_dir, "p5_status_kpi_dashboard.html")
    ip = os.path.join(out_dir, "p5_issue_tracker.html")
    open(sp,"w").write(render_status(data)); open(ip,"w").write(render_issues(data))
    # Persist artifact-derived coverage updates back to dashboard.json so the
    # file remains the single source of truth across runs.
    with open(data_path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"[gen_dashboards] wrote {sp}"); print(f"[gen_dashboards] wrote {ip}")
    print(f"[gen_dashboards] persisted derived counts to {data_path}")

if __name__ == "__main__":
    main()
