# check-claude-md-sync.ps1
# PostToolUse hook: fires on every Write/Edit.
# If ~/.claude/CLAUDE.md was just modified, reminds Claude to update ReinstallClaude.md.

$toolInput = $env:CLAUDE_TOOL_INPUT | ConvertFrom-Json -ErrorAction SilentlyContinue
$filePath = $toolInput.tool_input.file_path

if ($filePath -match '\.claude[/\\]CLAUDE\.md$') {
    @{
        hookSpecificOutput = @{
            additionalContext = "SYNC REMINDER: ~/.claude/CLAUDE.md was just modified. Before closing this session, update ReinstallClaude.md ({{WORKSPACE}}\ReinstallClaude.md) to reflect any new or changed rules. The auto-checkpoint Stop hook will also back up this file to global-CLAUDE.md in the repo."
        }
    } | ConvertTo-Json -Compress | Write-Output
}

exit 0
