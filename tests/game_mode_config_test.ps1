$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$lobbyLevelId = '172371058548994502264384971909138463342'
$dungeonLevelId = '50377054694119407947881484918402159964'
$lobbyMode = 1001
$matchMode = 1002
$privateMode = 1003

function Assert-Equal {
    param(
        [Parameter(Mandatory)] $Actual,
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] [string] $Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message`: expected $Expected, got $Actual"
    }
}

$gameModeConfig = Get-Content -LiteralPath (Join-Path $projectRoot 'gamemode.json') -Encoding UTF8 -Raw |
    ConvertFrom-Json
$dungeonConfig = Get-Content -LiteralPath (Join-Path $projectRoot 'dungeon.json') -Encoding UTF8 -Raw |
    ConvertFrom-Json
$matchConfig = Get-Content -LiteralPath (Join-Path $projectRoot 'match.json') -Encoding UTF8 -Raw |
    ConvertFrom-Json

$matchRule = @($matchConfig | Where-Object { [int] $_.game_mode -eq $matchMode })
Assert-Equal $matchRule.Count 1 'match rule count'
Assert-Equal ([int] $matchRule[0].sections[0].min_player_num) 2 'minimum match players'

$configuredModes = $gameModeConfig.game_modes.PSObject.Properties.Name
Assert-Equal ($configuredModes -contains [string] $lobbyMode) $true 'lobby mode registration'
Assert-Equal ($configuredModes -contains [string] $matchMode) $true 'match mode registration'
Assert-Equal ($configuredModes -contains [string] $privateMode) $true 'private mode registration'

$lobbyModes = $dungeonConfig.$lobbyLevelId.game_modes
$dungeonModes = $dungeonConfig.$dungeonLevelId.game_modes
Assert-Equal ([int] $lobbyModes.'1001'.enable_private) 1 'lobby private creation switch'
Assert-Equal ([int] $lobbyModes.'1001'.max_player_num) 8 'lobby mode player limit'
Assert-Equal ([int] $dungeonModes.'1002'.enable_private) 1 'match battle creation switch'
Assert-Equal ([int] $dungeonModes.'1003'.enable_private) 1 'private mode private switch'
Assert-Equal ([int] $dungeonModes.'1002'.max_player_num) 8 'match mode player limit'
Assert-Equal ([int] $dungeonModes.'1003'.max_player_num) 8 'private mode player limit'
Assert-Equal ([int] $dungeonModes.'1003'.can_add_in_time) 120 'private mode middle-join window'

Write-Output 'game_mode_config_test: PASS'
