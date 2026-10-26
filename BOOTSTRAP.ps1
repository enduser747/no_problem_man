param(
    [string]$OriginSid = '',
    [switch]$Elevated
)
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Windows.Forms
    if ([string]::IsNullOrWhiteSpace($OriginSid)) {
        $OriginSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }
    if (-not $Elevated) {
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $args = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}" -Elevated -OriginSid "{1}"' -f $PSCommandPath,$OriginSid
        Start-Process -FilePath $exe -ArgumentList $args -Verb RunAs -ErrorAction Stop
        exit
    }
    $core = Join-Path $PSScriptRoot 'no_problem_man.ps1'
    if (-not (Test-Path -LiteralPath $core -PathType Leaf)) { throw 'Не знайдено no_problem_man.ps1' }
    # Parsing happens inside try: PowerShell errors cannot disappear silently.
    & $core -OriginSid $OriginSid
}
catch {
    $details = $_ | Out-String
    try {
        $log = Join-Path $env:TEMP 'no_problem_man_startup_error.txt'
        [IO.File]::WriteAllText($log,$details,[Text.Encoding]::UTF8)
    } catch { $log = '(cannot save diagnostic log)' }
    try {
        [Windows.Forms.MessageBox]::Show(('Помилка запуску no_problem_man:' + "`r`n`r`n" + $details.Substring(0,[Math]::Min(1200,$details.Length)) + "`r`n`r`nLog: $log"),'no_problem_man','OK','Error') | Out-Null
    } catch {}
    exit 1
}
