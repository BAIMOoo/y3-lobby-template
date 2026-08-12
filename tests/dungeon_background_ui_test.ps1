$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$uiScriptPath = Join-Path $projectRoot 'maps\MapName001\script\test_ui.lua'
$source = Get-Content -Raw -LiteralPath $uiScriptPath

$visibilityPattern = 'local battle_mode = not is_lobby_mode\(mode\)\s+runtime\.backdrop:set_visible\(not battle_mode\)'
if ($source -notmatch $visibilityPattern) {
    throw 'The fullscreen backdrop must be hidden outside lobby mode.'
}

Write-Output 'PASS: dungeon backdrop visibility is correct.'
