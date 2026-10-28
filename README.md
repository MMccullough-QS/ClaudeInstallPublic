# Claude Code Workspace Setup

A one-command installer that configures Claude Code to a standard, team-consistent environment on Windows.

## What it sets up

- `~/.claude/CLAUDE.md` — global conventions: session workflow, code comments, prompt quality coaching, script output format, versioning, git workflow, tool evaluation rules
- `~/.claude/settings.json` — hooks: sensitive file protection, secrets scanning, CLAUDE.md sync reminder, auto-checkpoint (commit + push on session end)
- `~/.claude/settings.local.json` — scoped permissions for your workspace
- `~/.claude/.mcp.json` — context7 (live library docs) + GitHub MCP (optional)
- Hook scripts in your workspace: auto-checkpoint, secrets scan, sensitive file guard, CLAUDE.md sync reminder
- Workspace scaffold: `CLAUDE.md`, `.gitignore`, `Tasks/projects.md`
- **Automatic backup on every session end:** memory files, global CLAUDE.md, and config files are committed and pushed to your workspace repo

## Prerequisites

Install these before running setup:

1. **Node.js v18+** — [nodejs.org](https://nodejs.org) or `winget install OpenJS.NodeJS.LTS`
2. **Python 3.10+** — [python.org](https://www.python.org/downloads/) (check "Add to PATH" or install the `py` launcher)
3. **Git** — [git-scm.com](https://git-scm.com) (includes Git Bash on Windows)
4. **GitHub CLI** — [cli.github.com](https://cli.github.com) — run `gh auth login` after install
5. **Claude Code** — `npm install -g @anthropic-ai/claude-code`
6. **PowerShell 7** (recommended) — `winget install Microsoft.PowerShell`

## Quick start

```powershell
# Clone this repo
git clone https://github.com/MMccullough-QS/ClaudeInstallPublic.git
cd ClaudeInstallPublic

# Run the installer
pwsh -NoProfile -File setup.ps1
```

Follow the prompts. The installer detects your environment and asks only for values it cannot find automatically.

## What you'll be prompted for

| Prompt | Default | Notes |
|--------|---------|-------|
| Workspace directory | `C:\Users\<you>\Claude` | Where all your Claude projects will live |
| GitHub username | — | Used for git identity |
| GitHub PAT | — | Optional. Enables GitHub MCP server (repo/issue/PR access). Scopes: `repo`, `read:org` |
| Python command | auto-detected | Usually `py` on Windows |

## After setup

1. Open a terminal in your workspace directory
2. Run `claude` and authenticate
3. Update `CLAUDE.md` in your workspace with your active projects
4. Create a GitHub repo for your workspace and push

## Conventions included

Every session Claude will follow:
- **New project gate** — creates memory file, offers SPEC.md and task section before starting work
- **Session handoff** — Last Session block with decisions captured at end of every session
- **Prompt quality coaching** — flags vague prompts (no file path, no definition of done) and suggests the CIF template
- **Script output** — every script prints a `--- CLAUDE SUMMARY ---` block for efficient review
- **Script versioning** — one canonical file per script; git history replaces numbered copies
- **Code comments** — `# WHY:` tags for non-obvious choices; no paraphrasing comments
- **Rejected approaches** — captured in SPEC.md to prevent re-proposing abandoned ideas
- **Tool evaluation** — checklist before installing any MCP server or plugin

## Keeping in sync

When you update `~/.claude/CLAUDE.md`, the auto-checkpoint hook will remind you to update your local `ReinstallClaude.md`. For major changes, re-run `setup.ps1` from this repo to get the latest conventions.
