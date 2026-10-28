# auto-checkpoint.ps1
# Called by Claude Code Stop and PreCompact hooks after each completed turn.
# Commits any modified tracked files in the active git repo, then backs up
# ~/.claude/CLAUDE.md, memory files, and config files to the workspace repo.

$workDir = if ($env:CLAUDE_WORKING_DIRECTORY) { $env:CLAUDE_WORKING_DIRECTORY } else { "{{WORKSPACE}}" }

# Walk up from workDir to find nearest git root
$dir = $workDir
while ($dir -and $dir -ne [System.IO.Path]::GetPathRoot($dir)) {
    if (Test-Path (Join-Path $dir ".git")) {
        Push-Location $dir
        try {
            $status = git status --porcelain 2>$null
            if ($status) {
                git add -u 2>$null
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
                git commit -m "Auto-checkpoint ($timestamp)" --no-verify 2>$null
            }
            # Push any unpushed commits (committed this turn or from prior turns)
            $ahead = git rev-list --count "@{u}..HEAD" 2>$null
            if ($ahead -and [int]$ahead -gt 0) {
                git push 2>$null
            }
        } finally {
            Pop-Location
        }
        break
    }
    $dir = [System.IO.Path]::GetDirectoryName($dir)
}

$workspaceRepo = "{{WORKSPACE}}"

# Backup ~/.claude/CLAUDE.md to workspace repo as global-CLAUDE.md
$claudeMdSrc = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
$claudeMdDst = Join-Path $workspaceRepo "global-CLAUDE.md"

if (Test-Path $claudeMdSrc) {
    $changed = $true
    if (Test-Path $claudeMdDst) {
        $srcHash = (Get-FileHash $claudeMdSrc -Algorithm MD5).Hash
        $dstHash = (Get-FileHash $claudeMdDst -Algorithm MD5).Hash
        $changed = ($srcHash -ne $dstHash)
    }
    if ($changed) {
        Copy-Item $claudeMdSrc $claudeMdDst -Force
        Push-Location $workspaceRepo
        try {
            git add global-CLAUDE.md 2>$null
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
            git commit -m "Backup global CLAUDE.md ($ts)" --no-verify 2>$null
            $ahead2 = git rev-list --count "@{u}..HEAD" 2>$null
            if ($ahead2 -and [int]$ahead2 -gt 0) {
                git push 2>$null
            }
        } finally {
            Pop-Location
        }
    }
}

# Backup ~/.claude/projects/<encoded-workspace>/memory/ to workspace repo
# Memory path encoding: C:\Users\Name\Claude -> C--Users-Name-Claude
$encoded = $workspaceRepo -replace ':\\', '--' -replace '\\', '-'
$memorySrc = Join-Path $env:USERPROFILE ".claude\projects\$encoded\memory"
$memoryDst = Join-Path $workspaceRepo "memory-backup"

if (Test-Path $memorySrc) {
    if (-not (Test-Path $memoryDst)) { New-Item -ItemType Directory -Path $memoryDst | Out-Null }

    # robocopy: /MIR mirrors src to dst, /NJH /NJS /NP suppress headers/progress
    # Exit codes 0-7 are success (0=no change, 1=copied, 2-7=extras/mismatches)
    $roboOut = robocopy $memorySrc $memoryDst "*.md" /MIR /NJH /NJS /NP 2>$null
    $anyChanged = $LASTEXITCODE -ge 1 -and $LASTEXITCODE -le 7

    if ($anyChanged) {
        Push-Location $workspaceRepo
        try {
            git add "memory-backup/" 2>$null
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
            git commit -m "Backup memory files ($ts)" --no-verify 2>$null
            $ahead3 = git rev-list --count "@{u}..HEAD" 2>$null
            if ($ahead3 -and [int]$ahead3 -gt 0) {
                git push 2>$null
            }
        } finally {
            Pop-Location
        }
    }
}

# Backup ~/.claude config files (settings.json, settings.local.json, mcp.json)
# .mcp.json is sanitized -- tokens replaced with placeholders before committing.
$configSrc = Join-Path $env:USERPROFILE ".claude"
$configDst = Join-Path $workspaceRepo "config-backup"

if (-not (Test-Path $configDst)) { New-Item -ItemType Directory -Path $configDst | Out-Null }

$configChanged = $false

foreach ($file in @("settings.json", "settings.local.json")) {
    $src = Join-Path $configSrc $file
    $dst = Join-Path $configDst $file
    if (Test-Path $src) {
        $copy = $true
        if (Test-Path $dst) {
            $srcHash = (Get-FileHash $src -Algorithm MD5).Hash
            $dstHash = (Get-FileHash $dst -Algorithm MD5).Hash
            $copy = ($srcHash -ne $dstHash)
        }
        if ($copy) { Copy-Item $src $dst -Force; $configChanged = $true }
    }
}

$mcpSrc = Join-Path $configSrc ".mcp.json"
$mcpDst = Join-Path $configDst "mcp.json"
if (Test-Path $mcpSrc) {
    # Use py launcher to sanitize tokens -- PowerShell regex hangs on this pattern in hook context
    $pyScript = "import re,sys; raw=open(sys.argv[1]).read(); out=re.sub(r'""GITHUB_PERSONAL_ACCESS_TOKEN""\s*:\s*""[^""]*""','""GITHUB_PERSONAL_ACCESS_TOKEN"":""{GITHUB_PERSONAL_ACCESS_TOKEN}""',raw); cur=open(sys.argv[2]).read() if __import__('os').path.exists(sys.argv[2]) else ''; changed=out!=cur; open(sys.argv[2],'w').write(out) if changed else None; print(1 if changed else 0)"
    $result = py -c $pyScript $mcpSrc $mcpDst 2>$null
    if ($result -eq "1") { $configChanged = $true }
}

if ($configChanged) {
    Push-Location $workspaceRepo
    try {
        git add "config-backup/" 2>$null
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
        git commit -m "Backup config files ($ts)" --no-verify 2>$null
        $ahead4 = git rev-list --count "@{u}..HEAD" 2>$null
        if ($ahead4 -and [int]$ahead4 -gt 0) {
            git push 2>$null
        }
    } finally {
        Pop-Location
    }
}
