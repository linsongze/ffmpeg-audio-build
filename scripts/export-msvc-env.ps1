param(
  [Parameter(Mandatory = $true)]
  [string]$TargetArch
)

$ErrorActionPreference = 'Stop'

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
  throw "vswhere.exe not found at $vswhere"
}

$vsPath = & $vswhere -latest -products * -property installationPath
if (-not $vsPath) {
  throw 'Visual Studio installation not found'
}

$vcvarsall = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat'
if (-not (Test-Path $vcvarsall)) {
  throw "vcvarsall.bat not found at $vcvarsall"
}

$envDump = cmd /c "`"$vcvarsall`" $TargetArch >nul && set"
foreach ($line in $envDump) {
  if ($line -match '^(.*?)=(.*)$') {
    $name = $matches[1]
    $value = $matches[2]
    Add-Content $env:GITHUB_ENV "$name<<__EOF__"
    Add-Content $env:GITHUB_ENV $value
    Add-Content $env:GITHUB_ENV "__EOF__"
  }
}
