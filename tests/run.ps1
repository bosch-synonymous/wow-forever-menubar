param(
    [string[]] $Roots,
    [string] $LupaPath,
    [string] $HoardRoot,
    [string] $PythonExecutable,
    [switch] $SyntaxOnly
)

$ErrorActionPreference = 'Stop'
if (-not $PythonExecutable) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*\WindowsApps\*' } |
        Select-Object -First 1
    if ($pythonCommand) {
        $PythonExecutable = $pythonCommand.Source
    }
    else {
        $pythonInstall = Get-ChildItem -LiteralPath $env:ProgramFiles -Directory -Filter 'Python*' |
            Sort-Object Name -Descending |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'python.exe') } |
            Select-Object -First 1
        if ($pythonInstall) {
            $PythonExecutable = Join-Path $pythonInstall.FullName 'python.exe'
        }
        else {
            throw 'Python was not found. Supply -PythonExecutable with the path to a Python 3 interpreter.'
        }
    }
}

$runnerArguments = @((Join-Path $PSScriptRoot 'run_lua.py'))
if ($Roots) { $runnerArguments += '--roots'; $runnerArguments += $Roots }
if ($LupaPath) { $runnerArguments += @('--lupa-path', $LupaPath) }
if ($HoardRoot) { $runnerArguments += @('--hoard-root', $HoardRoot) }
if ($SyntaxOnly) { $runnerArguments += '--syntax-only' }
& $PythonExecutable @runnerArguments
exit $LASTEXITCODE
