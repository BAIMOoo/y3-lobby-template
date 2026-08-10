local callbacks = {}
local triggers = {}
local included = {}
local log_lines = {}
local roster_players = {}
local local_player
local connect_calls = {}

y3 = {
    const = {
        RoleType = {
            USER = 1,
            COMPUTER = 2,
        },
    },
    game = {
        get_current_game_mode = function()
            return 1002
        end,
        event = function(_, event_name, callback)
            local trigger = { event_name = event_name, id = #triggers + 1 }
            triggers[#triggers + 1] = trigger
            callbacks[event_name] = callback
            return trigger
        end,
    },
    lobby = {
        get_connection_status = function()
            return {
                code = 'idle',
                result_data = { status = 'idle' },
            }
        end,
        connect = function(game_play_id, in_game, endpoint_env)
            connect_calls[#connect_calls + 1] = {
                game_play_id = game_play_id,
                in_game = in_game,
                endpoint_env = endpoint_env,
            }
            return { accepted = true }
        end,
    },
    player = {
        with_local = function(callback)
            callback(local_player)
        end,
    },
    player_group = {
        get_all_players = function()
            return {
                count = function()
                    return #roster_players
                end,
                pick = function()
                    return roster_players
                end,
            }
        end,
    },
}

GameAPI = {
    get_dungeon_info = function()
        return {
            level_id = 'level-1',
            game_mode = 1002,
            space_id = 'space-1',
            start_game_time = 123,
        }
    end,
}

log = {
    info = function(message)
        log_lines[#log_lines + 1] = message
    end,
}

include = function(module_name)
    included[#included + 1] = module_name
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function assert_contains(value, expected, message)
    if not tostring(value):find(expected, 1, true) then
        error(string.format('%s: expected %q in %q', message, expected, tostring(value)))
    end
end

local function find_log(expected)
    for _, line in ipairs(log_lines) do
        if line:find(expected, 1, true) then
            return line
        end
    end
    error(string.format('log line not found: %s', expected))
end

dofile('maps/MapName001/script/main.lua')

assert_equal(#triggers, 2, 'diagnostic listener count')
assert_equal(#included, 2, 'included module count')
assert_equal(included[1], 'dungeon_unit_spawn', 'spawn include')
assert_equal(included[2], 'pub.test_ui', 'test UI include')
assert_contains(log_lines[1], 'main_load=1', 'main load sequence')
assert_contains(log_lines[1], 'lobby_status=idle', 'lobby status query')
assert_contains(log_lines[2], 'event=游戏-初始化', 'game init registration')
assert_contains(log_lines[3], 'event=玩家-加入游戏', 'player join registration')

local player = {
    get_id = function()
        return 1
    end,
    get_name = function()
        return 'test-player'
    end,
    get_state = function()
        return 1
    end,
    get_controller = function()
        return 1
    end,
    get_camp = function()
        return 1
    end,
    is_alive = function()
        return true
    end,
    need_sync = function()
        return true
    end,
}
local_player = player

local computer_player = {
    get_id = function()
        return 2
    end,
    get_name = function()
        return 'computer-player'
    end,
    get_state = player.get_state,
    get_controller = function()
        return 2
    end,
    get_camp = function()
        return 2
    end,
    is_alive = function()
        return false
    end,
    need_sync = function()
        return false
    end,
}

roster_players = { player, computer_player }

callbacks['游戏-初始化'](triggers[1], {})
callbacks['玩家-加入游戏'](triggers[2], { player = player, is_middle_join = false })
callbacks['玩家-加入游戏'](triggers[2], { player = computer_player, is_middle_join = true })

assert_equal(#connect_calls, 1, 'only local player starts a lobby connection')
assert_equal(connect_calls[1].game_play_id, 190356, 'target level game play id')
assert_equal(connect_calls[1].in_game, true, 'target level connects as in-game')
assert_equal(connect_calls[1].endpoint_env, 'pre', 'target level explicitly connects to pre')

assert_contains(find_log('event received: event=游戏-初始化 main_load=1'), 'event_seq=1', 'game init sequence')

local game_init_roster = find_log('[PlayerRosterDiag] snapshot begin: reason=game-init')
assert_contains(game_init_roster, 'group_count=2', 'game init player group count')
assert_contains(game_init_roster, 'picked_count=2', 'game init picked player count')

local human_roster = find_log('[PlayerRosterDiag] player: reason=game-init index=1')
assert_contains(human_roster, 'player_id=1', 'roster human player id')
assert_contains(human_roster, 'player_controller=1', 'roster human controller')
assert_contains(human_roster, 'is_computer=false', 'roster human type')
assert_contains(human_roster, 'player_camp=1', 'roster human camp')
assert_contains(human_roster, 'is_alive=true', 'roster human alive state')
assert_contains(human_roster, 'need_sync=true', 'roster human sync state')

local computer_roster = find_log('[PlayerRosterDiag] player: reason=game-init index=2')
assert_contains(computer_roster, 'player_id=2', 'roster computer player id')
assert_contains(computer_roster, 'player_name=computer-player', 'roster computer player name')
assert_contains(computer_roster, 'player_controller=2', 'roster computer controller')
assert_contains(computer_roster, 'is_computer=true', 'roster computer type')
assert_contains(computer_roster, 'player_camp=2', 'roster computer camp')
assert_contains(computer_roster, 'is_alive=false', 'roster computer alive state')
assert_contains(computer_roster, 'need_sync=false', 'roster computer sync state')
assert_contains(find_log('[PlayerRosterDiag] snapshot end: reason=game-init'), 'computer_count=1', 'computer player count')

local first_join = find_log('event=玩家-加入游戏 main_load=1 listener=2 event_seq=1')
assert_contains(first_join, 'player_controller=1', 'human player controller')
assert_contains(first_join, 'is_computer=false', 'human player type')
assert_contains(first_join, 'is_middle_join=false', 'first middle-join flag')
assert_contains(find_log('[PlayerRosterDiag] snapshot begin: reason=player-join-1'), 'picked_count=2', 'first join roster')

local second_join = find_log('event=玩家-加入游戏 main_load=1 listener=2 event_seq=2')
assert_contains(second_join, 'player_controller=2', 'computer player controller')
assert_contains(second_join, 'is_computer=true', 'computer player type')
assert_contains(second_join, 'is_middle_join=true', 'second middle-join flag')
assert_contains(find_log('[PlayerRosterDiag] snapshot begin: reason=player-join-2'), 'picked_count=2', 'second join roster')

print('mapname001_event_diagnostics_test: PASS')
