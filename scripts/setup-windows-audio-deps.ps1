param(
  [Parameter(Mandatory = $true)]
  [string]$VcpkgRoot,

  [Parameter(Mandatory = $true)]
  [string]$VcpkgTriplet
)

$ErrorActionPreference = 'Stop'

function Ensure-LibAlias {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Alias
  )

  if (-not (Test-Path $Source)) {
    throw "required library not found: $Source"
  }

  Copy-Item -Force $Source $Alias
}

function New-CombinedStaticLib {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Output,

    [Parameter(Mandatory = $true)]
    [string[]]$Inputs
  )

  foreach ($inputLib in $Inputs) {
    if (-not (Test-Path $inputLib)) {
      throw "required library not found: $inputLib"
    }
  }

  & lib.exe /nologo /OUT:$Output $Inputs
}

if (-not (Get-Command make.exe -ErrorAction SilentlyContinue)) {
  choco install make -y --no-progress
}

if (-not (Test-Path $VcpkgRoot)) {
  git clone --depth 1 https://github.com/microsoft/vcpkg.git $VcpkgRoot
}

& (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat') -disableMetrics

& (Join-Path $VcpkgRoot 'vcpkg.exe') install `
  --clean-after-build `
  "libogg:$VcpkgTriplet" `
  "libvorbis:$VcpkgTriplet" `
  "opus:$VcpkgTriplet" `
  "mp3lame:$VcpkgTriplet" `
  "pkgconf:$VcpkgTriplet"

$installedDir = Join-Path $VcpkgRoot "installed\$VcpkgTriplet"
$libDir = Join-Path $installedDir 'lib'
$mp3LameStaticLib = Join-Path $libDir 'libmp3lame-static.lib'
$mp3LameCompatLib = Join-Path $libDir 'mp3lame.lib'

$mpghipStaticLib = Join-Path $libDir 'libmpghip-static.lib'
if (Test-Path $mpghipStaticLib) {
  New-CombinedStaticLib `
    -Output $mp3LameCompatLib `
    -Inputs @($mp3LameStaticLib, $mpghipStaticLib)

  Ensure-LibAlias `
    -Source $mpghipStaticLib `
    -Alias (Join-Path $libDir 'mpghip.lib')
} else {
  Ensure-LibAlias `
    -Source $mp3LameStaticLib `
    -Alias $mp3LameCompatLib
}

$pkgconfCandidates = @(
  (Join-Path $installedDir 'tools\pkgconf\pkgconf.exe'),
  (Join-Path $installedDir 'tools\pkgconf\pkg-config.exe'),
  (Join-Path $installedDir 'tools\pkgconf\bin\pkgconf.exe'),
  (Join-Path $installedDir 'tools\pkgconf\bin\pkg-config.exe')
)

$pkgconfExe = $pkgconfCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $pkgconfExe) {
  throw "pkgconf executable not found under $installedDir"
}

Add-Content $env:GITHUB_ENV "WINDOWS_VCPKG_INSTALLED_DIR=$installedDir"
Add-Content $env:GITHUB_ENV "PKGCONF_EXE=$pkgconfExe"
