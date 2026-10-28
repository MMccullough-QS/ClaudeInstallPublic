# check-secrets.ps1
# PostToolUse hook for Write|Edit tool calls.
# Scans written file content for exposed credentials and injects a warning
# via additionalContext if any patterns are matched.

$raw = $env:CLAUDE_TOOL_INPUT
if (-not $raw) { exit 0 }

$path = $null
try {
    $parsed = $raw | ConvertFrom-Json
    # tool_input.file_path is the correct location in the hook JSON envelope
    $path = $parsed.tool_input.file_path
    if (-not $path) { $path = $parsed.file_path }  # fallback for flat payloads
} catch {
    if ($raw -match '"file_path"\s*:\s*"([^"]+)"') {
        $path = $Matches[1]
    }
}

if (-not $path) { exit 0 }
if (-not (Test-Path $path -PathType Leaf)) { exit 0 }

# Skip binary/non-text files
$skipExts = @('.exe','.dll','.zip','.tar','.gz','.png','.jpg','.jpeg',
              '.gif','.mp3','.mp4','.R5C','.mdb','.accdb','.bk1',
              '.drawio','.xlsx','.docx','.pdf','.db','.sqlite')
$ext = [System.IO.Path]::GetExtension($path).ToLower()
if ($ext -in $skipExts) { exit 0 }

$content = Get-Content $path -Raw -ErrorAction SilentlyContinue
if (-not $content) { exit 0 }

$patterns = [ordered]@{
    'Anthropic API key'          = 'sk-ant-api0[3-9]-[A-Za-z0-9_\-]{93}'
    'AWS access key'             = 'AKIA[A-Z0-9]{16}'
    'GitHub PAT (classic)'       = 'ghp_[A-Za-z0-9]{36}'
    'GitHub fine-grained PAT'    = 'github_pat_[A-Za-z0-9_]{82}'
    'Slack bot token'            = 'xoxb-[0-9A-Za-z\-]+'
    'Google API key'             = 'AIza[0-9A-Za-z\-_]{35}'
    'Private key block'          = '-----BEGIN .{0,20}PRIVATE KEY'
}

$hits = @()
foreach ($name in $patterns.Keys) {
    if ($content -match $patterns[$name]) {
        $hits += $name
    }
}

if ($hits.Count -gt 0) {
    $fileName = [System.IO.Path]::GetFileName($path)
    $msg = "SECRET SCAN WARNING: Possible credential(s) detected in ${fileName} -- $($hits -join ', '). Verify these are not real credentials before continuing."
    @{
        hookSpecificOutput = @{
            hookEventName     = "PostToolUse"
            additionalContext = $msg
        }
    } | ConvertTo-Json -Compress
}

exit 0
