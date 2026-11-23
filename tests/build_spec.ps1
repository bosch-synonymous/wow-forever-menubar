# Reusable packaging checks. Every fixture and generated package stays in scratch/.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture = Join-Path $repository ('scratch\build-spec\' + [guid]::NewGuid().ToString('N'))
$core = Join-Path $fixture 'candidate'
$coreSource = Join-Path $core 'src\menubar-core'
$timeSource = Join-Path $core 'src\menubar-time'
$socialSource = Join-Path $core 'src\menubar-social'
$performanceSource = Join-Path $core 'src\menubar-performance'
$mailSource = Join-Path $core 'src\menubar-mail'
$durabilitySource = Join-Path $core 'src\menubar-durability'
$builder = Join-Path $core 'tools\Build.ps1'
New-Item -ItemType Directory -Path $coreSource, $timeSource, $socialSource, $performanceSource, $mailSource, $durabilitySource, (Split-Path -Parent $builder) -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repository 'tools\Build.ps1') -Destination $builder
$validCoreToc = "## Interface: 16001`n## Version: 0.6.0`nCore.lua`n"
Set-Content -LiteralPath (Join-Path $coreSource 'Menubar.toc') -Value $validCoreToc -NoNewline
Set-Content -LiteralPath (Join-Path $coreSource 'Core.lua') -Value '-- Packaging fixture only.'
Set-Content -LiteralPath (Join-Path $timeSource 'Menubar_Time.toc') -Value "## Interface: 16001`n## Dependencies: Menubar`nTime.lua`n"
Set-Content -LiteralPath (Join-Path $timeSource 'Time.lua') -Value '-- Packaging fixture only.'
Set-Content -LiteralPath (Join-Path $socialSource 'Menubar_Social.toc') -Value "## Interface: 16001`n## Dependencies: Menubar`nSocial.lua`n"
Set-Content -LiteralPath (Join-Path $socialSource 'Social.lua') -Value '-- Packaging fixture only.'
Set-Content -LiteralPath (Join-Path $performanceSource 'Menubar_Performance.toc') -Value "## Interface: 16001`n## Dependencies: Menubar`nPerformance.lua`n"
Set-Content -LiteralPath (Join-Path $performanceSource 'Performance.lua') -Value '-- Packaging fixture only.'
Set-Content -LiteralPath (Join-Path $mailSource 'Menubar_Mail.toc') -Value "## Interface: 16001`n## Dependencies: Menubar`nMail.lua`n"
Set-Content -LiteralPath (Join-Path $mailSource 'Mail.lua') -Value '-- Packaging fixture only.'
Set-Content -LiteralPath (Join-Path $durabilitySource 'Menubar_Durability.toc') -Value "## Interface: 16001`n## Dependencies: Menubar`nDurability.lua`n"
Set-Content -LiteralPath (Join-Path $durabilitySource 'Durability.lua') -Value '-- Packaging fixture only.'
$distributionFiles = @(
    (Join-Path $core 'LICENSE'), (Join-Path $core 'README.md'), (Join-Path $core 'CHANGELOG.md')
)
foreach ($file in $distributionFiles) {
    Set-Content -LiteralPath $file -Value ("Distribution fixture: " + [IO.Path]::GetRelativePath($fixture, $file)) -Encoding utf8
}
# Assets need not be TOC entries: the package must preserve the complete source trees.
$assetDirectory = Join-Path $coreSource 'Textures'
New-Item -ItemType Directory -Path $assetDirectory | Out-Null
[IO.File]::WriteAllBytes((Join-Path $assetDirectory 'original-asset.bin'), [byte[]]@(0, 7, 128, 255))

$script:passed = 0
function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Source-Hashes {
    $result = @{}
    foreach ($source in @($coreSource, $timeSource, $socialSource, $performanceSource, $mailSource, $durabilitySource)) {
        foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
            $result[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    foreach ($file in $distributionFiles) {
        $result[$file] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $result
}
function Assert-SourcesUnchanged([hashtable]$Before) {
    $after = Source-Hashes
    Assert-That ($Before.Count -eq $after.Count) 'Packaging changed source file membership.'
    foreach ($path in $Before.Keys) { Assert-That ($Before[$path] -eq $after[$path]) "Packaging changed source bytes: $path" }
}
function Source-AddonName([string]$Source) {
    $tocs = @(Get-ChildItem -LiteralPath $Source -File -Filter '*.toc')
    Assert-That ($tocs.Count -eq 1) "One source TOC is required for fixture: $Source"
    return $tocs[0].BaseName
}
function Check-Package([string]$Output, [string[]]$Selected = @('Time'), [int]$ExpectedInterface = 16001, [string]$ExpectedVersion = '0.6.0') {
    $manifest = Get-Content -LiteralPath (Join-Path $Output 'manifest.json') -Raw | ConvertFrom-Json
    Assert-That ($manifest.version -eq $ExpectedVersion) 'Package version must come from the core TOC.'
    $names = @('Menubar') + @($Selected | ForEach-Object { 'Menubar_' + $_ })
    Assert-That (($manifest.addons -join ',') -eq ($names -join ',')) 'Canonical selected addons must occur exactly once.'
    Assert-That ($manifest.interface -eq $ExpectedInterface) 'Interface metadata must come from the core TOC.'
    Assert-That ($manifest.targetProduct -eq 'World of Warcraft: Forever') 'The target product must stay independent of executable build labels.'
    Assert-That ($manifest.PSObject.Properties.Name -notcontains 'targetClient') 'The manifest must not claim an unverified executable build.'
    Assert-That ($manifest.PSObject.Properties.Name -notcontains 'territoryDataBuilds') 'Dataset provenance must not be duplicated as a hardcoded packager list.'
    $expected = @{}
    $selectedSources = @($coreSource) + @($Selected | ForEach-Object { Join-Path $core ('src\menubar-' + $_.ToLowerInvariant()) })
    foreach ($source in $selectedSources) {
        foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
            $relative = [IO.Path]::GetRelativePath($source, $file.FullName).Replace('\', '/')
            $expected[(Source-AddonName $source) + '/' + $relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $repo = $core
        $metadata = if ($source -eq $coreSource) { @('LICENSE', 'README.md', 'CHANGELOG.md') } else { @() }
        foreach ($name in $metadata) {
            $file = Join-Path $repo $name
            $expected[(Source-AddonName $source) + '/' + $name] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    Assert-That ($manifest.files.Count -eq $expected.Count) 'Manifest file count must match runtime assets and distribution files.'
    foreach ($file in $manifest.files) {
        Assert-That ($expected.ContainsKey($file.path)) "Unexpected manifest file: $($file.path)"
        Assert-That ($file.sha256 -eq $expected[$file.path]) "Manifest hash differs from source: $($file.path)"
        $copied = Join-Path (Join-Path $Output 'AddOns') $file.path
        Assert-That ((Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash.ToLowerInvariant() -eq $file.sha256) "Copied file differs from manifest: $($file.path)"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Path]::GetFullPath((Join-Path $Output "Menubar-$ExpectedVersion.zip"))
    Assert-That ([IO.Path]::GetDirectoryName($zip) -eq [IO.Path]::GetFullPath($Output)) 'The release archive must stay directly inside the output directory.'
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $files = @($archive.Entries | Where-Object { $_.Name })
        Assert-That ($files.Count -eq $expected.Count) 'ZIP file count must match source and manifest.'
        $seen = @{}
        foreach ($entry in $files) {
            $path = $entry.FullName.Replace('\', '/')
            Assert-That (-not $seen.ContainsKey($path)) "Duplicate ZIP entry: $path"
            $seen[$path] = $true
            Assert-That ($expected.ContainsKey($path)) "Unexpected ZIP path (addon directories must be at its root): $path"
            $stream = $entry.Open()
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
            finally { $stream.Dispose(); $algorithm.Dispose() }
            Assert-That ($hash -eq $expected[$path]) "ZIP bytes differ from source: $path"
        }
    }
    finally { $archive.Dispose() }
    $script:passed++
    Write-Output "PASS ZIP, manifest, copied files, original assets and distribution files agree: $(Split-Path -Leaf $Output)"
}
function Reject-BeforeOutput([string]$Name, [string[]]$Widgets, [string]$ExpectedError) {
    $output = Join-Path $fixture $Name
    $caught = $null
    try { & $builder -Widgets $Widgets -OutputDirectory $output | Out-Null }
    catch { $caught = $_ }
    Assert-That ($null -ne $caught) "Expected rejection for $Name."
    Assert-That ($caught.Exception.Message -like "*$ExpectedError*") "Unexpected rejection for ${Name}: $($caught.Exception.Message)"
    Assert-That (-not (Test-Path -LiteralPath $output)) "Invalid inputs created output for $Name."
    $script:passed++
    Write-Output "PASS $Name rejected before creating output"
}

$before = Source-Hashes
$normalOutput = Join-Path $fixture 'normal'
& $builder -Widgets @('Time') -OutputDirectory $normalOutput | Out-Null
Check-Package $normalOutput
Assert-SourcesUnchanged $before
$coreOnlyOutput = Join-Path $fixture 'core-only'
& $builder -Widgets @() -OutputDirectory $coreOnlyOutput | Out-Null
Check-Package -Output $coreOnlyOutput -Selected @()
Assert-SourcesUnchanged $before
$duplicateOutput = Join-Path $fixture 'mixed-case'
& $builder -Widgets @('Time', 'time', 'TIME') -OutputDirectory $duplicateOutput | Out-Null
Check-Package $duplicateOutput
Assert-SourcesUnchanged $before
$socialOutput = Join-Path $fixture 'social-mixed-case'
& $builder -Widgets @('Social', 'social', 'SOCIAL', 'Time') -OutputDirectory $socialOutput | Out-Null
Check-Package $socialOutput @('Social', 'Time')
Assert-SourcesUnchanged $before
$performanceOutput = Join-Path $fixture 'performance-mixed-case'
& $builder -Widgets @('Performance', 'performance', 'PERFORMANCE', 'Social', 'Time') -OutputDirectory $performanceOutput | Out-Null
Check-Package $performanceOutput @('Performance', 'Social', 'Time')
Assert-SourcesUnchanged $before
$mailDurabilityOutput = Join-Path $fixture 'mail-durability-mixed-case'
& $builder -Widgets @('Mail', 'mail', 'MAIL', 'Durability', 'durability', 'DURABILITY', 'Performance', 'Time') -OutputDirectory $mailDurabilityOutput | Out-Null
Check-Package $mailDurabilityOutput @('Mail', 'Durability', 'Performance', 'Time')
Assert-SourcesUnchanged $before

# Updating all selected loader declarations is sufficient for a later interface;
# the packager must not require another literal version edit of its own.
$fixtureTocs = @($coreSource, $timeSource, $socialSource, $performanceSource, $mailSource, $durabilitySource) | ForEach-Object {
    Join-Path $_ ((Source-AddonName $_) + '.toc')
}
$savedTocBytes = @{}
try {
    foreach ($fixtureToc in $fixtureTocs) {
        $savedTocBytes[$fixtureToc] = [IO.File]::ReadAllBytes($fixtureToc)
        $nextToc = [regex]::Replace([IO.File]::ReadAllText($fixtureToc), '(?m)^## Interface:[ \t]*[0-9]+[ \t]*\r?$', '## Interface: 16002')
        [IO.File]::WriteAllText($fixtureToc, $nextToc)
    }
    $nextBefore = Source-Hashes
    $nextOutput = Join-Path $fixture 'next-interface'
    & $builder -Widgets @('Time', 'Social', 'Performance', 'Mail', 'Durability') -OutputDirectory $nextOutput | Out-Null
    Check-Package $nextOutput @('Time', 'Social', 'Performance', 'Mail', 'Durability') 16002
    Assert-SourcesUnchanged $nextBefore
}
finally {
    foreach ($fixtureToc in $savedTocBytes.Keys) { [IO.File]::WriteAllBytes($fixtureToc, $savedTocBytes[$fixtureToc]) }
}
Assert-SourcesUnchanged $before

foreach ($file in @((Join-Path $core 'LICENSE'), (Join-Path $core 'README.md'), (Join-Path $core 'CHANGELOG.md'))) {
    $file = [IO.Path]::GetFullPath($file)
    $saved = $file + '.disabled'
    [IO.File]::Move($file, $saved)
    try {
        $name = 'missing-' + (Split-Path -Leaf (Split-Path -Parent $file)) + '-' + (Split-Path -Leaf $file)
        Reject-BeforeOutput $name @('Time') 'Missing distribution file'
    }
    finally { [IO.File]::Move($saved, $file) }
}
foreach ($name in @('LICENSE', 'README.md', 'CHANGELOG.md')) {
    $reserved = Join-Path $coreSource $name
    Set-Content -LiteralPath $reserved -Value 'A second source copy must not be overwritten.'
    try { Reject-BeforeOutput ('reserved-' + $name) @('Time') 'Reserved distribution file already exists' }
    finally { Remove-Item -LiteralPath $reserved }
}
Assert-SourcesUnchanged $before

$duplicateAlias = Join-Path $core 'src\clock-copy'
New-Item -ItemType Directory -Path $duplicateAlias | Out-Null
$duplicateToc = Join-Path $duplicateAlias 'Menubar_Time.toc'
Copy-Item -LiteralPath (Join-Path $timeSource 'Menubar_Time.toc') -Destination $duplicateToc
try { Reject-BeforeOutput 'duplicate-addon-identity' @('Time') 'Multiple source folders declare addon' }
finally { Remove-Item -LiteralPath $duplicateToc }
Reject-BeforeOutput 'unknown-widget' @('Invalid') 'Unknown widget'
Reject-BeforeOutput 'missing-addon' @('Ammo') 'Missing addon'
$toc = Join-Path $coreSource 'Menubar.toc'
Set-Content -LiteralPath $toc -Value "## Interface: 99999`n## Version: 0.6.0`nCore.lua`n"
Reject-BeforeOutput 'mismatched-core-interface' @('Time') 'Mismatched interface'
Set-Content -LiteralPath $toc -Value $validCoreToc -NoNewline
$timeToc = Join-Path $timeSource 'Menubar_Time.toc'
$originalTimeToc = [IO.File]::ReadAllBytes($timeToc)
try {
    Set-Content -LiteralPath $timeToc -Value "## Interface: 16002`n## Dependencies: Menubar`nTime.lua`n"
    Reject-BeforeOutput 'mismatched-widget-interface' @('Time') 'Mismatched interface'
    foreach ($target in @($toc, $timeToc)) {
        $isCore = $target -eq $toc
        $suffix = if ($isCore) { "## Version: 0.6.0`nCore.lua`n" } else { "## Dependencies: Menubar`nTime.lua`n" }
        $kind = if ($isCore) { 'core' } else { 'widget' }
        [IO.File]::WriteAllBytes($timeToc, $originalTimeToc)
        foreach ($value in @('0', '-1', '16001.0', '16001, 16002', 'not-a-number', '999999999999999999999999999999', '')) {
            Set-Content -LiteralPath $target -Value ("## Interface: $value`n" + $suffix)
            Reject-BeforeOutput ("malformed-$kind-interface-" + [guid]::NewGuid().ToString('N')) @('Time') 'positive integer'
        }
        Set-Content -LiteralPath $target -Value $suffix
        Reject-BeforeOutput "missing-$kind-interface" @('Time') 'exactly one Interface field'
        foreach ($second in @('16001', '16002', 'invalid')) {
            Set-Content -LiteralPath $target -Value ("## Interface: 16001`n## Interface: $second`n" + $suffix)
            Reject-BeforeOutput ("duplicate-$kind-interface-$second") @('Time') 'exactly one Interface field'
        }
        Set-Content -LiteralPath $toc -Value $validCoreToc -NoNewline
    }
}
finally {
    Set-Content -LiteralPath $toc -Value $validCoreToc -NoNewline
    [IO.File]::WriteAllBytes($timeToc, $originalTimeToc)
}
Set-Content -LiteralPath $toc -Value "## Interface: 16001`nCore.lua`n"
Reject-BeforeOutput 'missing-version' @('Time') 'exactly one Version field'
foreach ($second in @('0.6.0', '0.6.1', 'invalid')) {
    Set-Content -LiteralPath $toc -Value "## Interface: 16001`n## Version: 0.6.0`n## Version: $second`nCore.lua`n"
    Reject-BeforeOutput ('duplicate-version-' + $second) @('Time') 'exactly one Version field'
}
foreach ($invalid in @('', '0.6.0 extra', 'x\..\..\escaped', 'x/../../escaped', '..', '.0.6.0', '0.6.0.', '0.6:0', '0.6*0', '0.6?0', '0.6"0')) {
    Set-Content -LiteralPath $toc -Value "## Interface: 16001`n## Version: $invalid`nCore.lua`n"
    $invalidBefore = Source-Hashes
    Reject-BeforeOutput ('invalid-version-' + [guid]::NewGuid().ToString('N')) @('Time') 'filename-safe Version'
    Assert-SourcesUnchanged $invalidBefore
}
Assert-That (-not (Test-Path -LiteralPath (Join-Path $fixture 'escaped.zip'))) 'Malformed release metadata must never produce an archive outside the output directory.'
foreach ($release in @('0.10.2', '0.11.0-alpha.1', '0.11.0-beta.2+build.7', 'v1.0_rc1')) {
    Set-Content -LiteralPath $toc -Value "## Interface: 16001`n## Version: $release`nCore.lua`n"
    $releaseBefore = Source-Hashes
    $releaseOutput = Join-Path $fixture ('release-' + $release)
    & $builder -Widgets @('Time') -OutputDirectory $releaseOutput | Out-Null
    Check-Package $releaseOutput @('Time') 16001 $release
    Assert-SourcesUnchanged $releaseBefore
}
Set-Content -LiteralPath $toc -Value "## Interface: 16001`n## Version: 0.6.0`nmissing.lua`n"
Reject-BeforeOutput 'missing-toc-file' @('Time') 'Missing TOC file'
Set-Content -LiteralPath (Join-Path (Split-Path -Parent $coreSource) 'outside.lua') -Value '-- Outside addon source.'
Set-Content -LiteralPath $toc -Value "## Interface: 16001`n## Version: 0.6.0`n../outside.lua`n"
Reject-BeforeOutput 'escaping-toc-file' @('Time') 'TOC entry leaves its addon folder'
Set-Content -LiteralPath $toc -Value $validCoreToc -NoNewline
Assert-SourcesUnchanged $before
$script:passed++
Write-Output 'PASS packaging preserves source files'
Write-Output "$script:passed packaging checks passed. Fixtures: $fixture"
