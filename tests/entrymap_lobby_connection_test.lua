local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local callbacks = {}
local connect_calls = {}
local included = {}
local local_player = { name = 'local' }
local other_player = { name = 'other' }

y3 = {
    config = {
        log = {},
    },
    game = {
        event = function(_, event_name, callback)
            callbacks[event_name] = callback
            return {}
        end,
    },
    player = {
        with_local = function(callback)
            callback(local_player)
        end,
    },
    lobby = {
        connect = function(game_play_id, in_game, endpoint_env)
            connect_calls[#connect_calls + 1] = {
                game_play_id = game_play_id,
                in_game = in_game,
                endpoint_env = endpoint_env,
            }
            return { accepted = true }
        end,
    },
}

include = function(module_name)
    included[#included + 1] = module_name
end

dofile('maps/EntryMap/script/main.lua')

assert_equal(included[1], 'test_ui', 'test UI include')
assert(callbacks['玩家-加入游戏'], 'player join listener must be registered')

callbacks['玩家-加入游戏'](nil, { player = other_player })
assert_equal(#connect_calls, 0, 'other player does not start a connection')

callbacks['玩家-加入游戏'](nil, { player = local_player })
assert_equal(#connect_calls, 1, 'local player starts one connection')
assert_equal(connect_calls[1].game_play_id, 190356, 'required game play id')
assert_equal(connect_calls[1].in_game, false, 'entry map connects as lobby')
assert_equal(connect_calls[1].endpoint_env, 'prod', 'entry map explicitly connects to prod')

callbacks['玩家-加入游戏'](nil, { player = other_player })
assert_equal(#connect_calls, 1, 'later joins do not reconnect the local client')

print('entrymap_lobby_connection_test: PASS')
