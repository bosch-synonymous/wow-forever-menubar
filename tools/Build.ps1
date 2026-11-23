[CmdletBinding()]
param(
    [string[]]$Widgets = @('Time', 'Currency', 'Location', 'Reputation', 'XP', 'Ammo', 'Network', 'Eyes', 'Volume', 'Social', 'Performance', 'Mail', 'Durability'),
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
function Get-TocInterface([string[]]$Entries, [string]$Toc) {
    $fields = @($Entries | Select-String -Pattern '^## Interface:\s*(.*?)\s*$')
    if ($fields.Count -ne 1) { throw "TOC needs exactly one Interface field: $Toc" }
    $value = $fields[0].Matches[0].Groups[1].Value
    $parsed = 0
    if ($value -notmatch '^[0-9]+$' -or -not [int]::TryParse($value, [ref]$parsed) -or $parsed -le 0) {
        throw "Interface must be a positive integer: $Toc"
    }
    return $parsed
}

$coreRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceDirectories = @{}
$sourceRoot = Join-Path $coreRoot 'src'
foreach ($directory in Get-ChildItem -LiteralPath $sourceRoot -Directory) {
    foreach ($tocFile in Get-ChildItem -LiteralPath $directory.FullName -File -Filter '*.toc') {
        $addonName = $tocFile.BaseName
        if ($addonName -ne 'Menubar' -and $addonName -notlike 'Menubar_*') { continue }
        if ($sourceDirectories.ContainsKey($addonName)) { throw "Multiple source folders declare addon: $addonName" }
        $sourceDirectories[$addonName] = $directory.FullName
    }
}
function Find-AddonSource([string]$Name) {
    if (-not $sourceDirectories.ContainsKey($Name)) { throw "Missing addon: $Name.toc" }
    return $sourceDirectories[$Name]
}
$coreSource = Find-AddonSource 'Menubar'
$coreToc = Join-Path $coreSource 'Menubar.toc'
$coreEntries = Get-Content -LiteralPath $coreToc
$interfaceVersion = Get-TocInterface $coreEntries $coreToc
$versionFields = @($coreEntries | Select-String -Pattern '^## Version:\s*(.*?)\s*$')
if ($versionFields.Count -ne 1) { throw 'Menubar.toc needs exactly one Version field.' }
$version = $versionFields[0].Matches[0].Groups[1].Value
if ($version -notmatch '^[A-Za-z0-9]+(?:[._+-][A-Za-z0-9]+)*$') {
    throw 'Menubar.toc needs a filename-safe Version (letters, digits, and separated . _ + - components).'
}
if (-not $OutputDirectory) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $OutputDirectory = Join-Path $coreRoot "scratch\dist\Menubar-$version-$stamp"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Output already exists. Choose a new directory: $OutputDirectory"
}
$zipPath = [IO.Path]::GetFullPath((Join-Path $OutputDirectory "Menubar-$version.zip"))
if (-not [IO.Path]::GetDirectoryName($zipPath).Equals($OutputDirectory.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Package ZIP must stay directly inside the output directory.'
}

$sources = @([pscustomobject]@{
    Name = 'Menubar'; Path = $coreSource; Repository = $coreRoot
    DistributionFiles = @('LICENSE', 'README.md', 'CHANGELOG.md')
})
$known = @('Time', 'Currency', 'Location', 'Reputation', 'XP', 'Ammo', 'Network', 'Eyes', 'Volume', 'Social', 'Performance', 'Mail', 'Durability')
$selected = @()
foreach ($widget in $Widgets) {
    if ($widget -notin $known) { throw "Unknown widget: $widget" }
    # Canonical spelling is important for folder/TOC names on case-sensitive filesystems.
    $widget = $known | Where-Object { $_ -eq $widget } | Select-Object -First 1
    if ($widget -in $selected) { continue }
    $selected += $widget
    $sources += [pscustomobject]@{
        Name = "Menubar_$widget"; Path = Find-AddonSource "Menubar_$widget"; Repository = $coreRoot
        DistributionFiles = @()
    }
}

# Validate all inputs before producing a partial package. No source tree is modified.
foreach ($source in $sources) {
    $sourcePrefix = [IO.Path]::GetFullPath($source.Path).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $outputPrefix = $OutputDirectory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($outputPrefix.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package output must be outside every addon source folder.'
    }
    $toc = Join-Path $source.Path ($source.Name + '.toc')
    if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) { throw "Missing addon: $toc" }
    $entries = Get-Content -LiteralPath $toc
    $addonInterface = Get-TocInterface $entries $toc
    if ($addonInterface -ne $interfaceVersion) {
        throw "Mismatched interface version: $toc (expected $interfaceVersion; found $addonInterface)"
    }
    foreach ($entry in $entries) {
        $entry = $entry.Trim()
        if (-not $entry -or $entry.StartsWith('#')) { continue }
        $file = [IO.Path]::GetFullPath((Join-Path $source.Path $entry))
        $allowedPrefix = [IO.Path]::GetFullPath($source.Path).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $file.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "TOC entry leaves its addon folder: $entry"
        }
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing TOC file: $file" }
    }
    foreach ($name in $source.DistributionFiles) {
        $file = Join-Path $source.Repository $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing distribution file: $file" }
        # The repository-root file is canonical. Refuse an ambiguous second
        # copy instead of silently overwriting runtime-source content.
        $reserved = Join-Path $source.Path $name
        if (Test-Path -LiteralPath $reserved) { throw "Reserved distribution file already exists in addon source: $reserved" }
    }
}

$addonsDirectory = Join-Path $OutputDirectory 'AddOns'
New-Item -ItemType Directory -Path $addonsDirectory -Force | Out-Null
foreach ($source in $sources) {
    Copy-Item -LiteralPath $source.Path -Destination (Join-Path $addonsDirectory $source.Name) -Recurse
    foreach ($name in $source.DistributionFiles) {
        Copy-Item -LiteralPath (Join-Path $source.Repository $name) -Destination (Join-Path (Join-Path $addonsDirectory $source.Name) $name)
    }
}
$addonPaths = @($sources | ForEach-Object { Join-Path $addonsDirectory $_.Name })
Compress-Archive -LiteralPath $addonPaths -DestinationPath $zipPath

$manifest = [ordered]@{
    version = $version
    interface = $interfaceVersion
    targetProduct = 'World of Warcraft: Forever'
    addons = @($sources.Name)
    files = @(Get-ChildItem -LiteralPath $addonsDirectory -File -Recurse | ForEach-Object {
        [ordered]@{
            path = [IO.Path]::GetRelativePath($addonsDirectory, $_.FullName).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.json') -Encoding utf8
Write-Output "Packaged $($sources.Count) addons."
Write-Output $zipPath
Write-Output "Extract the ZIP directly into the Forever client's Interface\AddOns directory."
