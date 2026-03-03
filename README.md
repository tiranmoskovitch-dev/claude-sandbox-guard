# Sandbox Guard for Claude Code

**Contain, Teach, Protect** — A safety hook that lets Claude Code work freely while protecting your system from destructive commands.

## The Problem

Claude Code executes shell commands on your machine. It's powerful, but one wrong `rm -rf /` or `curl | bash` could ruin your day. Existing solutions either:
- Block too much (slows down the AI, you keep clicking "approve")
- Block too little (one bad command gets through)

## How Sandbox Guard Works

Sandbox Guard is a **PreToolUse hook** — it inspects every Bash command *before* execution. It uses a philosophy of **containment over blocking**:

1. **ALLOW** — Normal dev commands pass through instantly (zero latency)
2. **CONTAIN** — Risky ops (like `rm -rf`) are allowed *inside your safe zone* (your dev directory, backed by git)
3. **TEACH** — When blocking, the AI gets a safe alternative via stderr so it can retry correctly
4. **BLOCK** — Only truly irreversible system-level destruction is hard-blocked

The AI never gets stuck. It either succeeds or gets told exactly how to succeed safely.

## 9 Security Rules

| # | Rule | What's Blocked | What's Allowed |
|---|------|---------------|----------------|
| 1 | Pipe-to-Execute | `curl \| bash`, `wget \| python` | Localhost pipes, formatting tools (`jq`, `head`) |
| 2 | Encoded Execution | Base64-decoded payloads, `powershell -enc` | Plain text commands |
| 3 | System Destruction | `format C:`, `diskpart`, `bcdedit`, `mkfs` | — |
| 4 | Recursive Deletion | `rm -rf /`, `rm -rf ~`, system drives | `rm -rf` inside your safe zone |
| 5 | System Paths | Write/delete in `/Windows`, `/usr/bin`, etc. | Read-only access |
| 6 | Registry & Services | `reg add`, `sc create`, `schtasks`, `iptables` | — |
| 7 | Credential Access | `curl` with `.env`/passwords, `cat ~/.ssh/id_rsa` | — |
| 8 | Resource Exhaustion | Fork bombs, `yes \|` infinite pipes | — |
| 9 | Permissions | `chmod 777` outside safe zone | `chmod 777` inside safe zone |

## Install

```bash
git clone https://github.com/YOUR_USERNAME/claude-sandbox-guard.git
cd claude-sandbox-guard
bash install.sh
```

The installer will:
1. Detect your OS (Git Bash / macOS / Linux / WSL)
2. Ask for your safe zone directory
3. Install to `~/.claude/guard/`
4. Register the hook in `~/.claude/settings.json`
5. Run a smoke test to verify it works

## Uninstall

```bash
bash uninstall.sh
```

Removes the hook from settings.json and deletes `~/.claude/guard/`.

## Dashboard

### Free Edition (included)

```bash
python ~/.claude/guard/dashboard.py
# Opens http://localhost:7777
```

- Real-time stat cards (total commands, blocked, contained, block rate)
- Blocked commands table with reasons and safe alternatives
- Full activity log with auto-refresh
- Guard status indicator

### Pro Edition (via Whop)

Everything in Free, plus:
- **Threat Intelligence** — Every block explained: what it does, why it's dangerous, was it a false positive
- **Expandable Event Cards** — Click any threat to see full context (commands before/after)
- **Risk Analysis** — Risk level and category breakdown charts
- **Verdict System** — Automatic classification (threat, false positive, security test, bad practice)
- **Outcome Tracking** — Did the AI find another way? Did it move on?

Get Pro: [https://whop.com/tiran-ai-tech/](https://whop.com/tiran-ai-tech/)

## Configuration

Edit `~/.claude/guard/config.sh`:

```bash
# Your development directory — destructive ops are ALLOWED here
SAFE_ZONE="/e/"
```

The guard treats your safe zone as contained territory. Since it's backed by git, anything deleted can be restored. Outside the safe zone, destructive operations are blocked.

## Cross-Platform Support

| Platform | Safe Zone Default | System Paths Protected |
|----------|-------------------|----------------------|
| Git Bash (Windows) | `/e/` | `C:\Windows`, `C:\Program Files` |
| macOS | `~/dev/` | `/System`, `/Library` |
| Linux | `~/projects/` | `/usr`, `/etc`, `/var`, `/boot` |
| WSL | `/mnt/e/` | `C:\Windows`, `C:\Program Files` |

## How It Works Technically

1. Claude Code fires a `PreToolUse` hook before every Bash command
2. The hook receives JSON with the tool name and command
3. `sandbox-guard.sh` parses the command and runs it through 9 rule categories
4. **Exit 0** = allow (command runs normally)
5. **Exit 2** = block (command is stopped, AI sees the stderr message with a safe alternative)
6. All activity is logged to `logs/commands.log` and `logs/blocked.log`

## Requirements

- **Claude Code** (the `~/.claude` directory must exist)
- **Bash** (Git Bash on Windows, native on macOS/Linux)
- **Python 3** (for the dashboard only — the guard itself is pure bash)

## Zero Dependencies

The guard is a single bash script. The dashboard uses only Python standard library. No npm, no pip, no Docker.

## License

The guard (`sandbox-guard.sh`) and free dashboard are MIT licensed. See [LICENSE](LICENSE).

The Pro dashboard (`dashboard-pro.py`) is proprietary and delivered exclusively via [Whop](https://whop.com/tiran-ai-tech/).
