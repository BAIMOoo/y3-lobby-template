local definitions = {}
local timers = {}
local named_events = {}
local numeric_events = {}
local errors = {}
local MOCK_GENERATED_EVENT_ID = 246813579

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, message)
    if not value then
        error(message)
    end
end

local function new_definition(name)
    local definition = {}
    function definition:with_param()
        return self
    end
    function definition:with_return()
        return self
    end
    function definition:call(callback)
        definitions[name] = callback
        return self
    end
    return definition
end

y3 = {
    helper = {
        py_dict = function(value)
            return value or {}
        end,
    },
    json = {
        encode = function()
            return '{}'
        end,
    },
    game = {
        get_current_game_mode = function()
            return 1001
        end,
        send_custom_event = function(event_id, payload)
            numeric_events[#numeric_events + 1] = { id = event_id, payload = payload }
        end,
    },
    const = {
        CustomEventName = {
            ['大厅服务请求完成'] = MOCK_GENERATED_EVENT_ID,
        },
    },
    ctimer = {
        wait = function(_, callback)
            local timer = { callback = callback }
            function timer:remove()
                self.removed = true
            end
            timers[#timers + 1] = timer
            return timer
        end,
    },
    eca = {
        def = new_definition,
        call = function(name, payload)
            named_events[#named_events + 1] = { name = name, payload = payload }
        end,
    },
    player = {
        with_local = function()
        end,
    },
}

GameAPI = {}
log = {
    error = function(message)
        errors[#errors + 1] = tostring(message)
    end,
}
MatchTestIsBattleContext = function()
    return false
end
MatchTestLocalPrivate = function()
    return true
end
MatchTestReturnLobby = function()
    return true
end
MatchTestJoinPrivateDungeon = function()
    return true
end

_G.__ECA_LOBBY_API_RUNTIME = nil
local api = dofile('maps/EntryMap/script/pub/eca_lobby_api.lua')

assert_equal(api.EVENT_ID, 1876423410, 'configured event fallback id')

local ok, result = pcall(api.create_private_dungeon)
assert_equal(ok, true, 'name event delivery must not escape')
assert_equal(result.accepted, true, 'name event request accepted')
assert_equal(#named_events, 1, 'name event count')
assert_equal(#numeric_events, 0, 'numeric fallback must not run after name delivery')
assert_equal(named_events[1].name, api.EVENT_NAME, 'name event name')
assert_equal(named_events[1].payload.request_id, result.request_id, 'name event request id')
assert_equal(named_events[1].payload.success, true, 'name event success')

y3.eca.call = function()
    error('name channel unavailable')
end
ok, result = pcall(api.return_lobby)
assert_equal(ok, true, 'numeric fallback must not escape')
assert_equal(result.accepted, true, 'numeric fallback request accepted')
assert_equal(#numeric_events, 1, 'numeric fallback event count')
assert_equal(numeric_events[1].id, MOCK_GENERATED_EVENT_ID, 'dynamic numeric fallback id')
assert_equal(
    numeric_events[1].payload[api.EVENT_PARAM_NAME].request_id,
    result.request_id,
    'numeric fallback request id')

y3.game.send_custom_event = function()
    error('numeric channel unavailable')
end
ok, result = pcall(api.return_lobby)
assert_equal(ok, true, 'dual event failure must not escape')
assert_equal(result.accepted, true, 'dual failure request remains accepted')
local failed = _G.__ECA_LOBBY_API_RUNTIME.failed_events[result.request_id]
assert_true(failed ~= nil, 'dual failure diagnostic record')
assert_equal(failed.payload.action, '返回大厅', 'dual failure diagnostic action')
assert_true(failed.error:find('按名称事件通道失败', 1, true) ~= nil, 'name failure diagnostic')
assert_true(failed.error:find('按编号事件通道失败', 1, true) ~= nil, 'numeric failure diagnostic')
assert_true(#errors > 0, 'dual failure must be logged')
assert_equal(_G.__ECA_LOBBY_API_RUNTIME.pending[result.request_id], nil, 'dual failure request cleanup')

y3.const.CustomEventName = {
    [api.EVENT_NAME] = 0,
}
y3.game.send_custom_event = function(event_id, payload)
    numeric_events[#numeric_events + 1] = { id = event_id, payload = payload }
end
ok, result = pcall(api.join_private_dungeon, 'space-123')
assert_equal(ok, true, 'missing event metadata must not escape')
assert_equal(result.accepted, true, 'missing event metadata request accepted')
failed = _G.__ECA_LOBBY_API_RUNTIME.failed_events[result.request_id]
assert_equal(failed, nil, 'configured fallback must deliver without generated metadata')
assert_equal(#numeric_events, 2, 'configured fallback event count')
assert_equal(numeric_events[2].id, api.EVENT_ID, 'configured fallback event id')
assert_equal(
    numeric_events[2].payload[api.EVENT_PARAM_NAME].request_id,
    result.request_id,
    'configured fallback request id')
assert_equal(api.get_state().result_event_id, api.EVENT_ID, 'state exposes configured fallback id')

y3.const.CustomEventName = nil
ok, result = pcall(api.create_private_dungeon)
assert_equal(ok, true, 'nil event metadata table must not escape')
assert_equal(result.accepted, true, 'nil event metadata request accepted')
failed = _G.__ECA_LOBBY_API_RUNTIME.failed_events[result.request_id]
assert_equal(failed, nil, 'nil metadata table must use configured fallback')
assert_equal(#numeric_events, 3, 'nil metadata fallback event count')
assert_equal(numeric_events[3].id, api.EVENT_ID, 'nil metadata fallback event id')
assert_equal(
    numeric_events[3].payload[api.EVENT_PARAM_NAME].request_id,
    result.request_id,
    'nil metadata fallback request id')

print('eca_lobby_api_event_spike_test: PASS')
