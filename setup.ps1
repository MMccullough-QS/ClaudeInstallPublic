# setup.ps1
# Claude Code workspace setup installer
# Run with: pwsh -NoProfile -File setup.ps1

param()
$ErrorActionPreference = "Stop"
Set-StrictMode -Off

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Header([string]$text) {
    $line = "=" * 68
    Write-Host ""
    Write-Host $line              -ForegroundColor Cyan
    Write-Host "  $text"          -ForegroundColor Cyan
    Write-Host $line              -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section([string]$text) {
    Write-Host ""
    Write-Host "--- $text ---"    -ForegroundColor Yellow
    Write-Host ""
}

function Write-StatusLine([string]$tag, [string]$color, [string]$label, [string]$detail) {
    Write-Host ("  [{0}]" -f $tag.PadRight(4)) -ForegroundColor $color -NoNewline
    Write-Host ("  {0}" -f $label.PadRight(18)) -NoNewline
    Write-Host $detail
}

function Get-CmdPath([string]$cmd) {
    $c = Get-Command $cmd -ErrorAction SilentlyContinue
    return if ($c) { $c.Source } else { $null }
}

function Toggle-Features([string]$title, [System.Collections.Specialized.OrderedDictionary]$features) {
    # Returns the same dict with .enabled toggled based on user input
    while ($true) {
        Write-Host ""
        Write-Host $title -ForegroundColor Yellow
        Write-Host ""
        $i = 1
        foreach ($key in $features.Keys) {
            $f = $features[$key]
            $check = if ($f.enabled) { "x" } else { " " }
            $note  = if ($f.note) { "  ($($f.note))" } else { "" }
            Write-Host ("  {0}. [{1}] {2,-28} {3}{4}" -f $i, $check, $key, $f.desc, $note)
            $i++
        }
        Write-Host ""
        $input = (Read-Host "Enter numbers to toggle (e.g. 2 3), or Enter to accept").Trim()
        if (-not $input) { break }
        foreach ($token in ($input -split '\s+')) {
            $idx = [int]$token - 1
            $key = @($features.Keys)[$idx]
            if ($key -and -not $features[$key].locked) {
                $features[$key].enabled = -not $features[$key].enabled
            } elseif ($features[$key].locked) {
                Write-Host "  (item $token is required and cannot be disabled)" -ForegroundColor Yellow
            }
        }
    }
    return $features
}

# ---------------------------------------------------------------------------
# SCREEN 1: Welcome and narrative
# ---------------------------------------------------------------------------
try { Clear-Host } catch {}
Write-Header "Claude Code Workspace Setup"

Write-Host "  This installer configures Claude Code for a consistent, team-ready"
Write-Host "  environment on Windows. It sets up four layers:"
Write-Host ""
Write-Host "  HOOKS        Run automatically on every Claude turn:"
Write-Host "               - Sensitive file guard (blocks writes to .env, .key, etc.)"
Write-Host "               - Secrets scanner (detects API keys in written files)"
Write-Host "               - CLAUDE.md sync reminder (flags when global config changes)"
Write-Host "               - Auto-checkpoint (commits + backs up memory/config on stop)"
Write-Host ""
Write-Host "  CONFIG       Claude Code settings files:"
Write-Host "               - settings.json   (hooks, permissions, update channel)"
Write-Host "               - settings.local.json  (pre-approved Bash commands)"
Write-Host "               - .mcp.json        (MCP servers for live docs + GitHub)"
Write-Host ""
Write-Host "  CONVENTIONS  ~/.claude/CLAUDE.md with team workflow rules:"
Write-Host "               Session gates, WHY comments, CIF prompting, script output"
Write-Host "               standards, versioning, SPEC.md, rejected approaches log"
Write-Host ""
Write-Host "  WORKSPACE    Scaffold in your workspace directory:"
Write-Host "               CLAUDE.md, .gitignore, Tasks/projects.md, ReinstallClaude.md"
Write-Host ""
Write-Host "  OPTIONAL     Model update notifications, scheduled tasks, MCP servers"
Write-Host "               (selected in a later step)"
Write-Host ""
$null = Read-Host "Press Enter to check prerequisites"

# ---------------------------------------------------------------------------
# SCREEN 2: Prerequisites
# ---------------------------------------------------------------------------
Write-Header "Prerequisites"

$prereqErrors   = @()
$prereqWarnings = @()

# --- Python ---
$pythonCmd     = $null
$pythonVersion = $null
$pythonExe     = $null
$sitePackages  = $null
$pythonPkgs    = ""

foreach ($cmd in @("py", "python3", "python")) {
    try {
        $v = & $cmd --version 2>&1
        if ("$v" -match "Python (\d+\.\d+\.\d+)") {
            $pythonCmd = $cmd; $pythonVersion = $Matches[1]; break
        }
    } catch {}
}

if ($pythonCmd) {
    $pythonExe    = try { (& $pythonCmd -c "import sys; print(sys.executable)" 2>$null).Trim() } catch { "" }
    $sitePackages = try { (& $pythonCmd -c "import site; print(site.getsitepackages()[0])" 2>$null).Trim() } catch { "" }
    try {
        $pkgLines = & $pythonCmd -m pip list --format=columns 2>$null | Select-Object -Skip 2
        $pythonPkgs = ($pkgLines | ForEach-Object {
            $p = $_ -split '\s+',2; if ($p[0]) { "$($p[0]) $($p[1])".Trim() }
        }) -join ", "
    } catch {}
    $pyVer = [version]$pythonVersion
    if ($pyVer -lt [version]"3.10") {
        $prereqErrors += "Python $pythonVersion is below minimum 3.10"
        Write-StatusLine "FAIL" "Red" "Python $pythonVersion" "Too old -- minimum 3.10"
    } else {
        Write-StatusLine "OK  " "Green" "Python $pythonVersion" "cmd: $pythonCmd  |  $pythonExe"
        Write-Host ("  {0}  {1}" -f "".PadRight(6), "site-packages: $sitePackages")
    }
} else {
    $prereqErrors += "Python not found"
    Write-StatusLine "FAIL" "Red" "Python" "NOT FOUND"
    Write-Host "         Install: winget install Python.Python.3.13" -ForegroundColor Red
    Write-Host "         Check 'Add to PATH' during install, or use the py launcher" -ForegroundColor Red
}

# --- Node.js ---
$nodePath    = Get-CmdPath "node"
$nodeVersion = try { (& node --version 2>&1).Trim() } catch { "" }
$npmPath     = Get-CmdPath "npm"

if ($nodeVersion -match "^v(\d+)") {
    $nodeMajor = [int]$Matches[1]
    if ($nodeMajor -lt 18) {
        $prereqErrors += "Node.js $nodeVersion below minimum v18"
        Write-StatusLine "FAIL" "Red" "Node.js $nodeVersion" "Too old -- minimum v18"
    } else {
        Write-StatusLine "OK  " "Green" "Node.js $nodeVersion" "$nodePath"
        Write-Host ("  {0}  npm: {1}" -f "".PadRight(6), $npmPath)
    }
} else {
    $prereqErrors += "Node.js not found -- required for Claude Code"
    Write-StatusLine "FAIL" "Red" "Node.js" "NOT FOUND"
    Write-Host "         Install: winget install OpenJS.NodeJS.LTS" -ForegroundColor Red
}

# --- Git ---
$gitPath    = Get-CmdPath "git"
$gitVersion = try { (& git --version 2>&1).Trim() } catch { "" }
$bashPath   = Get-CmdPath "bash"

if ($gitPath) {
    Write-StatusLine "OK  " "Green" "Git" "$gitPath  ($gitVersion)"
    if ($bashPath) {
        Write-Host ("  {0}  Git Bash: {1}" -f "".PadRight(6), $bashPath)
    } else {
        $prereqWarnings += "Git Bash (bash.exe) not on PATH -- Claude Code Bash tool may not work"
        Write-Host "         Git Bash: NOT FOUND -- add Git Bash to PATH" -ForegroundColor Yellow
    }
} else {
    $prereqErrors += "Git not found -- required"
    Write-StatusLine "FAIL" "Red" "Git" "NOT FOUND"
    Write-Host "         Install: winget install Git.Git  (includes Git Bash)" -ForegroundColor Red
}

# --- PowerShell 7 ---
$pwshPath = Get-CmdPath "pwsh"
if ($pwshPath) {
    $pwshVer = try { (& pwsh --version 2>&1).Trim() } catch { "" }
    Write-StatusLine "OK  " "Green" "PowerShell 7" "$pwshPath  ($pwshVer)"
} else {
    $prereqErrors += "PowerShell 7 (pwsh) not found -- hooks require pwsh"
    Write-StatusLine "FAIL" "Red" "PowerShell 7" "NOT FOUND -- hooks will not work"
    Write-Host "         Install: winget install Microsoft.PowerShell" -ForegroundColor Red
    $pwshPath = "pwsh"
}

# --- Claude Code ---
$claudePath = Get-CmdPath "claude"
if ($claudePath) {
    $claudeVer = try { (& claude --version 2>&1).Trim() } catch { "" }
    Write-StatusLine "OK  " "Green" "Claude Code" "$claudePath  ($claudeVer)"
} else {
    $prereqErrors += "Claude Code not found"
    Write-StatusLine "FAIL" "Red" "Claude Code" "NOT FOUND"
    Write-Host "         Install: npm install -g @anthropic-ai/claude-code" -ForegroundColor Red
    Write-Host "         Then:    claude  (authenticate with your Anthropic account)" -ForegroundColor Red
}

# --- GitHub CLI (optional) ---
$ghPath = Get-CmdPath "gh"
if ($ghPath) {
    $ghVer  = try { (& gh --version 2>&1 | Select-Object -First 1).Trim() } catch { "" }
    $ghAuth = try { (& gh auth status 2>&1 | Select-Object -First 1).Trim() } catch { "unknown" }
    Write-StatusLine "OK  " "Green" "GitHub CLI" "$ghPath"
    Write-Host ("  {0}  {1}  |  auth: {2}" -f "".PadRight(6), $ghVer, $ghAuth)
} else {
    $prereqWarnings += "GitHub CLI (gh) not found -- optional but enables GitHub MCP and repo operations"
    Write-StatusLine "WARN" "Yellow" "GitHub CLI" "not found (optional)"
    Write-Host "         Install: winget install GitHub.cli  then: gh auth login" -ForegroundColor Yellow
}

# --- Python packages quick check ---
if ($pythonCmd) {
    $missingPkgs = @()
    foreach ($pkg in @("openpyxl", "python-docx", "PyMuPDF")) {
        $found = try { & $pythonCmd -c "import $($pkg.Replace('-','_').Replace('PyMuPDF','fitz'))" 2>$null; $true } catch { $false }
        if (-not $found) { $missingPkgs += $pkg }
    }
    if ($missingPkgs.Count -gt 0) {
        Write-StatusLine "WARN" "Yellow" "Python packages" "Some common packages not installed"
        Write-Host ("  {0}  Not found: {1}" -f "".PadRight(6), ($missingPkgs -join ", ")) -ForegroundColor Yellow
        Write-Host ("  {0}  Install after setup: {1} -m pip install {2}" -f "".PadRight(6), $pythonCmd, ($missingPkgs -join " ")) -ForegroundColor Yellow
    } else {
        Write-StatusLine "OK  " "Green" "Python packages" "Core packages verified"
    }
}

# --- Summary ---
Write-Host ""
if ($prereqErrors.Count -gt 0) {
    Write-Host "  ERRORS -- the following must be resolved before setup can complete:" -ForegroundColor Red
    foreach ($e in $prereqErrors) { Write-Host "    * $e" -ForegroundColor Red }
    Write-Host ""
    $skip = Read-Host "  Some prerequisites are missing. Continue anyway? [y/N]"
    if ($skip -notmatch '^[Yy]') {
        Write-Host ""
        Write-Host "  Setup cancelled. Install missing prerequisites and re-run." -ForegroundColor Yellow
        exit 1
    }
}
if ($prereqWarnings.Count -gt 0) {
    Write-Host "  WARNINGS (non-blocking):" -ForegroundColor Yellow
    foreach ($w in $prereqWarnings) { Write-Host "    * $w" -ForegroundColor Yellow }
}

Write-Host ""
$null = Read-Host "Prerequisites checked. Press Enter to configure workspace"

# ---------------------------------------------------------------------------
# SCREEN 3: Configuration
# ---------------------------------------------------------------------------
Write-Header "Configuration"

Write-Host "  Answer the prompts below. Press Enter to accept the default shown in [brackets]."
Write-Host ""

# Workspace
$defaultWs = "C:\Users\$env:USERNAME\Claude"
$wsInput   = Read-Host "  Workspace directory [$defaultWs]"
$workspace = if ($wsInput.Trim()) { $wsInput.Trim().TrimEnd('\') } else { $defaultWs }

# GitHub username
$githubUser = (Read-Host "  GitHub username").Trim()

# GitHub PAT
Write-Host ""
Write-Host "  GitHub Personal Access Token" -ForegroundColor Yellow
Write-Host "    Enables GitHub MCP server (Claude can read repos, issues, PRs)"
Write-Host "    Required scopes: repo, read:org"
Write-Host "    Leave blank to skip -- you can add it to ~/.claude/.mcp.json later"
$ghPatSecure = Read-Host "  GitHub PAT" -AsSecureString
$ghPat = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ghPatSecure))

# Python command override
if (-not $pythonCmd) {
    $pc = (Read-Host "  Python command (py / python3 / python)").Trim()
    $pythonCmd = if ($pc) { $pc } else { "py" }
    $pythonVersion = try { (& $pythonCmd --version 2>&1).Replace("Python ","").Trim() } catch { "unknown" }
}

Write-Host ""
$null = Read-Host "Configuration saved. Press Enter to select features"

# ---------------------------------------------------------------------------
# SCREEN 4a: Feature selection -- optional components
# ---------------------------------------------------------------------------
Write-Header "Feature Selection"

Write-Host "  The items below are OPTIONAL. Core hooks and config are always installed."
Write-Host "  Items marked [x] are ON by default. Toggle by entering their numbers."
Write-Host ""
Write-Host "  Core (always installed, not toggleable):"
Write-Host "    -  Auto-checkpoint hook    Commit + backup on every session stop"
Write-Host "    -  Secrets scan hook       Detect credentials in written files"
Write-Host "    -  Sensitive file guard    Block writes to .env, .key, .secret"
Write-Host "    -  CLAUDE.md sync hook     Remind when global config is edited"
Write-Host "    -  CLAUDE.md conventions   Workflow rules written to ~/.claude/CLAUDE.md"
Write-Host "    -  Workspace scaffold      CLAUDE.md, .gitignore, Tasks/projects.md"

$features = [ordered]@{
    "context7 MCP"       = @{ enabled = $true;  locked = $false; desc = "Live docs for Python, npm libraries, and more";   note = "" }
    "GitHub MCP"         = @{ enabled = ($ghPat.Length -gt 0); locked = $false; desc = "Claude reads repos, issues, PRs from GitHub";  note = if ($ghPat) { "PAT provided" } else { "skipped -- no PAT" } }
    "Model update check" = @{ enabled = $true;  locked = $false; desc = "check-model-updates.py + scan-model-usage.py";    note = "" }
    "Git init workspace" = @{ enabled = $true;  locked = $false; desc = "git init, initial commit in workspace directory"; note = "" }
}

$features = Toggle-Features "  Optional features:" $features

# ---------------------------------------------------------------------------
# SCREEN 4b: Scheduled tasks
# ---------------------------------------------------------------------------
$tasks = [ordered]@{
    "ClaudeModelCheck" = @{ enabled = $features["Model update check"].enabled; locked = $false
                            desc = "Weekly check for new Claude releases"; note = "Mondays 9 AM" }
}

if ($features["Model update check"].enabled) {
    $tasks = Toggle-Features "  Scheduled tasks:" $tasks
} else {
    Write-Host "  (No scheduled tasks -- model update check is disabled)"
}

# ---------------------------------------------------------------------------
# SCREEN 5: Confirmation summary
# ---------------------------------------------------------------------------
Write-Header "Installation Summary"

Write-Host "  Workspace:       $workspace"
Write-Host "  GitHub user:     $(if ($githubUser) { $githubUser } else { '(not set)' })"
Write-Host "  GitHub MCP:      $(if ($ghPat) { 'yes (PAT provided)' } else { 'no' })"
Write-Host "  Python:          $pythonCmd ($pythonVersion)"
Write-Host ""
Write-Host "  Features:"
foreach ($key in $features.Keys) {
    $f     = $features[$key]
    $state = if ($f.enabled) { "[ON] " } else { "[OFF]" }
    $col   = if ($f.enabled) { "Green" } else { "DarkGray" }
    Write-Host ("    {0}  {1}" -f $state, $key) -ForegroundColor $col
}
Write-Host ""
Write-Host "  Scheduled tasks:"
if ($features["Model update check"].enabled -and $tasks["ClaudeModelCheck"].enabled) {
    Write-Host "    [ON]   ClaudeModelCheck (Mondays 9 AM)" -ForegroundColor Green
} else {
    Write-Host "    [OFF]  ClaudeModelCheck" -ForegroundColor DarkGray
}
Write-Host ""

$confirm = Read-Host "Install with these settings? [Y/n]"
if ($confirm -match '^[Nn]') {
    Write-Host "Cancelled." -ForegroundColor Yellow; exit 0
}

# ---------------------------------------------------------------------------
# SCREEN 6: Installation
# ---------------------------------------------------------------------------
Write-Header "Installing"

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$scriptDir = $PSScriptRoot

# Directories
Write-Host "  Creating directories..."
foreach ($dir in @(
    $workspace,
    (Join-Path $workspace "Tasks"),
    (Join-Path $workspace "memory-backup"),
    (Join-Path $workspace "config-backup"),
    $claudeDir
)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "    Created: $dir"
    }
}

# Hook scripts (substitute {{WORKSPACE}})
Write-Host "  Installing hook scripts..."
$hooksSource = Join-Path $scriptDir "hooks"
foreach ($hookFile in @(
    "auto-checkpoint.ps1", "check-secrets.ps1",
    "check-sensitive-file.ps1", "check-claude-md-sync.ps1"
)) {
    $src = Join-Path $hooksSource $hookFile
    $dst = Join-Path $workspace $hookFile
    if (-not (Test-Path $src)) {
        Write-Host "    WARNING: Hook not found: $src" -ForegroundColor Yellow; continue
    }
    $content = (Get-Content $src -Raw -Encoding UTF8).Replace("{{WORKSPACE}}", $workspace)
    Set-Content $dst $content -Encoding UTF8 -NoNewline
    Write-Host "    $hookFile"
}

# Optional scripts
if ($features["Model update check"].enabled) {
    Write-Host "  Installing model update scripts..."
    foreach ($pyFile in @("check-model-updates.py", "scan-model-usage.py", "setup-model-check-task.ps1")) {
        $src = Join-Path $scriptDir $pyFile
        $dst = Join-Path $workspace $pyFile
        if (Test-Path $src) {
            Copy-Item $src $dst -Force
            Write-Host "    $pyFile"
        }
    }
}

# settings.json
Write-Host "  Writing ~/.claude/settings.json..."
function Get-HookCmd([string]$script) { "pwsh -NoProfile -File `"$(Join-Path $workspace $script)`"" }

$settings = [ordered]@{
    hooks = [ordered]@{
        PreToolUse  = @(@{ matcher="Edit|Write"; hooks=@(@{ type="command"; command=(Get-HookCmd "check-sensitive-file.ps1") }) })
        PostToolUse = @(
            @{ matcher="Write|Edit"; hooks=@(@{ type="command"; command=(Get-HookCmd "check-secrets.ps1") }) },
            @{ matcher="Write|Edit"; hooks=@(@{ type="command"; command=(Get-HookCmd "check-claude-md-sync.ps1") }) }
        )
        Stop       = @(@{ hooks=@(@{ type="command"; command=(Get-HookCmd "auto-checkpoint.ps1") }) })
        PreCompact = @(@{ hooks=@(@{ type="command"; command=(Get-HookCmd "auto-checkpoint.ps1") }) })
    }
    autoUpdatesChannel = "latest"
    permissions = [ordered]@{
        deny = @(
            "Bash(rm -rf:*)", "Bash(git push --force:*)", "Bash(git push -f:*)",
            "Bash(git reset --hard:*)", "Bash(git clean -f:*)"
        )
    }
}
$settings | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $claudeDir "settings.json") -Encoding UTF8
Write-Host "    settings.json"

# settings.local.json
Write-Host "  Writing ~/.claude/settings.local.json..."
$localSettings = [ordered]@{
    permissions = [ordered]@{
        allow = @(
            "Read", "Glob", "Grep", "NotebookEdit", "WebSearch", "WebFetch",
            "Edit($workspace\**)", "Edit($claudeDir\**)",
            "Write($workspace\**)", "Write($claudeDir\**)",
            "Bash($($pythonCmd):*)", "Bash($($pythonCmd) -m pip:*)",
            "Bash(pwsh:*)", "Bash(powershell.exe:*)",
            "Bash(git:*)", "Bash(gh:*)",
            "Bash(node:*)", "Bash(npm:*)", "Bash(npx:*)",
            "Bash(dotnet:*)", "Bash(claude:*)",
            "Bash(mkdir:*)", "Bash(cp:*)", "Bash(mv:*)", "Bash(ls:*)",
            "Bash(cat:*)", "Bash(head:*)", "Bash(tail:*)", "Bash(echo:*)",
            "Bash(type:*)", "Bash(where:*)", "Bash(which:*)", "Bash(diff:*)",
            "Bash(wc:*)", "Bash(sort:*)", "Bash(curl:*)", "Bash(findstr:*)"
        )
    }
}
$localSettings | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $claudeDir "settings.local.json") -Encoding UTF8
Write-Host "    settings.local.json"

# .mcp.json
Write-Host "  Writing ~/.claude/.mcp.json..."
$mcpServers = [ordered]@{}
if ($features["context7 MCP"].enabled) {
    $mcpServers["context7"] = @{ type="stdio"; command="npx"; args=@("-y","@upstash/context7-mcp@latest") }
}
if ($features["GitHub MCP"].enabled -and $ghPat) {
    $mcpServers["github"] = @{
        type="stdio"; command="npx"; args=@("-y","@modelcontextprotocol/server-github")
        env=@{ GITHUB_PERSONAL_ACCESS_TOKEN=$ghPat }
    }
}
@{ mcpServers=$mcpServers } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $claudeDir ".mcp.json") -Encoding UTF8
Write-Host "    .mcp.json ($(($mcpServers.Keys) -join ', '))"

# CLAUDE.md from template
Write-Host "  Writing ~/.claude/CLAUDE.md..."
$tmplPath = Join-Path $scriptDir "templates\global-claude-md.md"
if (Test-Path $tmplPath) {
    $otherTools = @()
    if ($nodeVersion)   { $otherTools += "- **Node.js / npm**: in PATH ($nodeVersion)" }
    if ($pwshPath)      { $otherTools += "- **PowerShell 7**: ``$pwshPath``" }
    if ($ghPath)        { $otherTools += "- **GitHub CLI (gh)**: found" }
    $otherToolsStr = if ($otherTools) { $otherTools -join "`n" } else { "- (add installed tools here)" }

    (Get-Content $tmplPath -Raw -Encoding UTF8) `
        -replace '\{\{WORKSPACE\}\}',       $workspace `
        -replace '\{\{PYTHON_VERSION\}\}',  $pythonVersion `
        -replace '\{\{PYTHON_CMD\}\}',      $pythonCmd `
        -replace '\{\{PYTHON_EXE\}\}',      $pythonExe `
        -replace '\{\{SITE_PACKAGES\}\}',   $sitePackages `
        -replace '\{\{PYTHON_PACKAGES\}\}', $pythonPkgs `
        -replace '\{\{OTHER_TOOLS_LIST\}\}',$otherToolsStr `
        -replace '\{\{USERNAME\}\}',        $env:USERNAME |
    Set-Content (Join-Path $claudeDir "CLAUDE.md") -Encoding UTF8
    Write-Host "    CLAUDE.md"
} else {
    Write-Host "    WARNING: Template not found -- skipping CLAUDE.md" -ForegroundColor Yellow
}

# Workspace scaffold
Write-Host "  Writing workspace scaffold..."

$scaffoldClaude = Join-Path $workspace "CLAUDE.md"
if (-not (Test-Path $scaffoldClaude)) {
    @"
# Claude Projects

## Active Projects

| Directory | Description | Language | Key Dependencies |
|-----------|-------------|----------|-----------------|
| (add your projects here) | | | |

## Task Tracking

| Directory | Description | GitHub Repo |
|-----------|-------------|-------------|
| ``./Tasks/`` | Task lists | (add repo) |

## SPEC.md Convention

Maintain a ``SPEC.md`` at the root of any project in active development with:
- **Problem**, **Acceptance Criteria**, **Out of Scope**, **Dependencies**, **Rejected Approaches**

## Git Repositories

| Local Directory | GitHub Repo | Org |
|----------------|-------------|-----|
| ``./`` (root) | (add repo) | (your org) |
"@ | Set-Content $scaffoldClaude -Encoding UTF8
    Write-Host "    CLAUDE.md"
}

$gitignorePath = Join-Path $workspace ".gitignore"
if (-not (Test-Path $gitignorePath)) {
    @"
# Root workspace -- track only utility files (project subdirs have their own repos)
*
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
"@ | Set-Content $gitignorePath -Encoding UTF8
    Write-Host "    .gitignore"

    if ($features["Model update check"].enabled) {
        Add-Content $gitignorePath "`n!check-model-updates.py`n!scan-model-usage.py`n!setup-model-check-task.ps1"
        Write-Host "    .gitignore (+ model scripts)"
    }
}

$taskFile = Join-Path $workspace "Tasks\projects.md"
if (-not (Test-Path $taskFile)) {
    @"
# Project Tasks

## Open

- [ ] Set up first project and SPEC.md
- [ ] Create GitHub repo for workspace and push

## Done
"@ | Set-Content $taskFile -Encoding UTF8
    Write-Host "    Tasks/projects.md"
}

$reinstallPath = Join-Path $workspace "ReinstallClaude.md"
if (-not (Test-Path $reinstallPath)) {
    $pkgList = ($pythonPkgs -split ', ' | ForEach-Object { $_.Split(' ')[0] }) -join ' '
    @"
# ReinstallClaude.md

Bootstrap guide for replicating this Claude Code setup on a new machine.
Generated: $(Get-Date -Format "yyyy-MM-dd")

## Prerequisites

1. Node.js v18+:      winget install OpenJS.NodeJS.LTS
2. Python 3.10+:      winget install Python.Python.3.13  (check "Add to PATH")
3. Git + Git Bash:    winget install Git.Git
4. GitHub CLI:        winget install GitHub.cli  then: gh auth login
5. Claude Code:       npm install -g @anthropic-ai/claude-code
6. PowerShell 7:      winget install Microsoft.PowerShell

## Quick Setup

    git clone https://github.com/<your-org>/ClaudeInstallPublic.git
    cd ClaudeInstallPublic
    pwsh -NoProfile -File setup.ps1

## Python Packages

    $pythonCmd -m pip install $pkgList

## Notes

- Workspace: $workspace
- GitHub user: $(if ($githubUser) { $githubUser } else { '(set during install)' })
- Add machine-specific notes here as you discover them.
"@ | Set-Content $reinstallPath -Encoding UTF8
    Write-Host "    ReinstallClaude.md"
}

# Git init
if ($features["Git init workspace"].enabled) {
    Write-Host "  Initializing git repo..."
    Push-Location $workspace
    try {
        if (-not (Test-Path ".git")) {
            git init 2>&1 | Out-Null
            $toAdd = @(".gitignore", "CLAUDE.md", "auto-checkpoint.ps1",
                       "check-secrets.ps1", "check-sensitive-file.ps1", "check-claude-md-sync.ps1")
            if (Test-Path "Tasks\projects.md")  { $toAdd += "Tasks\projects.md" }
            if (Test-Path "ReinstallClaude.md") { $toAdd += "ReinstallClaude.md" }
            if ($features["Model update check"].enabled) {
                $toAdd += @("check-model-updates.py","scan-model-usage.py","setup-model-check-task.ps1")
            }
            $toAdd | Where-Object { Test-Path $_ } | ForEach-Object { git add $_ 2>&1 | Out-Null }
            if ($githubUser) { git config user.name $githubUser 2>&1 | Out-Null }
            git commit -m "Initial Claude Code workspace setup" 2>&1 | Out-Null
            Write-Host "    git init + initial commit done"
        } else {
            Write-Host "    (git repo already exists -- skipped)"
        }
    } finally { Pop-Location }
}

# Scheduled tasks
if ($features["Model update check"].enabled -and $tasks["ClaudeModelCheck"].enabled) {
    Write-Host "  Registering scheduled task: ClaudeModelCheck..."
    $taskScript = Join-Path $workspace "setup-model-check-task.ps1"
    if (Test-Path $taskScript) {
        # Register silently (no interactive prompt since we already confirmed)
        $pyCmd     = $pythonCmd
        $pyScript  = Join-Path $workspace "check-model-updates.py"
        $logFile   = Join-Path $workspace "check-model-updates.log"
        # WHY: cmd.exe /c required -- Task Scheduler passes args directly to exe;
        # shell redirect operators (>>) need a shell interpreter
        $action    = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $pyCmd `"$pyScript`" >> `"$logFile`" 2>&1"
        $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "9:00AM"
        $stSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable -RunOnlyIfNetworkAvailable
        Unregister-ScheduledTask -TaskName "ClaudeModelCheck" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "ClaudeModelCheck" -Action $action -Trigger $trigger -Settings $stSettings -RunLevel Limited -Description "Weekly Claude model update check" | Out-Null
        Write-Host "    ClaudeModelCheck registered (Mondays 9 AM)"
        Write-Host "  Seeding model check state..."
        & $pythonCmd $pyScript 2>&1 | Out-Null
        Write-Host "    State file seeded"
    } else {
        Write-Host "    WARNING: setup-model-check-task.ps1 not found -- task not registered" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# SCREEN 7: Done
# ---------------------------------------------------------------------------
Write-Header "Setup Complete"

Write-Host "  Everything is installed. Next steps:"
Write-Host ""
Write-Host "  1. Open a terminal in: $workspace"
Write-Host "  2. Run 'claude' and authenticate with your Anthropic account"
Write-Host "  3. Update CLAUDE.md in $workspace with your active projects"
if ($features["Git init workspace"].enabled) {
    Write-Host "  4. Create a private GitHub repo for the workspace and push:"
    Write-Host "       git remote add origin https://github.com/$githubUser/claude-workspace.git"
    Write-Host "       git push -u origin main"
}
if ($features["Model update check"].enabled -and $tasks["ClaudeModelCheck"].enabled) {
    Write-Host ""
    Write-Host "  Model update checker is active (Mondays 9 AM)."
    Write-Host "  Claude will alert you at session start if new models are detected."
}
Write-Host ""
Write-Host "  To update this setup when new conventions are published:"
Write-Host "    git pull  (in the ClaudeInstallPublic directory)"
Write-Host "    pwsh -NoProfile -File setup.ps1"
Write-Host ""
Write-Host "  Your hooks are live. Every session stop will:"
Write-Host "    - Auto-commit any tracked changes"
Write-Host "    - Back up ~/.claude/CLAUDE.md, memory files, and config files"
Write-Host ""
