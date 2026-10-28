# check-sensitive-file.ps1
# PreToolUse hook for Edit and Write tool calls.
# Blocks writes to sensitive files by checking file_path only -- not content.

$raw = $env:CLAUDE_TOOL_INPUT
if (-not $raw) { exit 0 }

$path = $null

# Try JSON parse first; fall back to regex if backslashes in Windows paths break parsing
try {
    $parsed = $raw | ConvertFrom-Json
    $path = $parsed.file_path
} catch {
    # Extract file_path value via regex (handles unescaped backslashes in Windows paths)
    if ($raw -match '"file_path"\s*:\s*"([^"]+)"') {
        $path = $Matches[1]
    }
}

if (-not $path) { exit 0 }

# Check only the filename extension
$filename = [System.IO.Path]::GetFileName($path)
if ($filename -match '\.(env|credentials|secret|key)$') {
    Write-Error "BLOCKED: Sensitive file path detected: $filename"
    exit 1
}

exit 0
