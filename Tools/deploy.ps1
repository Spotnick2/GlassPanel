<#
    deploy.ps1 - Copy GlassPanel [Core] and its [plugins] into the Forever AddOns folder.

    The core always deploys as AddOns\GlassPanel, whatever the repo folder is
    called: the folder name is the addon name. Each Plugins\<Name>\ becomes its
    own top-level AddOns\<toc name> (e.g. AddOns\GlassPanelXP): the client only
    discovers addons as top-level folders. The core's stale-file sweep also
    removes the old Blocks\*.lua left over from before the plugins split (#7).

    The glass material is the embedded LibGlass-1.0, in the core only. The
    packager fetches it into Libs\LibGlass-1.0 (.pkgmeta externals); for a dev
    copy this script hands that job to the LibGlass checkout's own deploy.ps1,
    which checks the checkout, copies only the shipped files and prints its
    commit. The checkout is $env:LIBGLASS, else ..\LibGlass.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }
# One canonical form (absolute, backslashes): the stale-file sweep compares
# paths as strings, and a relative or forward-slash path would match nothing
# and delete every file just copied.
$AddOnsPath = (Resolve-Path -LiteralPath $AddOnsPath).ProviderPath

$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
if (-not (Test-Path -LiteralPath (Join-Path $LibGlass "Tools\deploy.ps1"))) {
    Write-Error "LibGlass checkout not found at $LibGlass (clone github.com/Spotnick2/LibGlass there, or set `$env:LIBGLASS)"
    exit 1
}

# The commit or tag .pkgmeta pins, which is what the packager will ship. A dev
# checkout elsewhere is legitimate (trying a library change before a pin bump),
# but an in-game check then tests something the release won't carry: say so.
function Test-LibGlassPin {
    $pin = (Get-Content -LiteralPath (Join-Path $RepoRoot ".pkgmeta")) |
        Where-Object { $_ -match '^\s+(commit|tag):\s*(\S+)\s*$' } | ForEach-Object { $Matches[2] } | Select-Object -First 1
    if (-not $pin) { Write-Host "  (no LibGlass pin found in .pkgmeta)" -ForegroundColor Yellow; return }
    $want = $null; $head = $null; $dirty = $null
    try {
        $want = (git -C $LibGlass rev-parse --verify --quiet "$pin^{commit}" 2>$null)
        $head = (git -C $LibGlass rev-parse HEAD 2>$null)
        $dirty = (git -C $LibGlass status --porcelain 2>$null)
    } catch { }
    if (-not $want -or $want -ne $head -or $dirty) {
        Write-Host "  WARNING: the LibGlass checkout is not at the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }):" -ForegroundColor Yellow
        Write-Host "  this deploy tests a library the release won't ship." -ForegroundColor Yellow
    }
}

# Copy the files a TOC lists (plus the TOC) from $src to $dest, rewriting the
# version token, and remove Lua files the TOC no longer lists. Libs\ belongs
# to the library's own deploy: neither copied nor swept here.
function Deploy-Toc([string]$src, [string]$tocName, [string]$dest) {
    Write-Host "Deploying $tocName -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $toc = Join-Path $src $tocName
    (Get-Content -LiteralPath $toc -Raw) -replace '## Version: @project-version@', '## Version: dev' |
        Set-Content -LiteralPath (Join-Path $dest $tocName) -NoNewline
    $listed = Get-Content -LiteralPath $toc | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notmatch "^#" -and $_ -match "[.](lua|xml)$" -and $_ -notmatch "^Libs\\" }
    foreach ($f in $listed) {
        $target = Join-Path $dest $f
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $src $f) -Destination $target -Force
        Write-Host "  $f"
    }
    # A Lua file removed from the TOC must not linger where the client finds it.
    $keep = $listed | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $dest $_)).ToLower() }
    $libs = (Join-Path $dest "Libs\").ToLower()
    Get-ChildItem -LiteralPath $dest -Recurse -File -Filter "*.lua" |
        Where-Object { -not $_.FullName.ToLower().StartsWith($libs) -and $keep -notcontains $_.FullName.ToLower() } |
        ForEach-Object {
            Write-Host "  removing stale $($_.Name)" -ForegroundColor DarkYellow
            Remove-Item -LiteralPath $_.FullName -Force
        }
}

$core = Join-Path $AddOnsPath "GlassPanel"
Test-LibGlassPin
# The library first: its deploy checks the checkout and may refuse, and a
# refusal must leave the deployed addon as it was (a new TOC naming a library
# that never arrived loads no bar at all).
& pwsh -NoProfile -File (Join-Path $LibGlass "Tools\deploy.ps1") -Addon GlassPanel -AddOnsPath $AddOnsPath
if ($LASTEXITCODE -ne 0) { Write-Error "LibGlass deploy refused; GlassPanel was not touched"; exit 1 }
Deploy-Toc $RepoRoot "GlassPanel.toc" $core
# The textures now ship inside Libs\LibGlass-1.0\Media; the old folder is dead weight.
$oldMedia = Join-Path $core "Media"
if (Test-Path -LiteralPath $oldMedia) {
    Write-Host "  removing stale Media\ (textures now come from LibGlass)" -ForegroundColor DarkYellow
    Remove-Item -LiteralPath $oldMedia -Recurse -Force
}

$pluginRoot = Join-Path $RepoRoot "Plugins"
if (Test-Path $pluginRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $pluginRoot -Directory) {
        $toc = Get-ChildItem -LiteralPath $dir.FullName -Filter "*.toc" | Select-Object -First 1
        if (-not $toc) { Write-Host "  skipping Plugins\$($dir.Name): no .toc" -ForegroundColor DarkYellow; continue }
        Deploy-Toc $dir.FullName $toc.Name (Join-Path $AddOnsPath $toc.BaseName)
    }
}

Write-Host ""
Write-Host "Changed files: /reload is enough. A brand-new addon folder needs a client restart." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /gpanel" -ForegroundColor Green
