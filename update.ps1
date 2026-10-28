# update.ps1
# Pulls the latest Claude Code conventions from ClaudeInstallPublic and
# re-applies them to an existing installation.
#
# Run from the ClaudeInstallPublic directory:
#   pwsh -NoProfile -File update.ps1
#
# Safe to run repeatedly. Does NOT overwrite:
#   - Your workspace CLAUDE.md, .gitignore, Tasks/ (you own these)
#   - ~/.claude/.mcp.json (contains your tokens)
#   - ~/.claude/settings.local.json (may contain your customizations)
#
# DOES update:
#   - Hook scripts in your workspace (new logic, bug fixes)
#   - ~/.claude/CLAUDE.md (new conventions from template)
#   - ~/.claude/settings.json (hook paths regenerated)
#   - Optional scripts (check-model-updates.py, scan-model-usage.py)
#   - Scheduled tasks (if previously registered)

param()
$ErrorActionPreference = "Stop"
Set-StrictMode -Off

function Write-Header([string]$text) {
    $line = "=" * 68
    Write-Host ""; Write-Host $line -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan; Write-Host ""
}

function Write-Section([string]$text) {
    Write-Host ""; Write-Host "--- $text ---" -ForegroundColor Yellow; Write-Host ""
}

# ---------------------------------------------------------------------------
# SCREEN 1: Header
# ---------------------------------------------------------------------------
try { Clear-Host } catch {}
Write-Header "Claude Code Workspace Update"

Write-Host "  This script pulls the latest conventions and hook scripts from"
Write-Host "  ClaudeInstallPublic and re-applies them to your existing installation."
Write-Host ""
Write-Host "  Your project files and personal config are NOT touched."
Write-Host ""

$scriptDir = $PSScriptRoot

# ---------------------------------------------------------------------------
# SCREEN 2: Git pull
# ---------------------------------------------------------------------------
Write-Section "Pulling Latest Changes"

Push-Location $scriptDir
try {
    # Show current version info
    $currentCommit  = git rev-parse --short HEAD 2>$null
    $currentDate    = git log -1 --format="%ai" 2>$null
    Write-Host "  Current: $currentCommit  ($currentDate)"

    Write-Host "  Fetching from origin..."
    git fetch origin 2>&1 | Out-Null

    $behind = [int](git rev-list --count "HEAD..origin/main" 2>$null)
    if ($behind -eq 0) {
        Write-Host "  Already up to date." -ForegroundColor Green
        $hasChanges = $false
    } else {
        Write-Host "  $behind new commit(s) available. Pulling..." -ForegroundColor Yellow
        git pull origin main 2>&1 | Out-Null
        $newCommit = git rev-parse --short HEAD 2>$null
        Write-Host "  Updated: $currentCommit --> $newCommit" -ForegroundColor Green
        $hasChanges = $true
    }

    # Show what changed in hook/template files
    if ($hasChanges) {
        Write-Host ""
        Write-Host "  Files changed:"
        git diff "HEAD@{1}" HEAD --name-only 2>$null | ForEach-Object {
            Write-Host "    $_"
        }
    }
} finally {
    Pop-Location
}

Write-Host ""

# ---------------------------------------------------------------------------
# SCREEN 3: Detect existing installation
# ---------------------------------------------------------------------------
Write-Section "Detecting Existing Installation"

$claudeDir    = Join-Path $env:USERPROFILE ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"
$workspace    = $null
$pythonCmd    = $null
$pythonVersion = $null

# Detect workspace from settings.json (Stop hook command contains the path)
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        $stopCmd  = $settings.hooks.Stop[0].hooks[0].command
        if ($stopCmd -match 'File "([^"]+)\\auto-checkpoint\.ps1"') {
            $workspace = $Matches[1]
        }
    } catch {}
}

# Fallback: prompt
if (-not $workspace -or -not (Test-Path $workspace)) {
    Write-Host "  Could not detect workspace from settings.json." -ForegroundColor Yellow
    $default  = "C:\Users\$env:USERNAME\Claude"
    $wsInput  = Read-Host "  Workspace directory [$default]"
    $workspace = if ($wsInput.Trim()) { $wsInput.Trim().TrimEnd('\') } else { $default }
}

Write-Host "  Workspace:   $workspace"
Write-Host "  Config dir:  $claudeDir"

# Confirm
$wsConfirm = Read-Host "  Is this correct? [Y/n]"
if ($wsConfirm -match '^[Nn]') {
    $wsInput   = Read-Host "  Enter correct workspace path"
    $workspace = $wsInput.Trim().TrimEnd('\')
}

# Detect Python
foreach ($cmd in @("py", "python3", "python")) {
    try {
        $v = & $cmd --version 2>&1
        if ("$v" -match "Python (\d+\.\d+\.\d+)") {
            $pythonCmd     = $cmd
            $pythonVersion = $Matches[1]
            break
        }
    } catch {}
}

if (-not $pythonCmd) {
    $pythonCmd     = "py"
    $pythonVersion = "unknown"
}

Write-Host "  Python:      $pythonCmd ($pythonVersion)"
Write-Host ""

# ---------------------------------------------------------------------------
# SCREEN 4: What will be updated
# ---------------------------------------------------------------------------
Write-Section "Update Plan"

Write-Host "  The following will be re-applied from the latest version:"
Write-Host ""
Write-Host "  ALWAYS UPDATED:"
Write-Host "    auto-checkpoint.ps1       (session backup + git checkpoint)"
Write-Host "    check-secrets.ps1         (credential pattern scanner)"
Write-Host "    check-sensitive-file.ps1  (sensitive file guard)"
Write-Host "    check-claude-md-sync.ps1  (CLAUDE.md edit reminder)"
Write-Host "    ~/.claude/CLAUDE.md       (workflow conventions)"
Write-Host "    ~/.claude/settings.json   (hook paths + permissions)"
Write-Host ""
Write-Host "  IF PREVIOUSLY INSTALLED:"
Write-Host "    check-model-updates.py    (model release checker)"
Write-Host "    scan-model-usage.py       (hardcoded model string scanner)"
Write-Host "    ClaudeModelCheck task     (Task Scheduler -- if registered)"
Write-Host ""
Write-Host "  NOT TOUCHED:"
Write-Host "    ~/.claude/.mcp.json            (contains your tokens)"
Write-Host "    ~/.claude/settings.local.json  (your command permissions)"
Write-Host "    Workspace CLAUDE.md, .gitignore, Tasks/  (your project files)"
Write-Host "    Your custom hooks in settings.json  (merged, not replaced)"
Write-Host "    ~/.claude/CLAUDE.md            (you will be asked before this changes)"
Write-Host ""

$confirm = Read-Host "  Apply update? [Y/n]"
if ($confirm -match '^[Nn]') {
    Write-Host "  Update cancelled." -ForegroundColor Yellow; exit 0
}

# ---------------------------------------------------------------------------
# SCREEN 5: Apply updates
# ---------------------------------------------------------------------------
Write-Header "Applying Updates"

# Helper: get Python details for CLAUDE.md template substitution
$pythonExe    = try { (& $pythonCmd -c "import sys; print(sys.executable)" 2>$null).Trim() } catch { "" }
$sitePackages = try { (& $pythonCmd -c "import site; print(site.getsitepackages()[0])" 2>$null).Trim() } catch { "" }
$pythonPkgs   = ""
try {
    $pkgLines   = & $pythonCmd -m pip list --format=columns 2>$null | Select-Object -Skip 2
    $pythonPkgs = ($pkgLines | ForEach-Object {
        $p = $_ -split '\s+',2; if ($p[0]) { "$($p[0]) $($p[1])".Trim() }
    }) -join ", "
} catch {}

# Hook scripts
Write-Host "  Updating hook scripts..."
$hooksSource = Join-Path $scriptDir "hooks"
foreach ($hookFile in @(
    "auto-checkpoint.ps1", "check-secrets.ps1",
    "check-sensitive-file.ps1", "check-claude-md-sync.ps1"
)) {
    $src = Join-Path $hooksSource $hookFile
    $dst = Join-Path $workspace $hookFile
    if (Test-Path $src) {
        $content = (Get-Content $src -Raw -Encoding UTF8).Replace("{{WORKSPACE}}", $workspace)
        Set-Content $dst $content -Encoding UTF8 -NoNewline
        Write-Host "    $hookFile"
    } else {
        Write-Host "    WARNING: $hookFile not found in hooks/" -ForegroundColor Yellow
    }
}

# Optional scripts (only if already installed in workspace)
$optionalScripts = @("check-model-updates.py", "scan-model-usage.py", "setup-model-check-task.ps1")
$optionalUpdated = @()
foreach ($f in $optionalScripts) {
    $dst = Join-Path $workspace $f
    $src = Join-Path $scriptDir $f
    if ((Test-Path $dst) -and (Test-Path $src)) {
        Copy-Item $src $dst -Force
        $optionalUpdated += $f
    }
}
if ($optionalUpdated.Count -gt 0) {
    Write-Host "  Updating optional scripts..."
    $optionalUpdated | ForEach-Object { Write-Host "    $_" }
}

# ~/.claude/settings.json -- merge our managed hooks, preserve user additions
Write-Host "  Updating ~/.claude/settings.json..."
function Get-HookCmd([string]$script) { "pwsh -NoProfile -File `"$(Join-Path $workspace $script)`"" }

# Our managed scripts -- used to identify which hook entries we own
$ourScripts = @("auto-checkpoint.ps1","check-secrets.ps1","check-sensitive-file.ps1","check-claude-md-sync.ps1")

function Test-IsOurHook($entry) {
    foreach ($h in @($entry.hooks)) {
        foreach ($s in $ourScripts) {
            if ($h.command -match [regex]::Escape($s)) { return $true }
        }
    }
    return $false
}

# Latest versions of our managed hook entries
$ourHooksByEvent = @{
    PreToolUse  = @(@{ matcher="Edit|Write"; hooks=@(@{ type="command"; command=(Get-HookCmd "check-sensitive-file.ps1") }) })
    PostToolUse = @(
        @{ matcher="Write|Edit"; hooks=@(@{ type="command"; command=(Get-HookCmd "check-secrets.ps1") }) },
        @{ matcher="Write|Edit"; hooks=@(@{ type="command"; command=(Get-HookCmd "check-claude-md-sync.ps1") }) }
    )
    Stop        = @(@{ hooks=@(@{ type="command"; command=(Get-HookCmd "auto-checkpoint.ps1") }) })
    PreCompact  = @(@{ hooks=@(@{ type="command"; command=(Get-HookCmd "auto-checkpoint.ps1") }) })
}

# Load existing settings or start from a minimal base
$settingsObj = if (Test-Path $settingsPath) {
    try { Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable }
    catch { @{} }
} else { @{} }

if (-not $settingsObj.hooks)       { $settingsObj.hooks = @{} }
if (-not $settingsObj.permissions) { $settingsObj.permissions = @{} }

# For each managed event: keep user's non-our entries, replace our entries with latest
$preserved = @()
foreach ($event in $ourHooksByEvent.Keys) {
    $existing    = if ($settingsObj.hooks[$event]) { @($settingsObj.hooks[$event]) } else { @() }
    $userEntries = @($existing | Where-Object { -not (Test-IsOurHook $_) })
    if ($userEntries.Count -gt 0) { $preserved += "$event ($($userEntries.Count) custom)" }
    # Our entries first, user's custom entries appended
    $settingsObj.hooks[$event] = @($ourHooksByEvent[$event]) + $userEntries
}

# Ensure deny list exists and contains our entries (merge, don't replace)
$ourDeny = @("Bash(rm -rf:*)","Bash(git push --force:*)","Bash(git push -f:*)","Bash(git reset --hard:*)","Bash(git clean -f:*)")
$existingDeny = if ($settingsObj.permissions.deny) { @($settingsObj.permissions.deny) } else { @() }
$merged = @($existingDeny) + @($ourDeny | Where-Object { $_ -notin $existingDeny })
$settingsObj.permissions.deny = $merged

if (-not $settingsObj.autoUpdatesChannel) { $settingsObj.autoUpdatesChannel = "latest" }

$settingsObj | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
if ($preserved.Count -gt 0) {
    Write-Host "    settings.json (preserved user hooks: $($preserved -join ', '))"
} else {
    Write-Host "    settings.json"
}

# ~/.claude/CLAUDE.md -- generate new content from template, ask before overwriting
Write-Host "  Checking ~/.claude/CLAUDE.md..."
$claudeMdPath = Join-Path $claudeDir "CLAUDE.md"
$tmplPath     = Join-Path $scriptDir "templates\global-claude-md.md"

if (Test-Path $tmplPath) {
    $nodeVersion = try { (& node --version 2>&1).Trim() } catch { "" }
    $pwshPath    = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source ?? "pwsh"
    $ghPath      = (Get-Command gh   -ErrorAction SilentlyContinue)?.Source
    $otherTools  = @()
    if ($nodeVersion) { $otherTools += "- **Node.js / npm**: in PATH ($nodeVersion)" }
    if ($pwshPath)    { $otherTools += "- **PowerShell 7**: ``$pwshPath``" }
    if ($ghPath)      { $otherTools += "- **GitHub CLI (gh)**: found" }
    $otherToolsStr = if ($otherTools) { $otherTools -join "`n" } else { "- (add installed tools here)" }

    $newClaudeMd = (Get-Content $tmplPath -Raw -Encoding UTF8) `
        -replace '\{\{WORKSPACE\}\}',       $workspace `
        -replace '\{\{PYTHON_VERSION\}\}',  $pythonVersion `
        -replace '\{\{PYTHON_CMD\}\}',      $pythonCmd `
        -replace '\{\{PYTHON_EXE\}\}',      $pythonExe `
        -replace '\{\{SITE_PACKAGES\}\}',   $sitePackages `
        -replace '\{\{PYTHON_PACKAGES\}\}', $pythonPkgs `
        -replace '\{\{OTHER_TOOLS_LIST\}\}',$otherToolsStr `
        -replace '\{\{USERNAME\}\}',        $env:USERNAME

    $shouldWrite = $true
    if (Test-Path $claudeMdPath) {
        # If this machine's workspace IS the parent of scriptDir (i.e. the repo owner),
        # skip CLAUDE.md -- their personal version has private content not in the template.
        $scriptParent = Split-Path $scriptDir -Parent
        if ($scriptParent -eq $workspace) {
            Write-Host "    CLAUDE.md skipped -- this is the source machine. Update ~/.claude/CLAUDE.md manually if needed." -ForegroundColor Yellow
            $shouldWrite = $false
        } else {
            $existingHash = (Get-FileHash $claudeMdPath -Algorithm MD5).Hash
            $newHash = (Get-FileHash ([System.IO.MemoryStream][System.Text.Encoding]::UTF8.GetBytes($newClaudeMd)) -Algorithm MD5).Hash
            if ($existingHash -eq $newHash) {
                Write-Host "    CLAUDE.md is already up to date -- skipped"
                $shouldWrite = $false
            } else {
                Write-Host ""
                Write-Host "    ~/.claude/CLAUDE.md has changes from the new template." -ForegroundColor Yellow
                Write-Host "    This will REPLACE your current CLAUDE.md, including any edits you made."
                Write-Host "    Your workspace CLAUDE.md is NOT affected."
                Write-Host ""
                $claudeConfirm = Read-Host "    Update ~/.claude/CLAUDE.md? [y/N]"
                $shouldWrite = ($claudeConfirm -match '^[Yy]')
                if (-not $shouldWrite) {
                    Write-Host "    Skipped. Compare templates\global-claude-md.md to your CLAUDE.md to apply changes manually." -ForegroundColor Yellow
                }
            }
        }
    }

    if ($shouldWrite) {
        Set-Content $claudeMdPath $newClaudeMd -Encoding UTF8
        Write-Host "    CLAUDE.md updated"
    }
} else {
    Write-Host "    WARNING: Template not found -- CLAUDE.md not updated" -ForegroundColor Yellow
}

# Scheduled task (re-register if already exists to pick up any changes)
$existingTask = Get-ScheduledTask -TaskName "ClaudeModelCheck" -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "  Re-registering ClaudeModelCheck scheduled task..."
    $pyScript = Join-Path $workspace "check-model-updates.py"
    $logFile  = Join-Path $workspace "check-model-updates.log"
    if (Test-Path $pyScript) {
        $action   = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $pythonCmd `"$pyScript`" >> `"$logFile`" 2>&1"
        $trigger  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "9:00AM"
        $stSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable -RunOnlyIfNetworkAvailable
        Unregister-ScheduledTask -TaskName "ClaudeModelCheck" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "ClaudeModelCheck" -Action $action -Trigger $trigger -Settings $stSettings -RunLevel Limited -Description "Weekly Claude model update check" | Out-Null
        Write-Host "    ClaudeModelCheck (Mondays 9 AM)"
    } else {
        Write-Host "    WARNING: check-model-updates.py not found -- task not updated" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# SCREEN 6: Done
# ---------------------------------------------------------------------------
Write-Header "Update Complete"

Write-Host "  All hooks, settings, and conventions have been updated."
Write-Host ""
Write-Host "  Start a new Claude Code session to pick up the changes:"
Write-Host "    cd $workspace"
Write-Host "    claude"
Write-Host ""
Write-Host "  To check what conventions changed, review the commit log:"
Write-Host "    cd $scriptDir"
Write-Host "    git log --oneline -10"
Write-Host ""
