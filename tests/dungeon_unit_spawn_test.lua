local join_callback
local created_points = {}
local event_trigger = { id = 17 }
local log_lines = {}

y3 = {
    const = {
        RoleType = {
            USER = 1,
            COMPUTER = 2,
        },
    },
    game = {
        event = function(_, _, callback)
            join_callback = callback
            return event_trigger
        end,
    },
    point = {
        create = function(x, y)
            local point = { x = x, y = y }
            created_points[#created_points + 1] = point
            return point
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

dofile('maps/MapName001/script/dungeon_unit_spawn.lua')

local create_calls = {}
local player = {
    get_id = function()
        return 2
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
    create_unit = function(_, unit_key, point, facing)
        create_calls[#create_calls + 1] = {
            unit_key = unit_key,
            point = point,
            facing = facing,
        }
        return { id = #create_calls }
    end,
}

assert(join_callback, 'player join callback was not registered')
assert_contains(log_lines[1], 'module_load=1', 'module load log')
assert_contains(log_lines[2], 'listener=1', 'listener registration log')

join_callback(event_trigger, { player = player, is_middle_join = true })
join_callback(event_trigger, { player = player, is_middle_join = false })

assert_equal(#create_calls, 1, 'duplicate player create call count')
assert_equal(create_calls[1].unit_key, 134273733, 'unit key')
assert_equal(create_calls[1].point, created_points[1], 'first spawn point')
assert_equal(created_points[1].x, 200, 'first spawn x')
assert_equal(created_points[1].y, 0, 'first spawn y')
assert_equal(create_calls[1].facing, 0, 'facing')
assert_contains(log_lines[3], 'callback_seq=1', 'first callback sequence')
assert_contains(log_lines[3], 'player_callback_seq=1', 'first player callback sequence')
assert_contains(log_lines[3], 'player_controller=1', 'human player controller')
assert_contains(log_lines[3], 'is_computer=false', 'human player type')
assert_contains(log_lines[3], 'is_middle_join=true', 'first callback middle-join flag')
assert_contains(log_lines[3], 'space_id=space-1', 'first callback dungeon identity')
assert_contains(log_lines[5], 'callback_seq=2', 'second callback sequence')
assert_contains(log_lines[5], 'player_callback_seq=2', 'second player callback sequence')
assert_contains(log_lines[5], 'is_middle_join=false', 'second callback middle-join flag')
assert_contains(log_lines[6], 'skipped duplicate join event', 'duplicate event skip log')
assert_contains(log_lines[6], 'is_computer=false', 'duplicate event human player type')

local second_player = {
    get_id = function()
        return 3
    end,
    get_name = player.get_name,
    get_state = player.get_state,
    get_controller = function()
        return 2
    end,
    create_unit = player.create_unit,
}

join_callback(event_trigger, { player = second_player, is_middle_join = false })

assert_equal(#create_calls, 2, 'different player create call count')
assert_equal(create_calls[2].point, created_points[2], 'second player spawn point')
assert_equal(created_points[2].x, 400, 'second player spawn x')
assert_equal(created_points[2].y, 0, 'second player spawn y')
assert_contains(log_lines[7], 'player_controller=2', 'computer player controller')
assert_contains(log_lines[7], 'is_computer=true', 'computer player callback type')
assert_contains(log_lines[8], 'is_computer=true', 'computer player created unit type')

print('dungeon_unit_spawn_test: PASS')
