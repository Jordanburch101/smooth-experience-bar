# Builds the release zip of the addon.
#
#   ./scripts/package.ps1                  version from git (tag, or describe)
#   ./scripts/package.ps1 -Version 1.0.0   explicit version
#
# Steps:
#   1. Copies SmoothExperienceBar/ to build/SmoothExperienceBar/.
#   2. Puts the version in place of @project-version@ in the toc.
#   3. Checks the build: every file the toc lists exists, no markers are left,
#      and, with LuaJIT installed, every Lua file compiles.
#   4. Zips build/SmoothExperienceBar/ to dist/SmoothExperienceBar-<version>.zip,
#      with the SmoothExperienceBar folder at the top as WoW expects.
# Exits 1 if any check fails.

param(
    [string]$Version
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$addonName = "SmoothExperienceBar"
$source = Join-Path $root $addonName
$buildRoot = Join-Path $root "build"
$build = Join-Path $buildRoot $addonName
$dist = Join-Path $root "dist"

function Fail($message) {
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

# Version: argument, else the tag CI is building, else git describe, else "dev".
if (-not $Version) {
    if ($env:GITHUB_REF_TYPE -eq "tag") {
        $Version = $env:GITHUB_REF_NAME
    } else {
        # Windows PowerShell turns git's stderr into an error under "Stop".
        $ErrorActionPreference = "Continue"
        $Version = (git -C $root describe --tags --always --dirty 2>$null)
        $ErrorActionPreference = "Stop"
        if ($LASTEXITCODE -ne 0 -or -not $Version) { $Version = "dev" }
    }
}
$Version = $Version -replace '^v', ''
Write-Host "Packaging $addonName $Version"

# 1. Fresh copy.
if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Path $build -Force | Out-Null
Copy-Item -Path (Join-Path $source "*") -Destination $build -Recurse

# 2. Version in the toc, written as UTF-8 without BOM and LF endings on every platform.
$tocPath = Join-Path $build "$addonName.toc"
$toc = Get-Content $tocPath | ForEach-Object { $_.Replace("@project-version@", $Version) }
[System.IO.File]::WriteAllText($tocPath, (($toc -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))

# 3. Check the build.
$listed = @($toc | Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object { $_.Trim() })
foreach ($entry in $listed) {
    if (-not (Test-Path (Join-Path $build $entry))) { Fail "toc lists $entry, which is missing" }
}
foreach ($file in Get-ChildItem $build -Filter *.lua -Recurse) {
    $relative = $file.FullName.Substring($build.Length + 1).Replace('\', '/')
    if ($listed -notcontains $relative) { Fail "$relative is not listed in the toc" }
}
$leftovers = Get-ChildItem $build -Recurse -File -Include *.lua, *.toc | Select-String -Pattern "@project-version@"
if ($leftovers) { Fail ("markers left in the build:`n" + ($leftovers -join "`n")) }

$luajit = Get-Command luajit -ErrorAction SilentlyContinue
if ($luajit) {
    $scratch = [System.IO.Path]::GetTempFileName()
    foreach ($file in Get-ChildItem $build -Filter *.lua -Recurse) {
        $out = & luajit -b $file.FullName $scratch 2>&1
        if ($LASTEXITCODE -ne 0) { Fail "$($file.Name) does not compile: $out" }
    }
    Remove-Item $scratch -ErrorAction SilentlyContinue
} else {
    Write-Host "  luajit not found, skipping the compile check" -ForegroundColor Yellow
}

# 4. Zip with forward slashes in entry names (Compress-Archive on Windows
# PowerShell 5.1 writes backslashes, which some extractors mishandle).
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zipPath = Join-Path $dist "$addonName-$Version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem $build -Recurse -File) {
        $name = "$addonName/" + $file.FullName.Substring($build.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $name,
            [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}

$count = (Get-ChildItem $build -Recurse -File).Count
Write-Host ("Built {0} ({1} files, {2:N0} KB)" -f $zipPath, $count, ((Get-Item $zipPath).Length / 1KB))
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "zip=$zipPath"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "version=$Version"
}
