<#
    deploy.ps1 - Copy GlassPanel [Core] and its [plugins] into the Forever AddOns folder.

    The core always deploys as AddOns\GlassPanel, whatever the repo folder is
    called: the folder name is the addon name, and Glass.MEDIA is built from it.
    Each Plugins\<Name>\ becomes its own top-level AddOns\<toc name> (e.g.
    AddOns\GlassPanelXP): the client only discovers addons as top-level folders.
    The core's stale-file sweep also removes the old Blocks\*.lua left over from
    before the plugins split (#7).

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

# Copy the files a TOC lists (plus the TOC) from $src to $dest, rewriting the
# version token, and remove Lua files the TOC no longer lists.
function Deploy-Toc([string]$src, [string]$tocName, [string]$dest) {
    Write-Host "Deploying $tocName -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $toc = Join-Path $src $tocName
    (Get-Content -LiteralPath $toc -Raw) -replace '## Version: @project-version@', '## Version: dev' |
        Set-Content -LiteralPath (Join-Path $dest $tocName) -NoNewline
    $listed = Get-Content -LiteralPath $toc | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notmatch "^#" -and $_ -match "[.](lua|xml)$" }
    foreach ($f in $listed) {
        $target = Join-Path $dest $f
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $src $f) -Destination $target -Force
        Write-Host "  $f"
    }
    # A Lua file removed from the TOC must not linger where the client finds it.
    $keep = $listed | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $dest $_)).ToLower() }
    Get-ChildItem -LiteralPath $dest -Recurse -File -Filter "*.lua" |
        Where-Object { $keep -notcontains $_.FullName.ToLower() } | ForEach-Object {
            Write-Host "  removing stale $($_.Name)" -ForegroundColor DarkYellow
            Remove-Item -LiteralPath $_.FullName -Force
        }
}

$core = Join-Path $AddOnsPath "GlassPanel"
Deploy-Toc $RepoRoot "GlassPanel.toc" $core
$media = Join-Path $core "Media"
New-Item -ItemType Directory -Force -Path $media | Out-Null
$textures = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Media") -Filter "*.tga"
foreach ($t in $textures) { Copy-Item -LiteralPath $t.FullName -Destination (Join-Path $media $t.Name) -Force }
Write-Host "  Media\  ($($textures.Count) textures)"

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
