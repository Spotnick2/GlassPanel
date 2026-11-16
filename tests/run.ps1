<#
    run.ps1 - Syntax-check the addon and its plugins, and run every tests\test_*.lua under Lua 5.1,
    through WowTestKit at the commit tests\kit.pin names (#134).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev        # against the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    # The core's TOC is the kit's -Toc; every plugin's TOC and the probes'
    # (Tools\<X>Probe, ForeverProbe modules: never packaged) are -Extra, so a
    # new file cannot go unchecked.
    $tocs = @(Get-ChildItem "Plugins" -Recurse -Filter "*.toc" -ErrorAction SilentlyContinue) +
            @(Get-ChildItem "Tools" -Recurse -Filter "*.toc" -ErrorAction SilentlyContinue)
    $extra = foreach ($toc in $tocs) {
        $dir = Split-Path -Parent (Resolve-Path -Relative $toc.FullName)
        Get-Content $toc.FullName | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" } |
            ForEach-Object { Join-Path $dir $_ }
    }

    # The tests load the library checkouts as they are ($env:LIBGLASS,
    # default ..\LibGlass; $env:LIBTAXITIME, default ..\LibTaxiTime); CI loads
    # the .pkgmeta pins. (A missing checkout fails in the tests themselves, loudly.)
    . (Join-Path $RepoRoot "Tools\LibPin.ps1")
    $libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
    if (Test-Path -LiteralPath $libGlass) {
        $warning = Test-LibPin $RepoRoot "LibGlass-1.0" $libGlass
        if ($warning) { Write-Host "WARNING: $warning (CI tests the pin)" -ForegroundColor Yellow }
        else { Write-Host "LibGlass: $libGlass at the pin ($(Get-LibPin $RepoRoot 'LibGlass-1.0'))" -ForegroundColor DarkGray }
    }
    $libTaxiTime = if ($env:LIBTAXITIME) { $env:LIBTAXITIME } else { Join-Path (Split-Path -Parent $RepoRoot) "LibTaxiTime" }
    if (Test-Path -LiteralPath $libTaxiTime) {
        $warning = Test-LibPin $RepoRoot "LibTaxiTime-1.0" $libTaxiTime
        if ($warning) { Write-Host "WARNING: $warning (CI tests the pin)" -ForegroundColor Yellow }
        else { Write-Host "LibTaxiTime: $libTaxiTime at the pin ($(Get-LibPin $RepoRoot 'LibTaxiTime-1.0'))" -ForegroundColor DarkGray }
    }

    . (Join-Path $PSScriptRoot "kit.ps1")
    $kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
    & (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassPanel.toc" -Extra $extra -Lua $Lua
    exit $LASTEXITCODE
}
finally { Pop-Location }
