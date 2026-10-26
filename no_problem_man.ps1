# no_problem_man 1.0
# Windows 10/11 Startup Cleanup
# Requires Windows PowerShell 5.1
# Run as Administrator
# Does not uninstall apps or stop running processes.

$ErrorActionPreference = 'Stop'

$apps = @(
    'chrome',
    'msedge',
    'firefox',
    'opera',
    'brave',
    'vivaldi',
    'telegram',
    'viber',
    'discord',
    'discordptb',
    'discordcanary',
    'whatsapp',
    'signal',
    'skype',
    'teams',
    'ms-teams',
    'slack',
    'zoom',
    'steam',
    'epicgameslauncher',
    'galaxyclient',
    'ubisoftconnect',
    'eadesktop',
    'origin',
    'spotify',
    'tidal',
    'ldplayer',
    'dnplayer',
    'nox',
    'noxplayer',
    'memu',
    'hd-player',
    'bluestacks',
    'androidemulator',
    'mumuplayer'
)

function IsOptionalApp {
    param(
        [string]$Name,
        [string]$Command
    )

    $text = "$Name $Command".ToLowerInvariant()

    # Never modify known security or system-related entries.
    if ($text -match 'defender|antivirus|security|driver|backup|vpn|onedrive|dropbox|windows defender') {
        return $false
    }

    foreach ($app in $apps) {
        $escaped = [regex]::Escape($app)
        $pattern = "(^|[^a-z0-9])$escaped(\.exe)?([^a-z0-9]|$)"

        if ($text -match $pattern) {
            return $true
        }
    }

    return $false
}

$changed = 0
$errors = 0

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $env:ProgramData 'no_problem_man\Backups'
$backup = Join-Path $backupRoot $timestamp

New-Item -ItemType Directory -Path $backup -Force | Out-Null

function SaveRecord {
    param(
        [string]$Type,
        [string]$Name,
        [string]$Value
    )

    $record = [pscustomobject]@{
        Time  = (Get-Date).ToString('o')
        Type  = $Type
        Name  = $Name
        Value = $Value
    }

    $file = Join-Path $backup 'changes.jsonl'

    $record |
        ConvertTo-Json -Compress |
        Add-Content -LiteralPath $file -Encoding UTF8
}

Write-Host ''
Write-Host '============================================'
Write-Host '         no_problem_man 1.0'
Write-Host '      Windows Startup Cleanup'
Write-Host '============================================'
Write-Host ''
Write-Host "Backup directory: $backup"
Write-Host ''

# --------------------------------------------------
# 1. REGISTRY STARTUP ENTRIES
# --------------------------------------------------

$runKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)

foreach ($path in $runKeys) {

    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }

    try {
        $key = Get-Item -LiteralPath $path

        foreach ($name in $key.GetValueNames()) {

            $value = [string]$key.GetValue($name)

            if (-not (IsOptionalApp -Name $name -Command $value)) {
                continue
            }

            try {
                SaveRecord -Type 'Registry' -Name "$path\$name" -Value $value

                Remove-ItemProperty `
                    -LiteralPath $path `
                    -Name $name `
                    -ErrorAction Stop

                Write-Host "Disabled registry: $name"
                $changed++
            }
            catch {
                Write-Warning "Registry entry failed: $name"
                Write-Warning $_.Exception.Message
                $errors++
            }
        }
    }
    catch {
        Write-Warning "Cannot inspect registry path: $path"
        $errors++
    }
}

# --------------------------------------------------
# 2. STARTUP FOLDERS
# --------------------------------------------------

$startupFolders = @(
    [Environment]::GetFolderPath('Startup'),
    [Environment]::GetFolderPath('CommonStartup')
)

foreach ($folder in $startupFolders) {

    if (-not (Test-Path -LiteralPath $folder)) {
        continue
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $files = @(Get-ChildItem -LiteralPath $folder -File)

        foreach ($file in $files) {

            if ($file.Extension -ne '.lnk') {
                continue
            }

            try {
                $shortcut = $shell.CreateShortcut($file.FullName)
                $target = [string]$shortcut.TargetPath

                if (-not (IsOptionalApp -Name $file.BaseName -Command $target)) {
                    continue
                }

                $newName = 'shortcut_' +
                    [guid]::NewGuid().ToString('N') +
                    '.lnk'

                $destination = Join-Path $backup $newName

                SaveRecord `
                    -Type 'Shortcut' `
                    -Name $file.FullName `
                    -Value $destination

                Move-Item `
                    -LiteralPath $file.FullName `
                    -Destination $destination `
                    -ErrorAction Stop

                Write-Host "Disabled shortcut: $($file.Name)"
                $changed++
            }
            catch {
                Write-Warning "Shortcut failed: $($file.Name)"
                Write-Warning $_.Exception.Message
                $errors++
            }
        }
    }
    catch {
        Write-Warning "Cannot inspect startup folder: $folder"
        $errors++
    }
}

# --------------------------------------------------
# 3. SCHEDULED TASKS
# --------------------------------------------------

if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {

    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop)

        foreach ($task in $tasks) {

            try {
                if ($task.State -eq 'Disabled') {
                    continue
                }

                # Avoid Microsoft system tasks.
                if ($task.TaskPath -match '^\\Microsoft\\') {
                    continue
                }

                $triggered = $false

                foreach ($trigger in $task.Triggers) {

                    if ($trigger.CimClass.CimClassName -match 'LogonTrigger|BootTrigger') {
                        $triggered = $true
                    }
                }

                if (-not $triggered) {
                    continue
                }

                $command = (
                    (
                        $task.Actions | ForEach-Object {
                            "$($_.Execute) $($_.Arguments)"
                        }
                    ) -join ' '
                )

                if (-not (IsOptionalApp -Name $task.TaskName -Command $command)) {
                    continue
                }

                $taskIdentity = $task.TaskPath + $task.TaskName

                SaveRecord `
                    -Type 'Task' `
                    -Name $taskIdentity `
                    -Value $command

                Disable-ScheduledTask `
                    -TaskName $task.TaskName `
                    -TaskPath $task.TaskPath `
                    -ErrorAction Stop |
                    Out-Null

                Write-Host "Disabled task: $($task.TaskName)"
                $changed++
            }
            catch {
                Write-Warning "Task failed: $($task.TaskName)"
                Write-Warning $_.Exception.Message
                $errors++
            }
        }
    }
    catch {
        Write-Warning 'Cannot inspect scheduled tasks.'
        $errors++
    }
}

# --------------------------------------------------
# 4. RESULTS
# --------------------------------------------------

Write-Host ''
Write-Host '============================================'
Write-Host '                  RESULT'
Write-Host '============================================'
Write-Host ''
Write-Host "Startup entries disabled: $changed"
Write-Host "Errors: $errors"
Write-Host ''
Write-Host "Backup: $backup"
Write-Host ''
Write-Host 'No applications were uninstalled.'
Write-Host 'Currently running processes were not stopped.'
Write-Host 'Restart Windows to observe startup changes.'
Write-Host ''

Read-Host 'Press Enter to close'

