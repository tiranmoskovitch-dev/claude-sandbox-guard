"""
Sandbox Guard Dashboard — Free Edition
Start: python dashboard.py
Open:  http://localhost:7777
"""

import http.server
import json
import re
import os
import socketserver
import webbrowser
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# ── Self-locate ──────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
LOG_DIR = SCRIPT_DIR / "logs"
COMMANDS_LOG = LOG_DIR / "commands.log"
BLOCKED_LOG = LOG_DIR / "blocked.log"
HOOK_PATH = SCRIPT_DIR / "sandbox-guard.sh"
SETTINGS_PATH = Path.home() / ".claude" / "settings.json"
PORT = 7777


# ═══════════════════════════════════════════════════════════════════
# LOG PARSING
# ═══════════════════════════════════════════════════════════════════

def parse_commands_log():
    entries = []
    if not COMMANDS_LOG.exists():
        return entries
    try:
        with open(COMMANDS_LOG, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                m = re.match(r"\[(.+?) UTC\]\s+(OK|CONTAINED)\s+\|\s+(.*)", line)
                if m:
                    entries.append({
                        "timestamp": m.group(1),
                        "status": m.group(2),
                        "reason": m.group(3).split(" | ")[0] if m.group(2) == "CONTAINED" else "",
                        "command": m.group(3).split(" | ")[-1] if " | " in m.group(3) else m.group(3),
                    })
    except Exception:
        pass
    return entries


def parse_blocked_log():
    entries = []
    if not BLOCKED_LOG.exists():
        return entries
    try:
        with open(BLOCKED_LOG, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                m = re.match(r"\[(.+?) UTC\]\s+BLOCKED\s+\|\s+(.*)", line)
                if m:
                    rest = m.group(2)
                    parts = rest.split(" | ")
                    reason = parts[0]
                    command = ""
                    alternative = ""
                    if len(parts) >= 2:
                        if parts[-1].startswith("ALT: "):
                            alternative = parts[-1][5:]
                            command = " | ".join(parts[1:-1])
                        else:
                            command = " | ".join(parts[1:])
                    entries.append({
                        "timestamp": m.group(1),
                        "status": "BLOCKED",
                        "reason": reason,
                        "command": command,
                        "alternative": alternative,
                    })
    except Exception:
        pass
    return entries


def get_guard_status():
    hook_exists = HOOK_PATH.exists()
    hook_configured = False
    try:
        with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
            settings = json.load(f)
            hooks = settings.get("hooks", {}).get("PreToolUse", [])
            hook_configured = any("sandbox-guard" in json.dumps(h) for h in hooks)
    except Exception:
        pass
    if hook_exists and hook_configured:
        return "ACTIVE"
    elif not hook_exists:
        return "HOOK FILE MISSING"
    else:
        return "NOT IN SETTINGS"


def classify_command(cmd):
    cl = cmd.lower().strip()
    if cl.startswith("git "):
        return "git"
    if cl.startswith(("npm ", "pip ", "cargo ", "dotnet ")):
        return "package"
    if cl.startswith(("python ", "node ", "python3 ")):
        return "script"
    if cl.startswith(("ls ", "dir ", "find ", "tree ")):
        return "browse"
    if cl.startswith(("cat ", "head ", "tail ", "wc ", "grep ")):
        return "read"
    if cl.startswith(("curl ", "wget ")):
        return "network"
    if cl.startswith(("docker ", "docker-compose ")):
        return "docker"
    if cl.startswith(("mkdir ", "touch ", "cp ", "mv ")):
        return "filesystem"
    return "other"


def get_stats():
    ok_entries = parse_commands_log()
    blocked_entries = parse_blocked_log()
    total_contained = sum(1 for e in ok_entries if e["status"] == "CONTAINED")
    total = len(ok_entries) + len(blocked_entries)
    total_blocked = len(blocked_entries)
    blocked_pct = (total_blocked / total * 100) if total > 0 else 0

    now = datetime.now(timezone.utc)
    recent = 0
    for e in ok_entries + blocked_entries:
        try:
            ts = datetime.strptime(e["timestamp"], "%Y-%m-%d %H:%M:%S")
            ts = ts.replace(tzinfo=timezone.utc)
            if (now - ts).total_seconds() <= 600:
                recent += 1
        except Exception:
            pass

    return {
        "total_commands": total,
        "total_blocked": total_blocked,
        "total_contained": total_contained,
        "blocked_pct": round(blocked_pct, 1),
        "guard_status": get_guard_status(),
        "commands_per_minute": round(recent / 10.0, 1),
    }


def get_activity(limit=100):
    ok_entries = parse_commands_log()
    blocked_entries = parse_blocked_log()
    all_entries = ok_entries + blocked_entries
    all_entries.sort(key=lambda e: e["timestamp"])

    for e in all_entries:
        if e["status"] == "CONTAINED":
            e["cmd_category"] = "contained"
        elif e["status"] != "BLOCKED":
            e["cmd_category"] = classify_command(e["command"])

    return all_entries[-limit:][::-1]


# ═══════════════════════════════════════════════════════════════════
# HTTP HANDLER
# ═══════════════════════════════════════════════════════════════════

class DashboardHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)

        if path == "/":
            self._send_html(DASHBOARD_HTML)
        elif path == "/api/stats":
            self._send_json(get_stats())
        elif path == "/api/activity":
            limit = int(qs.get("limit", [100])[0])
            self._send_json(get_activity(limit))
        else:
            self.send_response(404)
            self.end_headers()

    def _send_html(self, content):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(content.encode("utf-8"))

    def _send_json(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def log_message(self, format, *args):
        pass


# ═══════════════════════════════════════════════════════════════════
# DASHBOARD HTML — FREE EDITION
# ═══════════════════════════════════════════════════════════════════

DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Sandbox Guard Dashboard</title>
<style>
* { margin:0; padding:0; box-sizing:border-box; }
:root {
  --bg:#08080f; --card:#0d0d16; --card2:#111119; --border:#1a1a2e;
  --text:#d0d0d0; --dim:#555; --green:#00ff88; --red:#ff4455;
  --yellow:#ffaa00; --blue:#4488ff; --purple:#aa66ff; --orange:#ff8844;
  --cyan:#44ddff;
  --mono:'Consolas','Courier New',monospace;
}
body { background:var(--bg); color:var(--text); font-family:var(--mono); padding:16px; font-size:13px; }

/* Header */
.hdr { display:flex; justify-content:space-between; align-items:center; padding:14px 20px; background:var(--card); border:1px solid var(--border); border-radius:8px; margin-bottom:14px; }
.hdr h1 { font-size:15px; letter-spacing:2px; text-transform:uppercase; }
.hdr-right { display:flex; align-items:center; gap:16px; }
.status-badge { display:flex; align-items:center; gap:8px; font-size:12px; font-weight:bold; padding:4px 12px; border-radius:20px; }
.status-badge.active { background:#0a2a1a; border:1px solid #00ff8844; color:var(--green); }
.status-badge.inactive { background:#2a0a0a; border:1px solid #ff445544; color:var(--red); }
.dot { width:8px; height:8px; border-radius:50%; }
.dot.active { background:var(--green); box-shadow:0 0 6px var(--green); animation:pulse 2s infinite; }
.dot.inactive { background:var(--red); box-shadow:0 0 6px var(--red); }
@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.3} }
.shield { font-size:11px; color:var(--green); padding:4px 10px; border:1px solid #0a2a1a; border-radius:4px; background:#050f0a; }
.shield.warn { color:var(--yellow); border-color:#2a1a0a; background:#0f0a05; }

/* Stat Cards */
.stats { display:grid; grid-template-columns:repeat(5,1fr); gap:10px; margin-bottom:14px; }
.sc { background:var(--card); border:1px solid var(--border); border-radius:8px; padding:14px; text-align:center; }
.sc .val { font-size:28px; font-weight:bold; }
.sc .lbl { font-size:10px; color:var(--dim); text-transform:uppercase; letter-spacing:1px; margin-top:2px; }
.sc.green .val{color:var(--green)} .sc.red .val{color:var(--red)} .sc.yellow .val{color:var(--yellow)} .sc.blue .val{color:var(--blue)}

/* Upgrade Banner */
.upgrade { background:linear-gradient(135deg, #1a0a2a 0%, #0a1a2a 100%); border:1px solid var(--purple); border-radius:8px; padding:16px 20px; margin-bottom:14px; display:flex; justify-content:space-between; align-items:center; }
.upgrade-text h3 { color:var(--purple); font-size:13px; letter-spacing:1px; text-transform:uppercase; margin-bottom:4px; }
.upgrade-text p { color:var(--dim); font-size:11px; }
.upgrade-btn { background:var(--purple); color:#fff; border:none; padding:8px 20px; border-radius:6px; font-family:var(--mono); font-size:12px; font-weight:bold; cursor:pointer; text-decoration:none; letter-spacing:1px; }
.upgrade-btn:hover { background:#bb77ff; }

/* Blocked List */
.blocked-panel { background:var(--card); border:1px solid var(--border); border-radius:8px; padding:14px; margin-bottom:14px; }
.blocked-panel h2 { font-size:12px; text-transform:uppercase; letter-spacing:1.5px; color:var(--dim); margin-bottom:10px; display:flex; align-items:center; gap:8px; }
.blocked-panel h2 .ct { color:var(--red); }
.blocked-table { width:100%; border-collapse:collapse; font-size:11px; }
.blocked-table th { text-align:left; padding:6px 8px; border-bottom:1px solid var(--border); color:var(--dim); font-size:10px; text-transform:uppercase; letter-spacing:.5px; }
.blocked-table td { padding:6px 8px; border-bottom:1px solid #0d0d14; }
.blocked-table .ts { color:var(--dim); white-space:nowrap; width:140px; }
.blocked-table .reason { color:var(--red); }
.blocked-table .cmd { max-width:400px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.blocked-table .alt { color:var(--green); max-width:300px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:10px; }

/* Activity */
.act-panel { background:var(--card); border:1px solid var(--border); border-radius:8px; padding:14px; }
.act-panel h2 { font-size:12px; text-transform:uppercase; letter-spacing:1.5px; color:var(--dim); margin-bottom:10px; }
.act-wrap { max-height:350px; overflow-y:auto; }
.act-wrap::-webkit-scrollbar { width:5px; }
.act-wrap::-webkit-scrollbar-thumb { background:#333; border-radius:3px; }
.act-table { width:100%; border-collapse:collapse; font-size:11px; }
.act-table td { padding:4px 8px; border-bottom:1px solid #0d0d14; }
.act-table .ts { color:var(--dim); white-space:nowrap; width:140px; }
.act-table .cmd { max-width:550px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.badge { padding:2px 6px; border-radius:3px; font-size:9px; font-weight:bold; letter-spacing:.5px; }
.badge.ok { background:#0a2a1a; color:var(--green); }
.badge.blocked { background:#2a0a0a; color:var(--red); }
.badge.contained { background:#1a1a0a; color:var(--yellow); }
.row-b { background:#110505; }
.row-c { background:#0f0f05; }
.cat-badge { padding:1px 5px; border-radius:3px; font-size:9px; color:var(--dim); background:#111; margin-left:4px; }

.footer { text-align:center; color:var(--dim); font-size:10px; margin-top:14px; }
.footer span { color:var(--green); }
.empty { color:var(--dim); font-size:12px; padding:20px; text-align:center; }
</style>
</head>
<body>

<div class="hdr">
  <h1>Sandbox Guard Dashboard</h1>
  <div class="hdr-right">
    <div class="shield" id="shield">SYSTEM SECURE</div>
    <div class="status-badge active" id="status-badge">
      <span class="dot active" id="status-dot"></span>
      <span id="status-text">CHECKING...</span>
    </div>
  </div>
</div>

<div class="stats">
  <div class="sc green"><div class="val" id="total">-</div><div class="lbl">Total Commands</div></div>
  <div class="sc red"><div class="val" id="blocked">-</div><div class="lbl">Blocked</div></div>
  <div class="sc yellow"><div class="val" id="contained">0</div><div class="lbl">Contained</div></div>
  <div class="sc yellow"><div class="val" id="pct">-</div><div class="lbl">Block Rate</div></div>
  <div class="sc blue"><div class="val" id="rate">-</div><div class="lbl">Cmds / Min</div></div>
</div>

<div class="upgrade">
  <div class="upgrade-text">
    <h3>Upgrade to Sandbox Guard Pro</h3>
    <p>Threat intelligence, risk analysis, expandable event cards, verdict tracking, command context windows</p>
  </div>
  <a class="upgrade-btn" href="https://whop.com/tiran-ai-tech/" target="_blank">GET PRO</a>
</div>

<div class="blocked-panel">
  <h2>Blocked Commands <span class="ct" id="blocked-count"></span></h2>
  <div class="act-wrap">
    <table class="blocked-table">
      <thead><tr><th>Time</th><th>Reason</th><th>Command</th><th>Safe Alternative</th></tr></thead>
      <tbody id="blocked-body"></tbody>
    </table>
  </div>
</div>

<div class="act-panel">
  <h2>Command Activity Log</h2>
  <div class="act-wrap">
    <table class="act-table"><tbody id="act-body"></tbody></table>
  </div>
</div>

<div class="footer">Auto-refreshing every <span>3s</span> &mdash; Sandbox Guard Free Edition &mdash; All blocked commands are <span>fully stopped</span> (exit code 2, never executed)</div>

<script>
const R=3000;
function esc(s){const d=document.createElement('div');d.textContent=s||'';return d.innerHTML;}

async function refresh(){
  try{
    const [sr,ar]=await Promise.all([fetch('/api/stats'),fetch('/api/activity?limit=200')]);
    const stats=await sr.json(), activity=await ar.json();
    updateStats(stats);
    updateBlocked(activity.filter(a=>a.status==='BLOCKED'));
    updateActivity(activity);
  }catch(e){
    document.getElementById('status-dot').className='dot inactive';
    document.getElementById('status-text').textContent='CONNECTION LOST';
    document.getElementById('status-badge').className='status-badge inactive';
  }
}

function updateStats(s){
  document.getElementById('total').textContent=s.total_commands;
  document.getElementById('blocked').textContent=s.total_blocked;
  document.getElementById('contained').textContent=s.total_contained;
  document.getElementById('pct').textContent=s.blocked_pct+'%';
  document.getElementById('rate').textContent=s.commands_per_minute;

  const dot=document.getElementById('status-dot'),
        txt=document.getElementById('status-text'),
        badge=document.getElementById('status-badge'),
        shield=document.getElementById('shield');

  if(s.guard_status==='ACTIVE'){
    dot.className='dot active';txt.textContent='GUARD ACTIVE';
    badge.className='status-badge active';
    const msg=s.total_contained>0?'SYSTEM SECURE \u2014 '+s.total_contained+' CONTAINED':'SYSTEM SECURE';
    shield.textContent=msg; shield.className='shield';
  }else{
    dot.className='dot inactive';txt.textContent=s.guard_status;
    badge.className='status-badge inactive';
    shield.textContent='GUARD OFFLINE'; shield.className='shield warn';
  }
}

function updateBlocked(blocked){
  const el=document.getElementById('blocked-body');
  document.getElementById('blocked-count').textContent=blocked.length?'('+blocked.length+')':'';
  if(!blocked.length){el.innerHTML='<tr><td colspan="4" class="empty">No blocked commands &mdash; all clear</td></tr>';return;}
  el.innerHTML=blocked.map(e=>`<tr>
    <td class="ts">${esc(e.timestamp)}</td>
    <td class="reason">${esc(e.reason)}</td>
    <td class="cmd" title="${esc(e.command)}">${esc(e.command)}</td>
    <td class="alt" title="${esc(e.alternative||'')}">${esc(e.alternative||'-')}</td>
  </tr>`).join('');
}

function updateActivity(entries){
  const el=document.getElementById('act-body');
  if(!entries.length){el.innerHTML='<tr><td colspan="3" class="empty">No activity</td></tr>';return;}
  el.innerHTML=entries.slice(0,100).map(e=>{
    const cat=e.cmd_category?`<span class="cat-badge">${e.cmd_category}</span>`:'';
    const rc=e.status==='BLOCKED'?'row-b':e.status==='CONTAINED'?'row-c':'';
    return `<tr class="${rc}">
      <td class="ts">${esc(e.timestamp)}</td>
      <td><span class="badge ${e.status.toLowerCase()}">${e.status}</span></td>
      <td class="cmd" title="${esc(e.command)}">${esc(e.command)}${cat}</td>
    </tr>`;
  }).join('');
}

setInterval(refresh,R);refresh();
</script>
</body>
</html>"""


# ═══════════════════════════════════════════════════════════════════
# SERVER
# ═══════════════════════════════════════════════════════════════════

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

if __name__ == "__main__":
    print(f"  Sandbox Guard Dashboard (Free Edition)")
    print(f"  Dashboard:  http://localhost:{PORT}")
    print(f"  Logs:       {LOG_DIR}")
    print(f"  Ctrl+C to stop")
    print()
    webbrowser.open(f"http://localhost:{PORT}")
    with ReusableTCPServer(("", PORT), DashboardHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n  Dashboard stopped.")
