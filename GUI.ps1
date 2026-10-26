# no_problem_man 1.0 - Windows graphical interface
# Requires Windows PowerShell 5.1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:ua = (
    [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'uk'
)

function L([string]$uk, [string]$en) {
    if ($script:ua) { $uk } else { $en }
}

$script:core = Join-Path $PSScriptRoot 'no_problem_man.ps1'
$script:running = $false
$script:proc = $null
$script:outTask = $null
$script:errTask = $null
$script:outDone = $false
$script:errDone = $false
$script:disabled = '?'
$script:errors = '?'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'no_problem_man 1.0'
$form.Size = New-Object System.Drawing.Size(740, 430)
$form.MinimumSize = New-Object System.Drawing.Size(680, 390)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(247, 248, 250)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = L 'Оптимізація автозавантаження Windows' 'Windows startup cleanup'
$title.Font = New-Object System.Drawing.Font(
    'Segoe UI', 15, [System.Drawing.FontStyle]::Bold
)
$title.SetBounds(22, 16, 680, 36)
$form.Controls.Add($title)

$desc = New-Object System.Windows.Forms.Label
$desc.Text = L 'Відомі необов’язкові програми. Системні служби не змінюємо.' 'Known optional apps only. System services are not changed.'
$desc.SetBounds(24, 60, 680, 35)
$form.Controls.Add($desc)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.SetBounds(24, 106, 674, 18)
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 28
$form.Controls.Add($progress)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.SetBounds(24, 140, 674, 165)
$log.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($log)

$status = New-Object System.Windows.Forms.Label
$status.Text = L 'Підготовка...' 'Preparing...'
$status.SetBounds(24, 320, 510, 42)
$status.Anchor = 'Bottom,Left'
$form.Controls.Add($status)

$close = New-Object System.Windows.Forms.Button
$close.Text = L 'Закрити' 'Close'
$close.SetBounds(586, 326, 112, 34)
$close.Anchor = 'Bottom,Right'
$close.Enabled = $false
$close.Add_Click({ $form.Close() })
$form.Controls.Add($close)

function Show-Line([string]$line, [bool]$isError = $false) {
    if ($isError) {
        $line = 'ERROR: ' + $line
    }

    $log.AppendText($line + "`r`n")

    if ($line -match '^Startup entries disabled:\s*(\d+)') {
        $script:disabled = $matches[1]
    }

    if ($line -match '^Errors:\s*(\d+)') {
        $script:errors = $matches[1]
    }
}

function Finish-Run {
    $timer.Stop()
    $script:running = $false
    $progress.Style = 'Blocks'
    $progress.Value = 100
    $close.Enabled = $true

    $exitCode = $script:proc.ExitCode

    if ($exitCode -ne 0) {
        $status.Text = (
            L 'Помилка виконання. Код: ' 'Execution error. Exit code: '
        ) + $exitCode
    }
    else {
        $status.Text = (
            L 'Вимкнено: {0}      Помилок: {1}' 'Disabled: {0}      Errors: {1}'
        ) -f $script:disabled, $script:errors
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120

$timer.Add_Tick({
    try {
        for ($i = 0; $i -lt 80; $i++) {
            $activity = $false

            if (-not $script:outDone -and $script:outTask.IsCompleted) {
                $line = $script:outTask.GetAwaiter().GetResult()

                if ($null -eq $line) {
                    $script:outDone = $true
                }
                else {
                    Show-Line $line
                    $script:outTask = $script:proc.StandardOutput.ReadLineAsync()
                }

                $activity = $true
            }

            if (-not $script:errDone -and $script:errTask.IsCompleted) {
                $line = $script:errTask.GetAwaiter().GetResult()

                if ($null -eq $line) {
                    $script:errDone = $true
                }
                else {
                    Show-Line $line $true
                    $script:errTask = $script:proc.StandardError.ReadLineAsync()
                }

                $activity = $true
            }

            if (-not $activity) {
                break
            }
        }

        if ($script:proc.HasExited -and
            $script:outDone -and
            $script:errDone) {
            Finish-Run
        }
    }
    catch {
        $timer.Stop()
        $script:running = $false
        $close.Enabled = $true
        $progress.Style = 'Blocks'

        Show-Line $_.Exception.Message $true
        $status.Text = L 'Помилка відображення журналу.' 'Log display error.'
    }
})

$form.Add_FormClosing({
    param($sender, $e)

    if ($script:running) {
        $e.Cancel = $true
    }
})

$form.Add_Shown({
    if (-not (Test-Path -LiteralPath $script:core -PathType Leaf)) {
        Show-Line (
            L 'Не знайдено no_problem_man.ps1 поряд із GUI.ps1.' 'Missing no_problem_man.ps1 next to GUI.ps1.'
        ) $true

        $progress.Style = 'Blocks'
        $status.Text = L 'Не запущено.' 'Not started.'
        $close.Enabled = $true
        return
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $PSHOME 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' +
            $script:core + '"'

        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true

        $script:proc = New-Object System.Diagnostics.Process
        $script:proc.StartInfo = $psi

        if (-not $script:proc.Start()) {
            throw 'PowerShell process did not start.'
        }

        $script:running = $true
        $status.Text = L 'Виконується оптимізація...' 'Cleaning startup entries...'

        $script:proc.StandardInput.WriteLine()
        $script:proc.StandardInput.Close()

        $script:outTask = $script:proc.StandardOutput.ReadLineAsync()
        $script:errTask = $script:proc.StandardError.ReadLineAsync()

        $timer.Start()
    }
    catch {
        $script:running = $false
        Show-Line $_.Exception.Message $true

        $progress.Style = 'Blocks'
        $status.Text = L 'Запуск не вдався.' 'Could not start.'
        $close.Enabled = $true
    }
})

[void][System.Windows.Forms.Application]::Run($form)
