# Global Claude Code Instructions

These instructions apply to ALL projects and sessions on this machine.

## Shell Environment (Windows 11 + Git Bash)

The Bash tool runs in **Git Bash (MINGW64)**, not cmd.exe or native PowerShell.

### PowerShell: ALWAYS use the heredoc pattern

Bash strips `$` signs from inline PowerShell commands before they reach PowerShell. Never use `powershell.exe -Command "$var = ..."` -- it will always fail.

**Correct pattern:**
```bash
pwsh -NoProfile -File - <<'PS1'
$result = Get-ChildItem "C:\Some\Path"
Write-Output $result.Name
PS1
```

Single-quoted `<<'PS1'` prevents bash from interpolating `$` variables.

### PowerShell 5.1 encoding trap
PowerShell 5.1 reads BOM-less files using Windows-1252. UTF-8 em-dash (bytes `E2 80 94`) decodes where byte `0x94` = smart quote, which PS treats as a string delimiter. **Never use non-ASCII characters in .ps1 files** -- use `--` instead of em-dash, `=`/`-` instead of box-drawing chars.

### General shell notes
- Use `pwsh` (PowerShell 7) as the default. Fall back to `powershell.exe` (5.1) only if a module requires .NET Framework / Desktop edition.
- Windows backslash paths work inside heredoc PS1 blocks
- For simple directory listings or file checks, prefer Claude Code's built-in tools (Glob, Read, Grep) over shell commands

## Installed Tools -- DO NOT reinstall

### Python
- **Version**: Python {{PYTHON_VERSION}}
- **Launcher**: `{{PYTHON_CMD}}` (at `{{PYTHON_EXE}}`)
- **pip**: `{{PYTHON_CMD}} -m pip` -- if missing, restore with: `{{PYTHON_CMD}} -m ensurepip --upgrade`
- **IMPORTANT**: `python`, `python3`, and `pip` may NOT be on the Git Bash PATH. Always use `{{PYTHON_CMD}}` or invoke via PowerShell heredoc.
- **site-packages**: `{{SITE_PACKAGES}}`

**Installed packages**: {{PYTHON_PACKAGES}}
**NOT installed by default**: PyPDF2, pdfplumber, pandas, requests -- verify before using.

### Other Tools on System
{{OTHER_TOOLS_LIST}}

## Global Permissions

### File Access
- **Read/Write**: Full access to `{{WORKSPACE}}\` and **all subdirectories** -- create, read, edit, and delete files across any project folder under this path.

### Web Search
- When the user asks for research, investigation, or information gathering **without specifying a source**, use web search proactively. No need to ask for permission first.

### Pre-Approved Commands (in settings.local.json)
- `Read`, `Glob`, `Grep`, `NotebookEdit`, `WebSearch`, `WebFetch` -- always allowed
- `Edit`, `Write` -- scoped to `{{WORKSPACE}}\**`, `C:\Users\{{USERNAME}}\.claude\**`
- `Bash({{PYTHON_CMD}}:*)`, `Bash({{PYTHON_CMD}} -m pip:*)` -- Python via launcher
- `Bash(pwsh:*)`, `Bash(powershell.exe:*)` -- PowerShell 7 (default) / 5.1 (fallback)
- `Bash(git:*)`, `Bash(gh:*)` -- git and GitHub CLI
- `Bash(node:*)`, `Bash(npm:*)`, `Bash(npx:*)`, `Bash(dotnet:*)`, `Bash(claude:*)` -- Node, .NET, Claude headless
- `Bash(mkdir|cp|mv|ls|cat|head|tail|echo|type|where|which|diff|wc|sort|curl|findstr:*)` -- shell utilities

### Hooks (in settings.json)
- **PreToolUse**: Blocks Edit/Write to sensitive files (`.env`, `.credentials`, `.secret`, `.key`)
- **PostToolUse**: Scans written files for exposed credentials; reminds to sync ReinstallClaude.md when CLAUDE.md is edited
- **Stop + PreCompact**: Auto-checkpoint -- commits tracked changes, backs up CLAUDE.md, memory files, and config files to workspace repo

## Git Workflow Conventions

All projects under `{{WORKSPACE}}\` use git with private GitHub repos.

### Automated Workflow (Full Auto)
For routine work (single-feature, single-project changes), handle the **entire git lifecycle silently**:
1. Pull latest `main`
2. Create a feature branch (`feature/`, `fix/`, `update/`, `docs/`, `refactor/`)
3. Make changes and commit
4. Merge to `main`, push, and delete the feature branch
5. Do NOT ask for permission at each step -- just do it and report what was done

**Only pause for explicit user review when:**
- The change touches 5+ files or multiple projects
- The change modifies core logic that could break existing functionality
- You are unsure about the approach or requirements

### Branch-per-Feature
- **`main`** is the stable branch.
- Create feature branches for all non-trivial changes: `git checkout -b <type>/<description>`
- Branch types: `feature/`, `fix/`, `update/`, `docs/`, `refactor/`
- Push branches: `git push -u origin <branch-name>`
- Merge to main after testing, then delete the feature branch.

### Commit Conventions
- Imperative mood in commit messages ("Add feature", not "Added feature")
- Always include `Co-Authored-By: Claude <noreply@anthropic.com>`
- Stage specific files by name -- never use `git add -A` or `git add .`
- NEVER commit files matching: `.env`, `*.mp4`

### GitHub Repos (Private)
Use `gh` CLI for GitHub operations. Add your GitHub username and repo list to the project CLAUDE.md.

## Multi-Agent Tool Pattern -- Headless CLI (Standard)

When building multi-agent AI tools in Python, use **`claude -p` headless CLI via subprocess** -- not the `anthropic` SDK. Uses the existing Claude Code subscription with no separate API key or billing.

```python
result = subprocess.run(
    ['claude', '-p', prompt, '--system-prompt', system_prompt,
     '--model', 'claude-sonnet-4-6', '--no-session-persistence'],
    capture_output=True, text=True, encoding='utf-8',
)
```

Only use the `anthropic` SDK when the task requires direct API access (billing control, beta features, non-Claude Code environments).

## Accuracy and Sources Rule

**Never fabricate information.** If you cannot find a verified answer -- say so. Specifically:

- When answering factual questions, rely on **official documentation, vendor sites, and reputable sources**. Do not invent URLs, API endpoints, command syntax, or configuration values.
- When performing web searches, **prioritize results from official/primary sources** over blog posts, forums, or AI-generated content. If the only results are low-quality or unverifiable, flag that to the user.
- If you are **unsure or cannot verify** something, clearly state: "I'm not confident in this answer" or "I couldn't find a reliable source for this."
- **Never guess** at file paths, database column names, API parameters, or system configurations. Look them up first.
- If a web search returns no useful results, report that honestly rather than falling back to potentially outdated training knowledge without disclosure.

## Proactive Error Notification Rule

When Claude encounters an error, misconfiguration, or broken pattern that negatively impacts workflow efficiency (e.g., a hook silently failing, a tool not working as expected, a recurring false positive), **immediately notify the user** and offer to fix it -- either right now or at the start of the next task. Do not silently work around it.

Format: briefly describe the problem, its impact, and ask: "Fix now or flag for next session?"

## Self-Improvement Rule

When a Bash command succeeds after prior failures in a session, record the working pattern in the relevant project's `CLAUDE.md` or in this global file (if the pattern is universal) to prevent future reattempts.

## Config Sync Rule -- ReinstallClaude.md

The file `{{WORKSPACE}}\ReinstallClaude.md` is a portable bootstrap guide for replicating this Claude Code setup on other machines. **Whenever any of the following are changed, you MUST also update ReinstallClaude.md to reflect the change:**

- `~/.claude/CLAUDE.md` (this file) -- tool versions, packages, shell notes, permissions
- `~/.claude/settings.json` -- update channel or other global settings
- `~/.claude/settings.local.json` -- permission allow-list entries
- Python packages installed or removed -- update the package list
- New system tools installed or removed -- update the tools section

## Session Conventions

### Starting a Session in a New Project Directory
**Hard requirement -- three steps before any code or file work:**
1. Check if a `project_<name>.md` memory file exists in `~/.claude/projects/<workspace>/memory/`
2. If not, **create one immediately** -- populate with purpose, tech stack, key files, GitHub repo, current status
3. Ask the user: "Do you want a task section in `Tasks/projects.md` or a separate task file for this project?"

Do not start work until all three steps are complete.

### Starting a Session in a Previously-Used Directory
- Read the relevant project memory file(s) before doing any work.
- Check for a `## Last Session` section -- this is the handoff note from the prior session.

### During a Long Session
- For multi-step tasks, write a `PROGRESS.md` in the project directory at natural milestones (what's done, what's next, active branch/file).
- Commit tracked changes more frequently -- after each logical unit of work, not just at the end of a session.

### Ending Any Session
Write or update a `## Last Session` block in the relevant project memory file with:
- What was completed
- What's next / open items
- Key decisions made and why (not just bare facts -- include reasoning)
- Active branch name if on a feature branch

#### Decisions
Capture non-obvious choices made during the session:
- What options were considered
- Why this approach was chosen over alternatives
- Any constraints that shaped the decision

Delete or merge `PROGRESS.md` into the memory file if it was created.

## Code Comments Rule

Follow a **WHY-first** commenting strategy -- comments explain intent and reasoning, not mechanics.

- Use `# WHY:` prefix for non-obvious choices: `# WHY: batch size 50 -- API rate limit 100 req/min with safety margin`
- Never paraphrase code: `# increment counter` above `i += 1` adds no value
- Document the "rejected alternative" when a natural approach was deliberately avoided
- Comments survive refactoring -- they should remain accurate if the logic changes

## Script Output Convention

Every script that performs multi-step work must end with a structured summary block for token-efficient Claude review:

**Python:**
```python
print("\n--- CLAUDE SUMMARY ---")
print(f"Status:    {'OK' if errors == 0 else 'ERRORS'}")
print(f"Processed: {processed} items")
print(f"Errors:    {errors}")
print(f"Output:    {output_path}")
if errors:
    for e in error_list[:5]:
        print(f"  ERR: {e}")
print("--- END SUMMARY ---")
```

**PowerShell:**
```powershell
Write-Host ""
Write-Host "--- CLAUDE SUMMARY ---"
Write-Host "Status:    $(if ($errors -eq 0) { 'OK' } else { 'ERRORS' })"
Write-Host "Processed: $processed"
Write-Host "Errors:    $errors"
Write-Host "Output:    $outputPath"
Write-Host "--- END SUMMARY ---"
```

When pasting terminal output for review, paste only the `--- CLAUDE SUMMARY ---` block unless errors require the full log.

## Script Versioning Rule

**One canonical file per script.** Git history is the version store -- no numbered copies (`_v2`, `_final`, `_backup`).

- Name scripts by function: `generate_report.py`, `import_data.py`
- Use temporary branch names for experimental A/B variants, merge or delete when resolved
- Keep all scripts in a `scripts/` subdirectory at the project root, not scattered in root
- Archive retired scripts to `archive/` with a one-line comment at the top explaining why they were retired
- Reference documents (PDFs, wiring guides) go in `ref/`; generated output goes in `output/`

## Prompt Quality Rule

Before starting any task, evaluate the prompt on four dimensions:
1. **Clarity** -- Is the goal unambiguous?
2. **Specificity** -- Are file paths, function names, or data sources named?
3. **Actionability** -- Is there a clear definition of done?
4. **Scope** -- Is the blast radius bounded?

If a prompt scores low on 2+ dimensions, surface one concrete improvement using the **CIF template**:

> **Context**: [what exists now]
> **Intent**: [what outcome you want]
> **Format**: [how the output should look]

Example coaching response:
> "This prompt is missing a definition of done. Try: 'Update `generate_report.py` so that running it against `test_data.csv` produces an Excel file in `output/` with columns X, Y, Z -- and the `--- CLAUDE SUMMARY ---` block shows 0 errors.'"

Apply this check silently for clear prompts. Surface it only when it would prevent rework.

## Tool Evaluation Rules

Before installing any MCP server, plugin, or extension, evaluate against this checklist:

- [ ] **Purpose**: Does this solve a real, current problem (not hypothetical)?
- [ ] **Trust**: Is the publisher known? Is the repo actively maintained with recent commits?
- [ ] **Permissions**: What data/system access does it require? Is that proportionate?
- [ ] **Alternatives**: Can this be done with existing tools (Bash, WebSearch, Read)?
- [ ] **Reversibility**: Can it be removed cleanly without side effects?

If any item raises concern, default to NOT installing and note the reason.
