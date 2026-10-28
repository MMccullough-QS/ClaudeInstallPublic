# setup.ps1
# Claude Code workspace setup installer
# Run with: pwsh -NoProfile -File setup.ps1
# Requires: PowerShell 7, Node.js, Git, Python 3.10+

param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Off

Write-Host ""
Write-Host "=== Claude Code Workspace Setup ===" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# SECTION 1: Detect and validate prerequisites
# ---------------------------------------------------------------------------
Write-Host "Checking prerequisites..." -ForegroundColor Yellow
Write-Host ""

$prereqErrors   = @()
$prereqWarnings = @()

# Helper: resolve command to full path
function Get-CmdPath([string]$cmd) {
    $c = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($c) { return $c.Source } else { return $null }
}

# --- Python ---
$pythonCmd      = $null
$pythonVersion  = $null
$pythonExe      = $null
$sitePackages   = $null
$pythonPackages = ""

foreach ($cmd in @("py", "python3", "python")) {
    try {
        $v = & $cmd --version 2>&1
        if ("$v" -match "Python (\d+\.\d+\.\d+)") {
            $pythonCmd    = $cmd
            $pythonVersion = $Matches[1]
            break
        }
    } catch {}
}

if ($pythonCmd) {
    $pythonExe    = try { "$(& $pythonCmd -c 'import sys; print(sys.executable)' 2>$null)".Trim() } catch { "" }
    $sitePackages = try { "$(& $pythonCmd -c 'import site; print(site.getsitepackages()[0])' 2>$null)".Trim() } catch { "" }
    try {
        $pkgLines = & $pythonCmd -m pip list --format=columns 2>$null | Select-Object -Skip 2
        $pythonPackages = ($pkgLines | ForEach-Object {
            $parts = $_ -split '\s+', 2
            if ($parts[0]) { "$($parts[0]) $($parts[1])".Trim() }
        }) -join ", "
    } catch {}
    $pyMajorMinor = [version]$pythonVersion
    if ($pyMajorMinor -lt [version]"3.10") {
        $prereqErrors += "Python $pythonVersion is too old. Minimum: 3.10."
    }
    Write-Host "  [OK] Python $pythonVersion" -ForegroundColor Green
    Write-Host "       Command:      $pythonCmd"
    Write-Host "       Executable:   $pythonExe"
    Write-Host "       site-packages: $sitePackages"
} else {
    $prereqErrors += "Python not found. Install: winget install Python.Python.3.13"
    Write-Host "  [!!] Python:       NOT FOUND" -ForegroundColor Red
    Write-Host "       Install:       winget install Python.Python.3.13" -ForegroundColor Red
    Write-Host "       Note: check 'Add to PATH' during install, or use the py launcher"
}
Write-Host ""

# --- Node.js ---
$nodePath    = Get-CmdPath "node"
$nodeVersion = try { "$(& node --version 2>&1)".Trim() } catch { "" }
$npmPath     = Get-CmdPath "npm"

if ($nodeVersion -match "^v(\d+)") {
    $nodeMajor = [int]$Matches[1]
    if ($nodeMajor -lt 18) {
        $prereqErrors += "Node.js $nodeVersion is too old. Minimum: v18."
    }
    Write-Host "  [OK] Node.js $nodeVersion" -ForegroundColor Green
    Write-Host "       node: $nodePath"
    Write-Host "       npm:  $npmPath"
} else {
    $prereqErrors += "Node.js not found. Install: winget install OpenJS.NodeJS.LTS"
    Write-Host "  [!!] Node.js:      NOT FOUND" -ForegroundColor Red
    Write-Host "       Install:       winget install OpenJS.NodeJS.LTS" -ForegroundColor Red
}
Write-Host ""

# --- Git ---
$gitPath    = Get-CmdPath "git"
$gitVersion = try { "$(& git --version 2>&1)".Trim() } catch { "" }

if ($gitPath) {
    Write-Host "  [OK] Git" -ForegroundColor Green
    Write-Host "       $gitPath"
    Write-Host "       $gitVersion"
} else {
    $prereqErrors += "Git not found. Install: winget install Git.Git (includes Git Bash)"
    Write-Host "  [!!] Git:          NOT FOUND" -ForegroundColor Red
    Write-Host "       Install:       winget install Git.Git" -ForegroundColor Red
}
Write-Host ""

# --- PowerShell 7 ---
$pwshPath = Get-CmdPath "pwsh"
if ($pwshPath) {
    $pwshVersion = try { "$(& pwsh --version 2>&1)".Trim() } catch { "" }
    Write-Host "  [OK] PowerShell 7 ($pwshVersion)" -ForegroundColor Green
    Write-Host "       $pwshPath"
} else {
    $prereqWarnings += "PowerShell 7 (pwsh) not found. Hooks will fail. Install: winget install Microsoft.PowerShell"
    Write-Host "  [!!] PowerShell 7: NOT FOUND -- hooks require pwsh" -ForegroundColor Red
    Write-Host "       Install:       winget install Microsoft.PowerShell" -ForegroundColor Red
    $pwshPath = "pwsh"  # placeholder for config generation
}
Write-Host ""

# --- GitHub CLI (optional) ---
$ghPath    = Get-CmdPath "gh"
$ghVersion = try { "$(& gh --version 2>&1 | Select-Object -First 1)".Trim() } catch { "" }

if ($ghPath) {
    $ghAuth = try { "$(& gh auth status 2>&1 | Select-Object -First 1)".Trim() } catch { "unknown" }
    Write-Host "  [OK] GitHub CLI" -ForegroundColor Green
    Write-Host "       $ghPath"
    Write-Host "       $ghVersion"
    Write-Host "       Auth: $ghAuth"
} else {
    $prereqWarnings += "GitHub CLI (gh) not found. Optional but recommended. Install: winget install GitHub.cli"
    Write-Host "  [--] GitHub CLI:   not found (optional)" -ForegroundColor Yellow
    Write-Host "       Install:       winget install GitHub.cli  then: gh auth login" -ForegroundColor Yellow
}
Write-Host ""

# --- Claude Code ---
$claudePath    = Get-CmdPath "claude"
if ($claudePath) {
    $claudeVersion = try { "$(& claude --version 2>&1)".Trim() } catch { "" }
    Write-Host "  [OK] Claude Code" -ForegroundColor Green
    Write-Host "       $claudePath"
    if ($claudeVersion) { Write-Host "       $claudeVersion" }
} else {
    $prereqErrors += "Claude Code not found. Install: npm install -g @anthropic-ai/claude-code"
    Write-Host "  [!!] Claude Code:  NOT FOUND" -ForegroundColor Red
    Write-Host "       Install:       npm install -g @anthropic-ai/claude-code" -ForegroundColor Red
    Write-Host "       Then run:      claude  (to authenticate)" -ForegroundColor Red
}
Write-Host ""

# --- Git Bash note ---
Write-Host "  [i]  Git Bash (MINGW64) is required for Claude Code's Bash tool on Windows." -ForegroundColor Cyan
Write-Host "       Installed with Git for Windows. Confirm: where bash" -ForegroundColor Cyan
$bashPath = Get-CmdPath "bash"
if ($bashPath) {
    Write-Host "       bash: $bashPath" -ForegroundColor Cyan
}
Write-Host ""

# --- Summary ---
if ($prereqErrors.Count -gt 0) {
    Write-Host "--- PREREQUISITE ERRORS (must fix before continuing) ---" -ForegroundColor Red
    foreach ($e in $prereqErrors) { Write-Host "  * $e" -ForegroundColor Red }
    Write-Host ""
    $skipPrereq = Read-Host "Prerequisites missing. Continue anyway? (not recommended) [y/N]"
    if ($skipPrereq -notmatch '^[Yy]') {
        Write-Host "Setup cancelled. Fix prerequisites and re-run." -ForegroundColor Yellow
        exit 1
    }
    Write-Host ""
}
if ($prereqWarnings.Count -gt 0) {
    Write-Host "--- WARNINGS ---" -ForegroundColor Yellow
    foreach ($w in $prereqWarnings) { Write-Host "  * $w" -ForegroundColor Yellow }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# SECTION 2: Prompts
# ---------------------------------------------------------------------------
Write-Host "--- Configuration ---" -ForegroundColor Cyan
Write-Host "(Press Enter to accept defaults)"
Write-Host ""

$defaultWorkspace = "C:\Users\$env:USERNAME\Claude"
$workspaceInput = Read-Host "Workspace directory [$defaultWorkspace]"
$workspace = if ($workspaceInput.Trim()) { $workspaceInput.Trim().TrimEnd('\') } else { $defaultWorkspace }

$githubUser = Read-Host "GitHub username"

Write-Host ""
Write-Host "GitHub Personal Access Token (optional)" -ForegroundColor Yellow
Write-Host "  Enables GitHub MCP server (repo/issue/PR access from Claude)"
Write-Host "  Required scopes: repo, read:org"
Write-Host "  Leave blank to skip -- you can add it later"
$ghPatSecure = Read-Host "GitHub PAT" -AsSecureString
$ghPat = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ghPatSecure)
)

if (-not $pythonCmd) {
    $pcInput = Read-Host "Python command (py / python3 / python)"
    $pythonCmd = if ($pcInput.Trim()) { $pcInput.Trim() } else { "py" }
    $pythonVersion = try { "$(& $pythonCmd --version 2>&1)".Replace("Python ","").Trim() } catch { "unknown" }
}

Write-Host ""
Write-Host "--- Setup Summary ---" -ForegroundColor Cyan
Write-Host "  Workspace:      $workspace"
Write-Host "  GitHub user:    $(if ($githubUser) { $githubUser } else { '(not set)' })"
Write-Host "  GitHub MCP:     $(if ($ghPat) { 'yes (PAT provided)' } else { 'no (skipped)' })"
Write-Host "  Python:         $pythonCmd ($pythonVersion)"
Write-Host ""

$confirm = Read-Host "Continue? [Y/n]"
if ($confirm -match '^[Nn]') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}
Write-Host ""

# ---------------------------------------------------------------------------
# SECTION 3: Create directories
# ---------------------------------------------------------------------------
Write-Host "Creating directories..." -ForegroundColor Yellow

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$scriptDir = $PSScriptRoot

foreach ($dir in @(
    $workspace,
    (Join-Path $workspace "Tasks"),
    (Join-Path $workspace "memory-backup"),
    (Join-Path $workspace "config-backup"),
    $claudeDir
)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  Created: $dir"
    }
}

# ---------------------------------------------------------------------------
# SECTION 4: Install hook scripts (substitute {{WORKSPACE}})
# ---------------------------------------------------------------------------
Write-Host "Installing hook scripts..." -ForegroundColor Yellow

$hooksSource = Join-Path $scriptDir "hooks"

foreach ($hookFile in @(
    "auto-checkpoint.ps1",
    "check-secrets.ps1",
    "check-sensitive-file.ps1",
    "check-claude-md-sync.ps1"
)) {
    $src = Join-Path $hooksSource $hookFile
    $dst = Join-Path $workspace $hookFile
    if (-not (Test-Path $src)) {
        Write-Host "  WARNING: Hook source not found: $src" -ForegroundColor Yellow
        continue
    }
    $content = Get-Content $src -Raw -Encoding UTF8
    $content = $content.Replace("{{WORKSPACE}}", $workspace)
    Set-Content $dst $content -Encoding UTF8 -NoNewline
    Write-Host "  Installed: $hookFile"
}

# ---------------------------------------------------------------------------
# SECTION 5: Write ~/.claude/settings.json
# ---------------------------------------------------------------------------
Write-Host "Writing ~/.claude/settings.json..." -ForegroundColor Yellow

# Build hook command strings (JSON-safe path)
function Get-HookCmd([string]$script) {
    $path = Join-Path $workspace $script
    return "pwsh -NoProfile -File `"$path`""
}

$settings = [ordered]@{
    hooks = [ordered]@{
        PreToolUse  = @(
            @{
                matcher = "Edit|Write"
                hooks   = @(@{ type = "command"; command = (Get-HookCmd "check-sensitive-file.ps1") })
            }
        )
        PostToolUse = @(
            @{
                matcher = "Write|Edit"
                hooks   = @(@{ type = "command"; command = (Get-HookCmd "check-secrets.ps1") })
            },
            @{
                matcher = "Write|Edit"
                hooks   = @(@{ type = "command"; command = (Get-HookCmd "check-claude-md-sync.ps1") })
            }
        )
        Stop        = @(
            @{ hooks = @(@{ type = "command"; command = (Get-HookCmd "auto-checkpoint.ps1") }) }
        )
        PreCompact  = @(
            @{ hooks = @(@{ type = "command"; command = (Get-HookCmd "auto-checkpoint.ps1") }) }
        )
    }
    autoUpdatesChannel = "latest"
    permissions        = [ordered]@{
        deny = @(
            "Bash(rm -rf:*)",
            "Bash(git push --force:*)",
            "Bash(git push -f:*)",
            "Bash(git reset --hard:*)",
            "Bash(git clean -f:*)"
        )
    }
}

$settingsJson = $settings | ConvertTo-Json -Depth 10
Set-Content (Join-Path $claudeDir "settings.json") $settingsJson -Encoding UTF8
Write-Host "  Written: settings.json"

# ---------------------------------------------------------------------------
# SECTION 6: Write ~/.claude/settings.local.json
# ---------------------------------------------------------------------------
Write-Host "Writing ~/.claude/settings.local.json..." -ForegroundColor Yellow

$workspaceGlob  = "$workspace\**"
$claudeDirGlob  = "$claudeDir\**"

$localSettings = [ordered]@{
    permissions = [ordered]@{
        allow = @(
            "Read",
            "Glob",
            "Grep",
            "NotebookEdit",
            "WebSearch",
            "WebFetch",
            "Edit($workspaceGlob)",
            "Edit($claudeDirGlob)",
            "Write($workspaceGlob)",
            "Write($claudeDirGlob)",
            "Bash($($pythonCmd):*)",
            "Bash($($pythonCmd) -m pip:*)",
            "Bash(pwsh:*)",
            "Bash(powershell.exe:*)",
            "Bash(git:*)",
            "Bash(gh:*)",
            "Bash(node:*)",
            "Bash(npm:*)",
            "Bash(npx:*)",
            "Bash(dotnet:*)",
            "Bash(claude:*)",
            "Bash(mkdir:*)",
            "Bash(cp:*)",
            "Bash(mv:*)",
            "Bash(ls:*)",
            "Bash(cat:*)",
            "Bash(head:*)",
            "Bash(tail:*)",
            "Bash(echo:*)",
            "Bash(type:*)",
            "Bash(where:*)",
            "Bash(which:*)",
            "Bash(diff:*)",
            "Bash(wc:*)",
            "Bash(sort:*)",
            "Bash(curl:*)",
            "Bash(findstr:*)"
        )
    }
}

$localJson = $localSettings | ConvertTo-Json -Depth 5
Set-Content (Join-Path $claudeDir "settings.local.json") $localJson -Encoding UTF8
Write-Host "  Written: settings.local.json"

# ---------------------------------------------------------------------------
# SECTION 7: Write ~/.claude/.mcp.json
# ---------------------------------------------------------------------------
Write-Host "Writing ~/.claude/.mcp.json..." -ForegroundColor Yellow

$mcpServers = [ordered]@{
    context7 = @{
        type    = "stdio"
        command = "npx"
        args    = @("-y", "@upstash/context7-mcp@latest")
    }
}

if ($ghPat) {
    $mcpServers["github"] = @{
        type    = "stdio"
        command = "npx"
        args    = @("-y", "@modelcontextprotocol/server-github")
        env     = @{
            GITHUB_PERSONAL_ACCESS_TOKEN = $ghPat
        }
    }
}

$mcpJson = @{ mcpServers = $mcpServers } | ConvertTo-Json -Depth 6
Set-Content (Join-Path $claudeDir ".mcp.json") $mcpJson -Encoding UTF8
Write-Host "  Written: .mcp.json$(if ($ghPat) { ' (with GitHub MCP)' } else { ' (context7 only)' })"

# ---------------------------------------------------------------------------
# SECTION 8: Write ~/.claude/CLAUDE.md from template
# ---------------------------------------------------------------------------
Write-Host "Writing ~/.claude/CLAUDE.md..." -ForegroundColor Yellow

$claudeMdTemplate = Join-Path $scriptDir "templates\global-claude-md.md"
if (Test-Path $claudeMdTemplate) {
    $claudeMdContent = Get-Content $claudeMdTemplate -Raw -Encoding UTF8

    # Detect "Other Tools" for the template
    $otherToolsList = @()
    if ($nodeVersion)  { $otherToolsList += "- **Node.js / npm**: in PATH ($nodeVersion)" }
    if ($pwshPath)     { $otherToolsList += "- **PowerShell 7**: ``$pwshPath``" }
    if ($ghVersion)    { $otherToolsList += "- **GitHub CLI (gh)**: found -- use ``gh`` for GitHub operations" }
    $otherTools = if ($otherToolsList) { $otherToolsList -join "`n" } else { "- (add installed tools here)" }

    $claudeMdContent = $claudeMdContent.Replace("{{WORKSPACE}}", $workspace)
    $claudeMdContent = $claudeMdContent.Replace("{{PYTHON_VERSION}}", $pythonVersion)
    $claudeMdContent = $claudeMdContent.Replace("{{PYTHON_CMD}}", $pythonCmd)
    $claudeMdContent = $claudeMdContent.Replace("{{PYTHON_EXE}}", $pythonExe)
    $claudeMdContent = $claudeMdContent.Replace("{{SITE_PACKAGES}}", $sitePackages)
    $claudeMdContent = $claudeMdContent.Replace("{{PYTHON_PACKAGES}}", $pythonPackages)
    $claudeMdContent = $claudeMdContent.Replace("{{OTHER_TOOLS_LIST}}", $otherTools)
    $claudeMdContent = $claudeMdContent.Replace("{{USERNAME}}", $env:USERNAME)

    Set-Content (Join-Path $claudeDir "CLAUDE.md") $claudeMdContent -Encoding UTF8
    Write-Host "  Written: CLAUDE.md"
} else {
    Write-Host "  WARNING: Template not found at $claudeMdTemplate -- skipping CLAUDE.md" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# SECTION 9: Write workspace scaffold
# ---------------------------------------------------------------------------
Write-Host "Writing workspace scaffold..." -ForegroundColor Yellow

# Workspace CLAUDE.md
$workspaceClaude = Join-Path $workspace "CLAUDE.md"
if (-not (Test-Path $workspaceClaude)) {
    $workspaceClaudeContent = @"
# Claude Projects

## Active Projects

| Directory | Description | Language | Key Dependencies |
|-----------|-------------|----------|-----------------|
| (add your projects here) | | | |

## Task Tracking

| Directory | Description | GitHub Repo |
|-----------|-------------|-------------|
| ``./Tasks/`` | Project task lists (``projects.md``, ``work.md``) | (add repo) |

### Task Management Convention
- When **starting a new project**, ask the user: "Do you want a new task section in ``Tasks/projects.md``, or a separate task file for this project?"
- Keep task files updated after significant sessions -- mark completed items, add new open items.

## SPEC.md Convention

For any project in active development, maintain a ``SPEC.md`` at the project root with:
- **Problem** -- what user pain is being solved
- **Acceptance Criteria** -- checkbox list of what "done" means (testable, not vague)
- **Out of Scope** -- explicit list of what this phase does NOT include
- **Dependencies / Blockers** -- what must be true before work can start
- **Rejected Approaches** -- ideas that were considered and discarded (and why)

When starting work on a project that has a ``SPEC.md``, read it first.

## Independent Review Convention

After completing a significant coding session, start a **fresh Claude session** and paste only the diff or changed files with this prompt:

> "Review these changes for correctness, edge cases, and anything the original session might have missed. Do not assume the changes are correct -- evaluate them independently."

Review checklist:
- [ ] Logic errors or off-by-one cases
- [ ] Unhandled exceptions or missing validation at system boundaries
- [ ] Hardcoded values that should be config
- [ ] Security issues (injection, exposed credentials, path traversal)
- [ ] SPEC.md compliance -- is anything out of scope being implemented?
- [ ] Rejected Approaches -- is a previously-discarded idea being re-introduced?

## Output File Convention

All projects follow an ``output/`` subdirectory pattern:

| Location | Contents |
|----------|----------|
| ``project_root/`` | Scripts, config, templates, CLAUDE.md, README |
| ``project_root/output/`` | All generated files (.xlsx, .docx, .csv, .html, .pdf) |

Scripts that generate files must write to ``./output/<filename>`` -- never to the project root.

## Git Repositories

| Local Directory | GitHub Repo | Org | Branch Strategy |
|----------------|-------------|-----|-----------------|
| ``./`` (root) | (add repo) | (add org) | Branch-per-feature off ``main`` |
"@
    Set-Content $workspaceClaude $workspaceClaudeContent -Encoding UTF8
    Write-Host "  Created: CLAUDE.md"
} else {
    Write-Host "  Skipped: CLAUDE.md (already exists)"
}

# .gitignore
$gitignorePath = Join-Path $workspace ".gitignore"
if (-not (Test-Path $gitignorePath)) {
    $gitignoreContent = @"
# Root workspace repo - only track specific utility files
# Ignore everything by default (project subdirs have their own repos)
*

# Whitelist root utility files
!.gitignore
!CLAUDE.md
!ReinstallClaude.md
!Tasks/
!Tasks/**
!auto-checkpoint.ps1
!check-sensitive-file.ps1
!check-secrets.ps1
!check-claude-md-sync.ps1
!global-CLAUDE.md
!memory-backup/
!memory-backup/**
!config-backup/
!config-backup/**
"@
    Set-Content $gitignorePath $gitignoreContent -Encoding UTF8
    Write-Host "  Created: .gitignore"
} else {
    Write-Host "  Skipped: .gitignore (already exists)"
}

# Tasks/projects.md
$taskFile = Join-Path $workspace "Tasks\projects.md"
if (-not (Test-Path $taskFile)) {
    $taskContent = @"
# Project Tasks

## Open

- [ ] Set up first project directory and SPEC.md
- [ ] Create GitHub repo for workspace and push: ``git remote add origin <url> && git push -u origin main``

## Done

"@
    Set-Content $taskFile $taskContent -Encoding UTF8
    Write-Host "  Created: Tasks/projects.md"
} else {
    Write-Host "  Skipped: Tasks/projects.md (already exists)"
}

# ReinstallClaude.md (placeholder -- user fills in their bootstrap notes)
$reinstallPath = Join-Path $workspace "ReinstallClaude.md"
if (-not (Test-Path $reinstallPath)) {
    $reinstallContent = @"
# ReinstallClaude.md

Bootstrap guide for replicating this Claude Code setup on a new machine.
Generated by setup.ps1 on $(Get-Date -Format "yyyy-MM-dd").

## Prerequisites

1. **Node.js v18+**: winget install OpenJS.NodeJS.LTS
2. **Python 3.10+**: winget install Python.Python.3.13 (check "Add to PATH")
3. **Git**: winget install Git.Git
4. **GitHub CLI**: winget install GitHub.cli -- then: gh auth login
5. **Claude Code**: npm install -g @anthropic-ai/claude-code
6. **PowerShell 7**: winget install Microsoft.PowerShell

## Quick Setup

Clone the installer repo and run setup:

``````powershell
git clone https://github.com/<your-org>/ClaudeInstallPublic.git
cd ClaudeInstallPublic
pwsh -NoProfile -File setup.ps1
``````

## Installed Python Packages

``````
$pythonPackages
``````

Reinstall with:
``````powershell
$pythonCmd -m pip install $(($pythonPackages -split ', ' | ForEach-Object { $_.Split(' ')[0] }) -join ' ')
``````

## Notes

- Workspace: $workspace
- GitHub user: $(if ($githubUser) { $githubUser } else { '(set during install)' })
- Add any machine-specific notes here as you discover them.
"@
    Set-Content $reinstallPath $reinstallContent -Encoding UTF8
    Write-Host "  Created: ReinstallClaude.md"
} else {
    Write-Host "  Skipped: ReinstallClaude.md (already exists)"
}

# ---------------------------------------------------------------------------
# SECTION 10: Optional git init
# ---------------------------------------------------------------------------
Write-Host ""
$doGitInit = Read-Host "Initialize git repo in $workspace? [Y/n]"
if ($doGitInit -notmatch '^[Nn]') {
    Push-Location $workspace
    try {
        if (-not (Test-Path ".git")) {
            git init 2>&1 | Out-Null
            git add .gitignore CLAUDE.md auto-checkpoint.ps1 check-secrets.ps1 check-sensitive-file.ps1 check-claude-md-sync.ps1 2>&1 | Out-Null
            if (Test-Path "Tasks\projects.md")  { git add "Tasks\projects.md" 2>&1 | Out-Null }
            if (Test-Path "ReinstallClaude.md") { git add "ReinstallClaude.md" 2>&1 | Out-Null }
            if ($githubUser) {
                git config user.name $githubUser 2>&1 | Out-Null
            }
            git commit -m "Initial Claude Code workspace setup" 2>&1 | Out-Null
            Write-Host "  Git repo initialized and initial commit created." -ForegroundColor Green
            Write-Host "  Next: create a private GitHub repo and run:" -ForegroundColor Yellow
            Write-Host "    git remote add origin https://github.com/$githubUser/claude-workspace.git"
            Write-Host "    git push -u origin main"
        } else {
            Write-Host "  Git repo already exists -- skipping init."
        }
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# DONE
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open a terminal in: $workspace"
Write-Host "  2. Run ``claude`` and authenticate with your Anthropic account"
Write-Host "  3. Update CLAUDE.md with your active projects"
Write-Host "  4. Create a GitHub repo for the workspace and push"
Write-Host ""
Write-Host "Your hooks are active. Every session end will:"
Write-Host "  - Auto-commit any tracked changes"
Write-Host "  - Back up ~/.claude/CLAUDE.md, memory files, and config files"
Write-Host ""
