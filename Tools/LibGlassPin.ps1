<#
    LibGlassPin.ps1 - Is the LibGlass checkout the one .pkgmeta pins?
    Dot-sourced by Tools\deploy.ps1 and tests\run.ps1, so both judge the same way.

    The pin is the commit: or tag: of the Libs/LibGlass-1.0 entry under
    externals:, read as tests/fetch_libglass.sh (CI) reads it, so another
    external can't be mistaken for it. A checkout elsewhere is legitimate
    (trying a library change before a pin bump), but then local tests and
    in-game checks exercise a library the release won't ship: say so.
#>

function Get-LibGlassPin([string]$RepoRoot) {
    $inExternals = $false; $inLib = $false
    foreach ($line in Get-Content -LiteralPath (Join-Path $RepoRoot ".pkgmeta")) {
        if ($line -match '^externals:') { $inExternals = $true; continue }
        if ($inExternals -and $line -match '^[^ #]') { $inExternals = $false }
        if (-not $inExternals) { continue }
        if ($line -match '^  Libs/LibGlass-1\.0:') { $inLib = $true; continue }
        if ($inLib -and $line -match '^  [^ ]') { $inLib = $false }
        if ($inLib -and $line -match '^\s+(commit|tag):\s*(\S+)\s*$') { return $Matches[2] }
    }
    return $null
}

# A warning line, or $null when the checkout is clean and at the pin.
function Test-LibGlassPin([string]$RepoRoot, [string]$LibGlass) {
    $pin = Get-LibGlassPin $RepoRoot
    if (-not $pin) { return "no LibGlass pin found in .pkgmeta" }
    $want = $null; $head = $null; $dirty = $null
    try {
        $want = git -C $LibGlass rev-parse --verify --quiet "$pin^{commit}" 2>$null
        $head = git -C $LibGlass rev-parse HEAD 2>$null
        $dirty = git -C $LibGlass status --porcelain 2>$null
    } catch { }
    if (-not $want -or $want -ne $head -or $dirty) {
        return "LibGlass at $LibGlass is not the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }): this tests a library the release won't ship"
    }
    return $null
}
