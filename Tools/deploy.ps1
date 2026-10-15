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

    The probes under Tools\<X>Probe are ForeverProbe modules: -Probe deploys
    them too, -ProbeOnly only them. Either deploys the ForeverProbe checkout
    first ($env:FOREVERPROBE, else ..\ForeverProbe), since a probe without its
    host doesn't load. Players never get a probe: it isn't packaged.

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -Probe        # ...and the probes (RXPProbe)
        pwsh Tools/deploy.ps1 -ProbeOnly    # just the probes
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns",
    [switch]$Probe,
    [switch]$ProbeOnly
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }
# One canonical form (absolute, backslashes): the stale-file sweep compares
# paths as strings, and a relative or forward-slash path would match nothing
# and delete every file just copied.
$AddOnsPath = (Resolve-Path -LiteralPath $AddOnsPath).ProviderPath

# The probes: the ForeverProbe host first (a probe has ## Dependencies:
# ForeverProbe, so without it the client loads none), then each Tools\<X>Probe
# as AddOns\<X>Probe, its TOC and Lua only.
$ForeverProbe = if ($env:FOREVERPROBE) { $env:FOREVERPROBE } else { Join-Path (Split-Path -Parent $RepoRoot) "ForeverProbe" }
function Deploy-Probes {
    if (-not (Test-Path -LiteralPath (Join-Path $ForeverProbe "Tools\deploy.ps1"))) {
        Write-Error "ForeverProbe checkout not found at $ForeverProbe (clone github.com/Spotnick2/ForeverProbe there, or set `$env:FOREVERPROBE)"
        exit 1
    }
    & pwsh -NoProfile -File (Join-Path $ForeverProbe "Tools\deploy.ps1") -AddOnsPath $AddOnsPath
    if ($LASTEXITCODE -ne 0) { Write-Error "ForeverProbe deploy refused; the probes were not touched"; exit 1 }
    foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Tools") -Directory -Filter "*Probe") {
        $dest = Join-Path $AddOnsPath $dir.Name
        Write-Host "Deploying $($dir.Name) -> $dest" -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object { $_.Extension -in ".toc", ".lua" } |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
                Write-Host "  $($_.Name)"
            }
    }
}
if ($ProbeOnly) {
    Deploy-Probes
    Write-Host ""
    Write-Host "In game: /reload, then /fp steps rxp arrow (or /fp rxp)" -ForegroundColor Green
    exit 0
}

$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
if (-not (Test-Path -LiteralPath (Join-Path $LibGlass "Tools\deploy.ps1"))) {
    Write-Error "LibGlass checkout not found at $LibGlass (clone github.com/Spotnick2/LibGlass there, or set `$env:LIBGLASS)"
    exit 1
}

# The pin check, shared with tests\run.ps1.
. (Join-Path $PSScriptRoot "LibGlassPin.ps1")

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
$warning = Test-LibGlassPin $RepoRoot $LibGlass
if ($warning) { Write-Host "  WARNING: $warning" -ForegroundColor Yellow }
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

if ($Probe) { Deploy-Probes }

Write-Host ""
Write-Host "Changed files, or a brand-new addon folder: /reload is enough." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /gpanel" -ForegroundColor Green
