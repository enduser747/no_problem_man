param(
    [switch]$Restore,
    [string]$OriginSid = ''
)

# no_problem_man 1.0 - Windows PowerShell 5.1, Windows 10/11
# Core based on WinCare Startup v1.0 (first working build)
# Conservative, reversible startup clean-up. No network traffic.
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { exit 1 }
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}" -OriginSid "{1}"' -f $PSCommandPath, $currentSid
    if ($Restore) { $args += ' -Restore' }
    try { Start-Process -FilePath $shell -ArgumentList $args -Verb RunAs -ErrorAction Stop }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show('Для зміни автозавантаження потрібен дозвіл адміністратора.', 'no_problem_man', 'OK', 'Warning') | Out-Null
    }
    exit
}
if (-not $OriginSid) { $OriginSid = $currentSid }
$sameUser = $currentSid -eq $OriginSid

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$base = Join-Path $env:ProgramData 'no_problem_man\Backups'
$script:manifest = $null
$script:manifestFile = ''
$script:busy = $false
$script:changed = 0
$script:kept = 0
$script:errors = 0

# Explicit allowlist: program EXECUTABLES, never disable unknown entries by display name alone.
# Backups/sync, VPN, antiviruses, hardware helpers and Windows components are omitted.
$appExe = @{
    'chrome.exe'='Chrome'; 'msedge.exe'='Microsoft Edge'; 'firefox.exe'='Firefox'
    'brave.exe'='Brave'; 'vivaldi.exe'='Vivaldi'; 'opera.exe'='Opera'
    'opera_gx.exe'='Opera GX'; 'telegram.exe'='Telegram'; 'viber.exe'='Viber'
    'whatsapp.exe'='WhatsApp'; 'discord.exe'='Discord'; 'signal.exe'='Signal'
    'skype.exe'='Skype'; 'teams.exe'='Microsoft Teams'; 'ms-teams.exe'='Microsoft Teams'
    'slack.exe'='Slack'; 'zoom.exe'='Zoom'; 'wechat.exe'='WeChat'
    'line.exe'='LINE'; 'kakaotalk.exe'='KakaoTalk'; 'element.exe'='Element'
    'mattermost.exe'='Mattermost'; 'rambox.exe'='Rambox'; 'franz.exe'='Franz'
    'wire.exe'='Wire'; 'threema.exe'='Threema'; 'guilded.exe'='Guilded'
    'steam.exe'='Steam'; 'epicgameslauncher.exe'='Epic Games'
    'galaxyclient.exe'='GOG Galaxy'; 'ubisoftconnect.exe'='Ubisoft Connect'
    'origin.exe'='Origin'; 'eadesktop.exe'='EA App'; 'battlenet.exe'='Battle.net'
    'battle.net.exe'='Battle.net'; 'spotify.exe'='Spotify'; 'tidal.exe'='TIDAL'
    'deezer.exe'='Deezer'; 'ldplayer.exe'='LDPlayer'; 'dnplayer.exe'='LDPlayer'
    'ldlauncher.exe'='LDPlayer'; 'bluestacks.exe'='BlueStacks'
    'hd-player.exe'='BlueStacks'; 'hd-agent.exe'='BlueStacks'
    'nox.exe'='Nox'; 'noxplayer.exe'='Nox'; 'noxvmhandle.exe'='Nox'
    'memu.exe'='MEmu'; 'memuconsole.exe'='MEmu'; 'memuheadless.exe'='MEmu'
    'androidemulator.exe'='GameLoop'; 'appmarket.exe'='GameLoop'
    'mumuplayer.exe'='MuMu'; 'mumuemulator.exe'='MuMu'
    'genymotion.exe'='Genymotion'; 'genymotion-player.exe'='Genymotion'
}
$protectedRx = '(?i)(defender|msmpeng|securityhealth|antimalware|antivirus|avast|avg|bitdefender|eset|kaspersky|sophos|malwarebytes|vpn|wireguard|openvpn|forticlient|backup|acronis|veeam|dropbox|onedrive|google[ ]?drive|synaptics|elanservice|realtek|intel|nvidia|amd|radeon|touchpad|hotkey|bluetooth|wifi|wlan)'
$systemPathRx = '(?i)^\s*"?(?:[A-Z]:)?\\(?:Windows|WindowsApps\\Microsoft\\Windows)\\'

function Get-Identity([string]$command, [string]$itemName) {
    if ([string]::IsNullOrWhiteSpace($command)) { return $null }
    if ($command -match $protectedRx) { return $null }
    if ($command -match $systemPathRx) { return $null }
    $matchesExe = [regex]::Matches($command, '(?i)(?<![a-z0-9_.-])([a-z0-9_.-]+\.exe)(?![a-z0-9_.-])')
    if ($matchesExe.Count -eq 0) { return $null }
    $first = $matchesExe[0].Groups[1].Value.ToLowerInvariant()
    if ($appExe.ContainsKey($first)) { return $appExe[$first] }
    # Squirrel updater: only if its own path clearly names the product AND the
    # launch arguments name the same approved executable. Generic updater alone is unsafe.
    if ($first -in @('update.exe','squirrel.exe')) {
        for ($i = 1; $i -lt $matchesExe.Count; $i++) {
            $child = $matchesExe[$i].Groups[1].Value.ToLowerInvariant()
            if ($appExe.ContainsKey($child)) {
                $app = $appExe[$child]
                $folder = [regex]::Escape($app.Replace(' ','').ToLowerInvariant())
                $lower = $command.ToLowerInvariant().Replace(' ','')
                if ($lower -match ('(?i)\\' + $folder + '(?:\\|-)')) { return $app }
            }
        }
    }
    return $null
}

$form = New-Object Windows.Forms.Form
$form.Text = 'no_problem_man 1.0 | Startup Control'
$form.Size = New-Object Drawing.Size(730,505)
$form.MinimumSize = New-Object Drawing.Size(730,505)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::FromArgb(23,30,40)
$form.ForeColor = [Drawing.Color]::FromArgb(233,239,245)
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$form.MaximizeBox = $false

$title = New-Object Windows.Forms.Label
$title.Text = 'no_problem_man'
$title.Font = New-Object Drawing.Font('Segoe UI',19,[Drawing.FontStyle]::Bold)
$title.SetBounds(25,18,600,38)
$title.ForeColor = [Drawing.Color]::FromArgb(238,243,248)
$form.Controls.Add($title)

$desc = New-Object Windows.Forms.Label
$desc.Text = 'STARTUP CONTROL   /   WINDOWS 10 + 11'
$desc.SetBounds(27,62,630,23)
$desc.Font = New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold)
$desc.ForeColor = [Drawing.Color]::FromArgb(111,184,226)
$form.Controls.Add($desc)

$panel = New-Object Windows.Forms.Panel
$panel.SetBounds(24,104,663,129)
$panel.BackColor = [Drawing.Color]::FromArgb(35,45,59)
$form.Controls.Add($panel)

$stage = New-Object Windows.Forms.Label
$stage.Text = 'Готово до запуску'
$stage.ForeColor = [Drawing.Color]::FromArgb(233,239,245)
$stage.Font = New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
$stage.SetBounds(15,15,620,30)
$panel.Controls.Add($stage)

$progress = New-Object Windows.Forms.ProgressBar
$progress.SetBounds(16,58,629,10)
$progress.Style = 'Blocks'
$progress.Value = 0
$progress.Maximum = 100
$panel.Controls.Add($progress)

$stats = New-Object Windows.Forms.Label
$stats.Text = 'Вимкнено: —      Збережено: —      Помилок: —'
$stats.ForeColor = [Drawing.Color]::FromArgb(169,186,203)
$stats.Font = New-Object Drawing.Font('Segoe UI',10)
$stats.SetBounds(17,83,620,29)
$panel.Controls.Add($stats)

$runButton = New-Object Windows.Forms.Button
$runButton.Text = 'ОПТИМІЗУВАТИ АВТОЗАПУСК'
$runButton.SetBounds(24,249,352,42)
$runButton.BackColor = [Drawing.Color]::FromArgb(108,175,223)
$runButton.ForeColor = [Drawing.Color]::FromArgb(20,29,39)
$runButton.FlatStyle = 'Flat'
$runButton.FlatAppearance.BorderSize = 0
$runButton.UseVisualStyleBackColor = $false
$runButton.Font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$form.Controls.Add($runButton)

$restoreButton = New-Object Windows.Forms.Button
$restoreButton.Text = 'Відновити'
$restoreButton.SetBounds(388,249,145,42)
$restoreButton.BackColor = [Drawing.Color]::FromArgb(48,62,79)
$restoreButton.ForeColor = [Drawing.Color]::FromArgb(233,239,245)
$restoreButton.FlatStyle = 'Flat'
$restoreButton.FlatAppearance.BorderSize = 0
$restoreButton.UseVisualStyleBackColor = $false
$form.Controls.Add($restoreButton)

$logBox = New-Object Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.WordWrap = $true
$logBox.BackColor = [Drawing.Color]::FromArgb(30,40,53)
$logBox.ForeColor = [Drawing.Color]::FromArgb(216,227,238)
$logBox.BorderStyle = 'FixedSingle'
$logBox.SetBounds(24,318,663,115)
$logBox.Font = New-Object Drawing.Font('Consolas',9)
$form.Controls.Add($logBox)

$footer = New-Object Windows.Forms.Label
$footer.Text = 'OFFLINE  /  БЕЗ ВИДАЛЕННЯ ПРОГРАМ  /  РЕЗЕРВУВАННЯ ЗМІН'
$footer.SetBounds(27,445,650,22)
$footer.Font = New-Object Drawing.Font('Segoe UI',8)
$footer.ForeColor = [Drawing.Color]::FromArgb(149,165,182)
$form.Controls.Add($footer)

$form.Add_FormClosing({ param($sender,$e) if ($script:busy) { $e.Cancel = $true } })

function Ui-Step([string]$message) {
    $stage.Text = $message
    $logBox.AppendText(('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'),$message) + "`r`n")
    $logBox.SelectionStart = $logBox.TextLength; $logBox.ScrollToCaret()
    [Windows.Forms.Application]::DoEvents()
}
function Ui-Count { $stats.Text = 'Вимкнено: {0}     Збережено: {1}     Помилок: {2}' -f $script:changed,$script:kept,$script:errors }

function Save-State {
    $json = $script:manifest | ConvertTo-Json -Depth 12
    $tmp = $script:manifestFile + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($true)))
    [IO.File]::Copy($tmp,$script:manifestFile,$true)
    [IO.File]::Delete($tmp)
}
function Apply-Change([hashtable]$record,[scriptblock]$action) {
    $record.Status = 'Pending'
    [void]$script:manifest.Changes.Add($record)
    Save-State
    try {
        & $action
        $record.Status = 'Applied'
        $script:changed++
        Ui-Step ('  Вимкнено: ' + $record.Label)
    } catch {
        $record.Status = 'Pending'  # Pending also restored if action partly completed.
        $script:errors++
        Ui-Step ('  Не вдалося: ' + $record.Label + ' (' + $_.Exception.Message + ')')
    }
    Save-State
    Ui-Count
}

function Process-Registry {
    Ui-Step '1/3  Реєстр автозавантаження'
    $locations = @(
        @{Hive='LocalMachine';View='Registry64';Label='HKLM/64'},
        @{Hive='LocalMachine';View='Registry32';Label='HKLM/32'}
    )
    if ($sameUser) { $locations += @{Hive='CurrentUser';View='Default';Label='HKCU'} }
    $subkey = 'Software\Microsoft\Windows\CurrentVersion\Run'
    foreach ($loc in $locations) {
        try {
            $view = [Microsoft.Win32.RegistryView]([Enum]::Parse([Microsoft.Win32.RegistryView],$loc.View))
            if (-not [Environment]::Is64BitOperatingSystem -and $loc.View -eq 'Registry64') { continue }
            $hive = [Microsoft.Win32.RegistryHive]([Enum]::Parse([Microsoft.Win32.RegistryHive],$loc.Hive))
            $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
            $key = $root.OpenSubKey($subkey,$true)
            if ($null -eq $key) { $root.Close(); continue }
            foreach ($name in @($key.GetValueNames())) {
                if ([string]::IsNullOrEmpty($name)) { continue }
                try {
                    $kind = $key.GetValueKind($name).ToString()
                    if ($kind -notin @('String','ExpandString')) { $script:kept++; continue }
                    $cmd = [string]$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    $app = Get-Identity $cmd $name
                    if (-not $app) { $script:kept++; continue }
                    $rec = @{Category='Registry';Hive=$loc.Hive;View=$loc.View;SubKey=$subkey;EntryName=$name;Data=$cmd;Kind=$kind;Label="$app ($name)"}
                    Apply-Change $rec { $key.DeleteValue($name,$false) }
                } catch { $script:errors++; Ui-Step ('  Помилка запису реєстру: ' + $_.Exception.Message) }
                [Windows.Forms.Application]::DoEvents()
            }
            $key.Close(); $root.Close()
        } catch { $script:errors++; Ui-Step ('  Помилка читання реєстру: ' + $_.Exception.Message) }
    }
    Ui-Count
}

function Process-StartupFolders {
    Ui-Step '2/3  Папки автозавантаження'
    $folders = @([Environment]::GetFolderPath('CommonStartup'))
    if ($sameUser) { $folders += [Environment]::GetFolderPath('Startup') }
    foreach ($dir in ($folders | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            if ($file.Extension.ToLowerInvariant() -ne '.lnk') { $script:kept++; continue }
            try {
                $sh = New-Object -ComObject WScript.Shell
                $shortcut = $sh.CreateShortcut($file.FullName)
                $command = ([string]$shortcut.TargetPath) + ' ' + ([string]$shortcut.Arguments)
                $app = Get-Identity $command $file.Name
                [Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null
                if (-not $app) { $script:kept++; continue }
                $safeName = [Guid]::NewGuid().ToString('N') + '.lnk'
                $to = Join-Path (Join-Path $script:runDir 'Links') $safeName
                $rec = @{Category='Shortcut';Original=$file.FullName;Saved=$to;Label="$app ($($file.Name))"}
                Apply-Change $rec { Move-Item -LiteralPath $file.FullName -Destination $to -ErrorAction Stop }
            } catch { $script:errors++; Ui-Step ('  Помилка ярлика: ' + $_.Exception.Message) }
            [Windows.Forms.Application]::DoEvents()
        }
    }
    Ui-Count
}

function Process-TasksAndServices {
    Ui-Step '3/3  Фонові завдання й обережна перевірка служб'
    try {
        Import-Module ScheduledTasks -ErrorAction Stop
        foreach ($task in @(Get-ScheduledTask -ErrorAction Stop)) {
            try {
                if ($task.State.ToString() -eq 'Disabled' -or $task.TaskPath -like '\Microsoft\*') { continue }
                $startupTrigger = $false
                $hasOtherTrigger = $false
                foreach ($t in $task.Triggers) {
                    if ($null -ne $t -and $t.CimClass.CimClassName -match '(?i)(Logon|Boot)Trigger') {
                        $startupTrigger = $true
                    } else {
                        $hasOtherTrigger = $true
                    }
                }
                # Never disable a task that also runs on a maintenance schedule.
                if (-not $startupTrigger -or $hasOtherTrigger) { continue }
                $apps = New-Object System.Collections.Generic.List[string]
                foreach ($a in $task.Actions) {
                    $app = Get-Identity (([string]$a.Execute)+' '+([string]$a.Arguments)) $task.TaskName
                    if ($app) { $apps.Add($app) }
                }
                if ($apps.Count -eq 0 -or $apps.Count -ne @($task.Actions).Count) { $script:kept++; continue }
                $tp = [string]$task.TaskPath; $tn = [string]$task.TaskName
                $rec = @{Category='Task';TaskPath=$tp;TaskName=$tn;Label="$($apps[0]) ($tn)"}
                Apply-Change $rec { Disable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null }
            } catch { $script:errors++; Ui-Step ('  Помилка завдання: ' + $_.Exception.Message) }
            [Windows.Forms.Application]::DoEvents()
        }
    } catch { $script:errors++; Ui-Step ('  Планувальник недоступний: ' + $_.Exception.Message) }

    # Only known UPDATER-only emulator services. Never touch virtualization/driver
    # services (e.g. BstHdAndroidSvc), Windows Update, security, hardware or VPN.
    try {
        foreach ($svc in @(Get-CimInstance Win32_Service -Filter "StartMode='Auto'" -ErrorAction Stop)) {
            $name = [string]$svc.Name
            if ($name -notin @('BstHdUpdaterSvc','BlueStacksUpdaterService','NoxUpdaterSvc')) { continue }
            $path = [string]$svc.PathName
            if ($path -notmatch '(?i)(bluestacks|nox)' -or $path -notmatch '(?i)updat') { $script:kept++; continue }
            # Do not change delayed-auto start services: preserving that setting
            # requires additional state tracking, so err on the side of safety.
            $delay = Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $name) -Name DelayedAutoStart -ErrorAction SilentlyContinue
            if ($delay -and $delay.DelayedAutoStart -eq 1) { $script:kept++; continue }
            $rec = @{Category='Service';Name=$name;Previous='Automatic';Label="Служба оновлення емулятора: $name"}
            Apply-Change $rec { Set-Service -Name $name -StartupType Manual -ErrorAction Stop }
        }
    } catch { $script:errors++; Ui-Step ('  Служби недоступні: ' + $_.Exception.Message) }
    Ui-Count
}

function Restore-State {
    Ui-Step 'Шукаємо останню резервну копію...'
    if (-not (Test-Path -LiteralPath $base)) { Ui-Step 'Резервних копій немає.'; return }
    $found = $null
    foreach ($folder in @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name -Descending)) {
        $file = Join-Path $folder.FullName 'changes.json'
        if (-not (Test-Path -LiteralPath $file)) { continue }
        try {
            $candidate = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($candidate.Computer -eq $env:COMPUTERNAME -and $candidate.UserSid -eq $OriginSid -and -not $candidate.Restored -and @($candidate.Changes).Count -gt 0) {
                $found = $candidate; $script:manifestFile = $file; break
            }
        } catch { continue }
    }
    if (-not $found) { Ui-Step 'Немає змін, які потрібно відновлювати.'; return }
    $script:manifest = $found
    Ui-Step ('Копія: ' + $script:manifestFile)
    $answer = [Windows.Forms.MessageBox]::Show('Повернути попереднє автозавантаження з останньої копії?', 'no_problem_man', 'YesNo', 'Question')
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Ui-Step 'Відновлення скасовано.'; return }
    $changes = @($script:manifest.Changes)
    [array]::Reverse($changes)
    foreach ($c in $changes) {
        if ($c.Status -notin @('Applied','Pending')) { continue }
        try {
            switch ($c.Category) {
                'Registry' {
                    $hive = [Microsoft.Win32.RegistryHive]([Enum]::Parse([Microsoft.Win32.RegistryHive],[string]$c.Hive))
                    $view = [Microsoft.Win32.RegistryView]([Enum]::Parse([Microsoft.Win32.RegistryView],[string]$c.View))
                    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                    $key = $root.OpenSubKey([string]$c.SubKey,$true)
                    if (-not $key) { throw 'Гілку реєстру не знайдено' }
                    if ($key.GetValueNames() -notcontains [string]$c.EntryName) {
                        $kind = [Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$c.Kind))
                        $key.SetValue([string]$c.EntryName,[string]$c.Data,$kind)
                    }
                    $key.Close(); $root.Close()
                }
                'Shortcut' {
                    if ((Test-Path -LiteralPath ([string]$c.Saved)) -and -not (Test-Path -LiteralPath ([string]$c.Original))) {
                        Move-Item -LiteralPath ([string]$c.Saved) -Destination ([string]$c.Original) -ErrorAction Stop
                    }
                }
                'Task' {
                    $task = Get-ScheduledTask -TaskPath ([string]$c.TaskPath) -TaskName ([string]$c.TaskName) -ErrorAction Stop
                    if ($task.State.ToString() -eq 'Disabled') { Enable-ScheduledTask -TaskPath ([string]$c.TaskPath) -TaskName ([string]$c.TaskName) -ErrorAction Stop | Out-Null }
                }
                'Service' {
                    $svc = Get-Service -Name ([string]$c.Name) -ErrorAction Stop
                    if ($svc.StartType.ToString() -eq 'Manual') { Set-Service -Name ([string]$c.Name) -StartupType Automatic -ErrorAction Stop }
                }
            }
            $c.Status = 'Restored'; $script:changed++
            Ui-Step ('  Повернено: ' + [string]$c.Label)
        } catch { $script:errors++; Ui-Step ('  Не вдалося повернути: ' + [string]$c.Label + ': ' + $_.Exception.Message) }
        Ui-Count
    }
    # Write object with possibly updated changes; preserve retry for partial failures.
    $script:manifest.Restored = ($script:errors -eq 0)
    Save-State
}

function Main-Work {
    try {
        if ($Restore) { Restore-State }
        else {
            if (-not $sameUser) {
                Ui-Step 'Вхід під іншим адміністратором: персональні записи не чіпаємо.'
            }
            [void](New-Item -ItemType Directory -Path $base -Force -ErrorAction Stop)
            $id = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + ([Guid]::NewGuid().ToString('N').Substring(0,6))
            $script:runDir = Join-Path $base $id
            [void](New-Item -ItemType Directory -Path (Join-Path $script:runDir 'Links') -Force -ErrorAction Stop)
            $script:manifestFile = Join-Path $script:runDir 'changes.json'
            $script:manifest = @{Version=1; Created=(Get-Date).ToString('s'); Computer=$env:COMPUTERNAME; UserSid=$OriginSid; Restored=$false; Changes=(New-Object System.Collections.ArrayList)}
            Save-State
            Process-Registry
            Process-StartupFolders
            Process-TasksAndServices
        }
        Ui-Step ('Готово. Змінено: ' + $script:changed + '; помилок: ' + $script:errors)
    } catch { $script:errors++; Ui-Step ('Помилка: ' + $_.Exception.Message) }
    finally {
        $script:busy = $false
        $progress.Style = 'Blocks'; $progress.Value = 100
        if (-not $Restore) {
            $runButton.Enabled = $true; $restoreButton.Enabled = $true
            $title.Text = 'no_problem_man'
            $stage.Text = 'Готово. Зміни діятимуть після нового входу.'
        } else {
            $title.Text = 'no_problem_man'
            $stage.Text = 'Відновлення завершено.'
        }
        $runButton.Enabled = $true; $restoreButton.Enabled = $true
        Ui-Count
    }
}
$runButton.Add_Click({
    if ($script:busy) { return }
    $script:busy = $true
    $script:changed = 0; $script:kept = 0; $script:errors = 0
    $script:Restore = $false
    $runButton.Enabled = $false; $restoreButton.Enabled = $false
    $logBox.Clear(); Ui-Count
    $progress.Value = 0
    $progress.Style = 'Marquee'; $progress.MarqueeAnimationSpeed = 22
    Main-Work
})
$restoreButton.Add_Click({
    if ($script:busy) { return }
    $script:busy = $true
    $script:changed = 0; $script:kept = 0; $script:errors = 0
    $script:Restore = $true
    $runButton.Enabled = $false; $restoreButton.Enabled = $false
    $logBox.Clear(); Ui-Count
    $progress.Value = 0
    $progress.Style = 'Marquee'; $progress.MarqueeAnimationSpeed = 22
    Main-Work
})
[void][Windows.Forms.Application]::Run($form)
