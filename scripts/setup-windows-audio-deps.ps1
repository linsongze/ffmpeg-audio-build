param(
  [Parameter(Mandatory = $true)]
  [string]$VcpkgRoot,

  [Parameter(Mandatory = $true)]
  [string]$VcpkgTriplet
)

$ErrorActionPreference = 'Stop'

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
