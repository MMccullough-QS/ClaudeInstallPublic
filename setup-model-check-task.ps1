# setup-model-check-task.ps1
# Registers a weekly Windows Task Scheduler task that runs check-model-updates.py.
# Run once after initial setup, or re-run to update the task.
#
# Task: "ClaudeModelCheck" -- runs every Monday at 9 AM

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$pythonCmd  = if (Get-Command py -ErrorAction SilentlyContinue) { "py" }
              elseif (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" }
              else { "python" }
$scriptPath = Join-Path $scriptDir "check-model-updates.py"
$logPath    = Join-Path $scriptDir "check-model-updates.log"
$taskName   = "ClaudeModelCheck"

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Script not found: $scriptPath" -ForegroundColor Red
    exit 1
}

Write-Host "Registering Task Scheduler task: $taskName" -ForegroundColor Yellow
Write-Host "  Script:  $scriptPath"
Write-Host "  Python:  $pythonCmd"
Write-Host "  Log:     $logPath"
Write-Host "  Schedule: Every Monday at 9:00 AM"
Write-Host ""

# Build the action: run python script, append stdout+stderr to log
$action  = New-ScheduledTaskAction `
    -Execute $pythonCmd `
    -Argument "`"$scriptPath`" >> `"$logPath`" 2>&1"

# WHY: weekly on Monday -- model releases don't happen daily; weekly is sufficient
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "9:00AM"

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

# Remove existing task if present, then register fresh
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName   $taskName `
    -Action     $action `
    -Trigger    $trigger `
    -Settings   $settings `
    -RunLevel   Limited `
    -Description "Weekly check for new Claude model releases. Writes notification to ~/.claude/ if updates found." `
    | Out-Null

Write-Host "Task registered successfully." -ForegroundColor Green
Write-Host ""
Write-Host "To run immediately: Start-ScheduledTask -TaskName '$taskName'"
Write-Host "To view log:        Get-Content '$logPath' -Tail 50"
Write-Host "To remove task:     Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
Write-Host ""

# Run once now to seed the state file with the current Claude Code version
$run = Read-Host "Run the check now to seed initial state? [Y/n]"
if ($run -notmatch '^[Nn]') {
    Write-Host "Running initial check..." -ForegroundColor Yellow
    & $pythonCmd $scriptPath
}
