package.preload['pub.runtime_token'] = function()
    return {}
end

log = {
    info = function()
    end,
    debug = function()
    end,
    error = function(err)
        error(err)
    end,
}

y3 = {
    game = {
        event = function()
            return {}
        end,
    },
}

IsValid = function()
    return true
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function assert_file_contains(path, expected, message)
    local file = assert(io.open(path, 'rb'))
    local content = file:read('*a')
    file:close()
    assert(content:find(expected, 1, true), message)
end

local function run_case(path)
    local request
    BOB = {
        client = {},
        team_info = {
            team_id = 101659,
            members = {
                { aid = 53003947 },
                { aid = 53000076 },
            },
        },
        is_valid = function()
            return true
        end,
        is_launching = function()
            return false
        end,
        is_matching = function()
            return false
        end,
        is_captain = function()
            return true
        end,
        is_in_team = function()
            return true
        end,
        get_player_count = function()
            return 2, 8
        end,
        refresh_player_info = function(_, callback)
            callback({}, nil)
        end,
        start_privat_dungeon_game = function(_, dungeon_info, players)
            request = {
                dungeon_info = dungeon_info,
                players = players,
            }
        end,
        map_id = 'test-map',
        level_id = 'test-level',
    }

    dofile(path)
    MatchTestStartPrivate()

    assert(request, path .. ' must send a private dungeon request')
    assert_equal(#request.players, 2, path .. ' player count')
    assert_equal(request.players[1].aid, '53003947', path .. ' first player aid')
    assert_equal(request.players[1].version, '2.0', path .. ' first player version')
    assert_equal(request.players[2].aid, '53000076', path .. ' second player aid')
    assert_equal(request.players[2].version, '2.0', path .. ' second player version')
end

run_case('maps/EntryMap/script/pub/pub.lua')
run_case('maps/MapName001/script/pub/pub.lua')

assert_file_contains(
    'maps/EntryMap/script/pub/ui.lua',
    'version = DUNGEON_PLAYER_VERSION',
    'EntryMap UI private dungeon request must include player version')
assert_file_contains(
    'maps/MapName001/script/pub/ui.lua',
    'version = DUNGEON_PLAYER_VERSION',
    'MapName001 UI private dungeon request must include player version')

print('dungeon_player_version_test: PASS')
