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
    # The TOC is the list, so a new file cannot go unchecked. Plugins' TOCs too.
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    $tocs = @("GlassPanel.toc") + (Get-ChildItem "Plugins" -Recurse -Filter "*.toc" -ErrorAction SilentlyContinue |
        ForEach-Object { Resolve-Path -Relative $_.FullName })
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
