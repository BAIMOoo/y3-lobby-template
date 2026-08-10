local classes = {}
local logs = {}
local remote_version = '2.5.23.760719'

function Class(name)
    local class = {}
    classes[name] = class
    return class
end

function Extends()
end

package.preload['pub.core.service.client'] = function()
    return {}
end

local function record_log(level, ...)
    local parts = { level }
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    logs[#logs + 1] = table.concat(parts, '\t')
end

log = {
    debug = function(...)
        record_log('debug', ...)
    end,
    info = function(...)
        record_log('info', ...)
    end,
    warn = function(...)
        record_log('warn', ...)
    end,
    error = function(...)
        record_log('error', ...)
    end,
}

y3 = {
    inspect = function()
        return ''
    end,
    player = {
        get_local = function()
            return {}
        end,
    },
    game = {
        is_debug_mode = function()
            return false
        end,
        request_url = function(_, _, _, callback)
            callback('{}')
        end,
    },
    ctimer = {
        wait = function()
            return {
                remove = function()
                end,
            }
        end,
    },
    json = {
        decode = function()
            return {
                ['2.0'] = {
                    ['@metadata@'] = {
                        ['@displayversion@'] = remote_version,
                    },
                },
            }
        end,
    },
}

GameAPI = {
    visual_pyexec = function()
    end,
    get_dungeon_info = function()
        return { env = 'prod' }
    end,
}

dofile('maps/EntryMap/script/pub/core/bob.lua')

local Bob = assert(classes.Bob)

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function assert_log_contains(text, message)
    for _, line in ipairs(logs) do
        if line:find(text, 1, true) then
            return
        end
    end
    error(message .. ': missing ' .. text .. '\nlogs:\n' .. table.concat(logs, '\n'))
end

local function run_case(local_version, injection_status)
    logs = {}
    _G['_SVN_VERSION'] = local_version
    _G['_SVN_VERSION_INJECTION_STATUS'] = injection_status
    local result
    Bob.check_update({}, function(need_update)
        result = need_update
    end)
    return result
end

assert_equal(run_case(nil, 'failed: import error'), true, 'missing local version blocks startup')
assert_log_contains('result=local-version-missing', 'missing-version result')
assert_log_contains('injection=\tfailed: import error', 'injection failure detail')

assert_equal(run_case('2.5.22.750000', 'ok'), true, 'old client version blocks startup')
assert_log_contains('result=client-version-mismatch', 'client mismatch result')
assert_log_contains('local=\t2.5.22.750000', 'client mismatch local value')
assert_log_contains('remote=\t2.5.23.760719', 'client mismatch remote value')

assert_equal(run_case(123, 'ok'), true, 'different version type blocks startup')
remote_version = '123'
assert_equal(run_case(123, 'ok'), true, 'same text with different type preserves comparison behavior')
assert_log_contains('result=version-type-mismatch', 'type mismatch result')

remote_version = '2.5.23.760719'
assert_equal(run_case(remote_version, 'ok'), false, 'matching version allows startup')
assert_log_contains('result=version-match', 'matching-version result')

local private_request_count = 0
local bob = setmetatable({
    aid = 1001,
    request_handlers = {},
    team_info = {
        captain = 2002,
        member_limit = 2,
        members = {
            { aid = 1001 },
            { aid = 2002 },
        },
    },
    client = {
        DungeonManager_StartMatchPrivateDungeonGame = function()
            private_request_count = private_request_count + 1
        end,
    },
}, { __index = Bob })

local team_count, max_count = bob:get_player_count()
assert_equal(team_count, 2, 'team member count')
assert_equal(max_count, 2, 'team member limit')

local allowed, reason = bob:start_privat_dungeon_game({}, {})
assert_equal(allowed, false, 'non-captain private dungeon guard')
assert_equal(reason, '只有队长可以进入多人副本', 'non-captain private dungeon reason')
assert_equal(private_request_count, 0, 'non-captain private dungeon request count')

bob.team_info.captain = bob.aid
bob.can_match = function()
    return true
end
local private_callback_result
local private_callback_error
assert_equal(bob:start_privat_dungeon_game({}, {}, function(result, err)
    private_callback_result = result
    private_callback_error = err
end), true, 'captain private dungeon request')
assert_equal(private_request_count, 1, 'captain private dungeon request count')
bob:notify_ret('DungeonManager_StartMatchPrivateDungeonGame', 1, {}, { ret1 = { started = true } })
assert_equal(private_callback_result.started, true, 'private dungeon callback result')
assert_equal(private_callback_error, nil, 'private dungeon callback error')

print('bob_version_diagnostics_test: PASS')
