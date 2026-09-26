# Builds CurseForge-ready zips into .release\ for manual upload.
#   .\tools\package.ps1 -Version 0.2.0                  both addons
#   .\tools\package.ps1 -Version 0.2.0 -Addon Darkndark one addon
# The zip contains the addon folder at its root, with @project-version@ in the
# TOC replaced by the given version (what the BigWigs packager would do).
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string[]]$Addon = @("Darkndark", "DarkndarkTalents")
)

$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root ".release"
New-Item -ItemType Directory -Force $out | Out-Null

foreach ($name in $Addon) {
    $source = Join-Path $root $name
    if (-not (Test-Path $source)) { Write-Error "Missing folder: $source"; continue }

    $staging = Join-Path $env:TEMP ("dnd-pack-" + [guid]::NewGuid())
    $dest = Join-Path $staging $name
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item -Path (Join-Path $source "*") -Destination $dest -Recurse -Force

    $toc = Join-Path $dest "$name.toc"
    $text = [IO.File]::ReadAllText($toc)
    $text = $text.Replace("@project-version@", $Version)
    [IO.File]::WriteAllText($toc, $text, (New-Object Text.UTF8Encoding($false)))

    $zip = Join-Path $out "$name-v$Version.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    # Compress-Archive in PowerShell 5.1 writes "\" in entry names, which breaks
    # on Mac/Linux, so build the zip by hand with "/" separators.
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem $dest -Recurse -File | ForEach-Object {
            $rel = $name + "/" + $_.FullName.Substring($dest.Length + 1).Replace("\", "/")
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $rel)
        }
    } finally {
        $archive.Dispose()
    }
    Remove-Item $staging -Recurse -Force

    $size = [math]::Round((Get-Item $zip).Length / 1KB, 1)
    Write-Host "OK  $zip ($size KB)"
}
