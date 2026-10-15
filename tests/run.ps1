<#
    run.ps1 - Syntax-check the addon and its plugins, and run every tests\test_*.lua under Lua 5.1.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Lua)) { Write-Error "Lua 5.1 not found at $Lua (pass -Lua <path>)"; exit 1 }
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    # The TOC is the list, so a new file cannot go unchecked. Every plugin's TOC too.
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    $tocs = @("GlassPanel.toc") + (Get-ChildItem "Plugins" -Recurse -Filter "*.toc" -ErrorAction SilentlyContinue |
        ForEach-Object { Resolve-Path -Relative $_.FullName })
    # The probes (Tools\<X>Probe, ForeverProbe modules: never packaged) are checked too.
    $tocs += Get-ChildItem "Tools" -Recurse -Filter "*.toc" -ErrorAction SilentlyContinue |
        ForEach-Object { Resolve-Path -Relative $_.FullName }
    $luaFiles = foreach ($toc in $tocs) {
        $dir = Split-Path -Parent $toc
        Get-Content $toc | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" } |
            ForEach-Object { if ($dir) { Join-Path $dir $_ } else { $_ } }
    }
    if (-not (Test-Path $luac)) {
        Write-Host "luac -p SKIPPED: no luac.exe beside $Lua - syntax was NOT checked" -ForegroundColor Yellow
    } else {
        & $luac -p @luaFiles
        if ($LASTEXITCODE -ne 0) { Write-Host "luac -p FAILED" -ForegroundColor Red; exit 1 }
        Remove-Item -LiteralPath "luac.out" -ErrorAction SilentlyContinue
        Write-Host "luac -p: ok ($($luaFiles.Count) files from $($tocs.Count) TOC(s))" -ForegroundColor DarkGray
    }

    # The tests load the LibGlass checkout as it is ($env:LIBGLASS, default
    # ..\LibGlass); CI loads the .pkgmeta pin. (A missing checkout fails in
    # the tests themselves, loudly.)
    . (Join-Path $RepoRoot "Tools\LibGlassPin.ps1")
    $libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
    if (Test-Path -LiteralPath $libGlass) {
        $warning = Test-LibGlassPin $RepoRoot $libGlass
        if ($warning) { Write-Host "WARNING: $warning (CI tests the pin)" -ForegroundColor Yellow }
        else { Write-Host "LibGlass: $libGlass at the pin ($(Get-LibGlassPin $RepoRoot))" -ForegroundColor DarkGray }
    }

    # Without the API dump the tests accept every event name and skip the
    # method check, and still pass: say so locally (CI has no dump, by design).
    $dump = & $Lua -e "dofile('tests/wow_stubs.lua') io.write(WoW.dumpAvailable and '' or WoW.DUMP)"
    if ($dump -and -not $env:CI) {
        Write-Host "WARNING: no API dump at $dump (set GLASSPANEL_API_DUMP): event names and widget methods are NOT checked" -ForegroundColor Yellow
    }

    $failed = 0
    Get-ChildItem (Join-Path $PSScriptRoot "test_*.lua") | Sort-Object Name | ForEach-Object {
        Write-Host "-- $($_.Name) " -NoNewline -ForegroundColor Cyan
        & $Lua $_.FullName
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    if ($failed -gt 0) { Write-Host "$failed test file(s) FAILED" -ForegroundColor Red; exit 1 }
    Write-Host "All test files passed." -ForegroundColor Green
}
finally { Pop-Location }
