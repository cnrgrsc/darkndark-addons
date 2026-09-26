# Links every addon folder in this repo into WoW's AddOns folder as a directory
# junction, so edits here show up in game after /reload. Safe to run again.
param(
    [string]$WowPath = "C:\Program Files (x86)\World of Warcraft\_retail_"
)

$addonFolders = @("Darkndark", "DarkndarkTalents")
$addons = Join-Path $WowPath "Interface\AddOns"

if (-not (Test-Path $WowPath)) {
    Write-Error "WoW not found at '$WowPath'. Run: .\install.ps1 -WowPath 'D:\...\_retail_'"
    exit 1
}
New-Item -ItemType Directory -Force $addons | Out-Null

foreach ($name in $addonFolders) {
    $source = Join-Path $PSScriptRoot $name
    $target = Join-Path $addons $name
    if (Test-Path $target) {
        $item = Get-Item $target -Force
        if ($item.LinkType -eq "Junction") {
            Write-Host "OK      $name (already linked)"
        } else {
            Write-Warning "SKIP    $name : '$target' exists and is not a junction. Remove or rename it first."
        }
        continue
    }
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "LINKED  $name"
}
