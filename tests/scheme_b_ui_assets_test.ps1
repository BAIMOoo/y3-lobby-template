$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$assetDirectory = Join-Path $repoRoot 'assets\ui\scheme_b'
$expectedIds = 134217729..134217745
$files = Get-ChildItem -LiteralPath $assetDirectory -File -Filter '*.png'

if ($files.Count -ne $expectedIds.Count) {
    throw "Expected $($expectedIds.Count) Scheme B PNG files, found $($files.Count)"
}

$actualIds = foreach ($file in $files) {
    if ($file.BaseName -notmatch '^[^.]+%ID([1-9][0-9]{8})$') {
        throw "Invalid Y3 resource filename: $($file.Name)"
    }
    [int]$Matches[1]
}

if (($actualIds | Select-Object -Unique).Count -ne $actualIds.Count) {
    throw 'Scheme B resource IDs must be unique'
}

foreach ($id in $expectedIds) {
    if ($id -notin $actualIds) {
        throw "Missing Scheme B resource ID: $id"
    }
}

foreach ($id in $actualIds) {
    if ($id -lt 134217728 -or $id -gt 134283263) {
        throw "Scheme B resource ID is outside the allowed range: $id"
    }
}

$packagedFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'custom\OriginalRes\icon') `
    -Recurse -File -Filter 'scheme_b_*.png'
if ($packagedFiles.Count -ne $expectedIds.Count) {
    throw "Expected $($expectedIds.Count) packaged Scheme B PNG files, found $($packagedFiles.Count)"
}
foreach ($file in $packagedFiles) {
    if ($file.BaseName -notmatch '^[^.]+%ID([1-9][0-9]{8})$') {
        throw "Invalid packaged Y3 resource filename: $($file.Name)"
    }
    if ([int]$Matches[1] -notin $expectedIds) {
        throw "Unexpected packaged Scheme B resource ID: $($Matches[1])"
    }
}

$entryScript = Get-Content -Raw -Encoding utf8 (Join-Path $repoRoot 'maps\EntryMap\script\test_ui.lua')
$battleScript = Get-Content -Raw -Encoding utf8 (Join-Path $repoRoot 'maps\MapName001\script\test_ui.lua')
$resourceTable = Get-Content -Raw -Encoding utf8 (Join-Path $repoRoot 'editor_table\resicon.json')
$repository = Get-Content -Raw -Encoding utf8 (
    Join-Path $repoRoot 'custom\CustomImportRepo.local\resource.repository')
foreach ($id in $expectedIds) {
    if ($entryScript -notmatch [regex]::Escape([string]$id)) {
        throw "EntryMap test_ui.lua does not reference resource ID $id"
    }
    if ($battleScript -notmatch [regex]::Escape([string]$id)) {
        throw "MapName001 test_ui.lua does not reference resource ID $id"
    }
    if ($resourceTable -notmatch [regex]::Escape('"ui/' + [string]$id + '"')) {
        throw "editor_table/resicon.json does not register resource ID $id"
    }
    if ($repository -notmatch [regex]::Escape('<Name>' + [string]$id + '</Name>')) {
        throw "CustomImportRepo does not contain runtime texture ID $id"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "editor_table\editoricon\$id.json"))) {
        throw "Missing editor icon metadata for resource ID $id"
    }
}

Write-Host 'scheme_b_ui_assets_test: PASS'
