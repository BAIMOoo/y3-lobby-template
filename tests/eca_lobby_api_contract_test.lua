local candidate_roots = {}
local configured_root = os.getenv('Y3_LUALIB_ROOT')
if configured_root and configured_root ~= '' then
    candidate_roots[#candidate_roots + 1] = configured_root
end
candidate_roots[#candidate_roots + 1] = '.omx/worktrees/y3-lualib-lobby'

local root
for _, candidate in ipairs(candidate_roots) do
    local file = io.open(candidate .. '/game/lobby/init.lua', 'rb')
    if file then
        file:close()
        root = candidate
        break
    end
end
assert(root, 'lobby module root not found; set Y3_LUALIB_ROOT to a y3-lualib checkout')

package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. root .. '/game/?.lua;' .. root .. '/game/?/init.lua;' .. package.path

TEST_GAME_PLAY_ID = 10190356

local expected_eca_names = {
    '大厅服务 - 建立连接',
    '大厅服务 - 获取连接状态',
    '大厅服务 - 设置匹配分数',
    '大厅服务 - 创建队伍',
    '大厅服务 - 加入队伍',
    '大厅服务 - 离开队伍',
    '大厅服务 - 解散队伍',
    '大厅服务 - 转移队长',
    '大厅服务 - 移出队员',
    '大厅服务 - 获取队伍成员',
    '大厅服务 - 开始匹配',
    '大厅服务 - 取消匹配',
    '大厅服务 - 发送队伍聊天',
    '大厅服务 - 发送世界聊天',
    '大厅服务 - 获取聊天记录',
    '大厅服务 - 同房分流',
    '大厅服务 - 跨房合流',
    '大厅服务 - 加入口令',
    '大厅服务 - 获取口令',
    '大厅服务 - 返回大厅',
    '大厅服务 - 退出游戏',
    '大厅服务 - 获取状态快照',
    '大厅服务 - 获取聊天消息',
    '大厅服务 - 获取队伍成员项',
    '大厅服务 - 获取队伍信息',
    '大厅服务 - 获取玩家信息',
    '大厅服务 - 刷新玩家信息',
}

local expected_lua_functions = {
    'connect',
    'on_event',
    'get_connection_status',
    'set_score',
    'create_team',
    'join_team',
    'leave_team',
    'dismiss_team',
    'change_captain',
    'kick_member',
    'get_members',
    'get_member',
    'start_match',
    'cancel_match',
    'send_team_chat',
    'send_world_chat',
    'get_chat_history',
    'get_chat_message',
    'same_room_split',
    'cross_room_merge',
    'join_by_token',
    'get_token',
    'return_lobby',
    'exit_game',
    'request_state',
    'get_state',
    'get_team_info',
    'get_player_info',
    'refresh_player_info',
}

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_true(value, message)
    if not value then
        error(message, 2)
    end
end

local function read_file(path)
    local file = assert(io.open(path, 'rb'), path)
    local content = file:read('*a')
    file:close()
    return content
end

local function contains_bare_print_call(source)
    return source:find('^%s*print%s*%(') ~= nil
        or source:find('[^%w_%.:]print%s*%(') ~= nil
end

local function file_exists(path)
    local file = io.open(path, 'rb')
    if file then
        file:close()
        return true
    end
    return false
end

local function table_size(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local searchers = package.searchers or package.loaders
table.insert(searchers, 1, function(name)
    local prefix = 'y3.game.lobby'
    if name ~= prefix and name:sub(1, #prefix + 1) ~= prefix .. '.' then
        return nil
    end
    local suffix = name == prefix and 'init' or name:sub(#prefix + 2):gsub('%.', '/')
    local lua_path = root .. '/game/lobby/' .. suffix .. '.lua'
    if file_exists(lua_path) then
        return function()
            return dofile(lua_path)
        end
    end
    local init_path = root .. '/game/lobby/' .. suffix .. '/init.lua'
    if file_exists(init_path) then
        return function()
            return dofile(init_path)
        end
    end
    return nil
end)

assert_true(file_exists(root .. '/game/lobby/init.lua'), 'official lobby public module must exist')
assert_true(file_exists(root .. '/game/lobby/eca.lua'), 'official lobby ECA module must exist')
assert_true(file_exists(root .. '/game/lobby/result.lua'), 'official lobby result module must exist')
assert_true(file_exists(root .. '/game/lobby/state.lua'), 'official lobby state module must exist')
assert_true(file_exists(root .. '/game/lobby/client.lua'), 'official lobby client module must exist')
assert_true(file_exists(root .. '/game/lobby/proto/service.pb'), 'official lobby service.pb must exist')

local root_init_source = read_file(root .. '/init.lua')
local eca_init_pos = root_init_source:find('eca', 1, true) or 0
local lobby_export_pos = root_init_source:find('lobby', 1, true)
assert_true(lobby_export_pos ~= nil, 'root init.lua must expose or load y3.lobby')
assert_true(lobby_export_pos > eca_init_pos, 'root init.lua must load lobby after y3.eca initialization')

local registered = {}
local io_open_calls = {}
local pb_load_calls = 0
local network_handler_calls = 0
local client_factory_calls = 0

local real_io_open = io.open
io.open = function(path, mode)
    io_open_calls[#io_open_calls + 1] = tostring(path)
    return real_io_open(path, mode)
end

pb = {
    load = function()
        pb_load_calls = pb_load_calls + 1
        return true
    end,
}

GameAPI = {
    get_current_game_mode = function()
        return 1001
    end,
}

log = {
    error = function() end,
    warn = function() end,
    info = function() end,
}

local function new_definition(name)
    local definition = {
        name = name,
        params = {},
        returns = {},
    }
    function definition:with_param(param_name, param_type)
        self.params[#self.params + 1] = { name = param_name, type = param_type }
        return self
    end
    function definition:with_return(return_name, return_type)
        self.returns[#self.returns + 1] = { name = return_name, type = return_type }
        return self
    end
    function definition:call(callback)
        self.callback = callback
        registered[self.name] = self
        return self
    end
    return definition
end

y3 = {
    eca = {
        def = new_definition,
        call = function()
            error('init-time must not send completion events')
        end,
    },
    game = {
        get_current_game_mode = GameAPI.get_current_game_mode,
    },
    json = {
        encode = function()
            return '{}'
        end,
    },
}

BOB = {
    create_client = function()
        client_factory_calls = client_factory_calls + 1
        return {}
    end,
}

_G.__Y3_LOBBY_TEST_PROBES = {
    on_create_client = function()
        client_factory_calls = client_factory_calls + 1
    end,
    on_create_network_handler = function()
        network_handler_calls = network_handler_calls + 1
    end,
}

local ok, result = pcall(require, 'game.lobby.init')
assert_true(ok, tostring(result))
y3.lobby = y3.lobby or result

local eca_ok, eca_result = pcall(require, 'game.lobby.eca')
assert_true(eca_ok, tostring(eca_result))
if table_size(registered) == 0 then
    if type(eca_result) == 'function' then
        eca_result()
    elseif type(eca_result) == 'table' and type(eca_result.register) == 'function' then
        eca_result.register()
    elseif type(eca_result) == 'table' and type(eca_result.init) == 'function' then
        eca_result.init()
    end
end
io.open = real_io_open
assert_true(type(y3.lobby) == 'table', 'game.lobby.init must expose y3.lobby-compatible table')

assert_equal(table_size(registered), #expected_eca_names, 'registered ECA function count')
for _, name in ipairs(expected_eca_names) do
    local definition = registered[name]
    assert_true(definition ~= nil, 'missing ECA function: ' .. name)
    assert_equal(#definition.returns, 1, name .. ' return count')
    assert_equal(definition.returns[1].type, 'table', name .. ' return type')
end

local eca_definitions = eca_result.get_definitions and eca_result.get_definitions() or {}
local eca_by_action = {}
for _, definition in ipairs(eca_definitions) do
    eca_by_action[definition[2]] = definition
end

local function assert_eca_params(action, expected)
    local definition = eca_by_action[action]
    assert_true(definition ~= nil, 'missing ECA definition for action: ' .. action)
    local params = definition[4] or {}
    assert_equal(#params, #expected, action .. ' parameter count')
    for index, expected_param in ipairs(expected) do
        assert_equal(params[index][1], expected_param[1], action .. ' parameter name #' .. index)
        assert_equal(params[index][2], expected_param[2], action .. ' parameter type #' .. index)
    end
end

local expected_eca_params = {
    ['建立连接'] = { { '玩法ID', 'integer' }, { '是否在游戏关卡', 'boolean?' } },
    ['获取连接状态'] = {},
    ['设置匹配分数'] = { { '分数', 'integer' } },
    ['创建队伍'] = { { '人数上限', 'integer' } },
    ['加入队伍'] = { { '队伍编号', 'integer' } },
    ['离开队伍'] = {},
    ['解散队伍'] = {},
    ['转移队长'] = { { '目标AID', 'integer' } },
    ['移出队员'] = { { '目标AID', 'integer' } },
    ['获取队伍成员'] = {},
    ['开始匹配'] = { { '匹配参数', 'table' } },
    ['取消匹配'] = {},
    ['发送队伍聊天'] = { { '消息', 'string' } },
    ['发送世界聊天'] = { { '消息', 'string' } },
    ['获取聊天记录'] = { { '频道', 'string?' } },
    ['获取聊天消息'] = { { '序号', 'integer' }, { '频道', 'string?' } },
    ['同房分流'] = { { '分流参数', 'table' } },
    ['跨房合流'] = { { '合流参数', 'table' } },
    ['加入口令'] = { { '口令', 'string' } },
    ['获取口令'] = {},
    ['返回大厅'] = { { '大厅参数', 'table' } },
    ['退出游戏'] = {},
    ['获取状态快照'] = {},
    ['获取队伍成员项'] = { { '序号', 'integer' } },
    ['获取队伍信息'] = { { '目标AID', 'integer?' } },
    ['获取玩家信息'] = { { '目标AID', 'integer?' } },
    ['刷新玩家信息'] = {},
}
for action, params in pairs(expected_eca_params) do
    assert_eca_params(action, params)
end

assert_true(registered['大厅服务 - 重建大厅连接'] == nil, 'old rebuild alias must not be an official ECA function')
assert_true(registered['大厅服务 - 创建私人副本'] == nil, 'old private dungeon name must not be official')
assert_true(registered['大厅服务 - 启动多人私人副本'] == nil, 'old private dungeon name must not be official')
assert_true(registered['大厅服务 - 加入口令副本'] == nil, 'old private dungeon name must not be official')
assert_true(registered['大厅服务 - 获取副本口令'] == nil, 'old private dungeon name must not be official')

for _, function_name in ipairs(expected_lua_functions) do
    assert_equal(type(y3.lobby[function_name]), 'function', 'missing y3.lobby.' .. function_name)
end

assert_equal(client_factory_calls, 0, 'lobby module registration must not create BOB client')
assert_equal(pb_load_calls, 0, 'lobby module registration must not call pb.load')
assert_equal(network_handler_calls, 0, 'lobby module registration must not create network handler')
for _, path in ipairs(io_open_calls) do
    assert_true(not path:find('custom/protocol/protocol.pb', 1, true), 'lobby module registration must not read project protocol.pb')
    assert_true(not path:find('game/lobby/proto/service.pb', 1, true), 'lobby module registration must not read service.pb')
end

local function assert_result_shape(value, action)
    assert_equal(type(value), 'table', action .. ' result type')
    assert_equal(value.action, action, action .. ' action')
    assert_equal(type(value.accepted), 'boolean', action .. ' accepted type')
    assert_equal(type(value.reason), 'string', action .. ' reason type')
    assert_equal(type(value.code), 'string', action .. ' code type')
    assert_true(value.request_id == nil or type(value.request_id) == 'string', action .. ' request_id type')
    assert_equal(type(value.sync), 'boolean', action .. ' sync type')
    assert_equal(type(value.result_data), 'table', action .. ' result_data type')
end

local rejected = y3.lobby.create_team()
assert_result_shape(rejected, '创建队伍')
assert_equal(rejected.accepted, false, 'unconnected business request accepted')
assert_equal(rejected.code, 'not_connected', 'unconnected business request code')
assert_equal(client_factory_calls, 0, 'business request must not implicitly connect')

local unconnected_platform_requests = {}
local unconnected_exit_game_calls = 0
local unconnected_frame_callbacks = {}
local unconnected_completions = {}
local unconnected_listener = y3.lobby.on_complete(function(payload)
    unconnected_completions[#unconnected_completions + 1] = payload
end)
y3.ctimer = {
    wait_frame = function(_, callback)
        unconnected_frame_callbacks[#unconnected_frame_callbacks + 1] = callback
        return { remove = function() end }
    end,
}
y3.player = {
    with_local = function(callback)
        callback({
            handle = {
                request_create_private_dungeon = function(_, level_id, game_mode, max_player, custom_param)
                    unconnected_platform_requests[#unconnected_platform_requests + 1] = {
                        level_id = level_id,
                        game_mode = game_mode,
                        max_player = max_player,
                        custom_param = custom_param,
                    }
                end,
            },
            exit_game = function()
                unconnected_exit_game_calls = unconnected_exit_game_calls + 1
            end,
        })
    end,
}
local unconnected_return_lobby = y3.lobby.return_lobby({
    level_id = 'unconnected-lobby',
    game_mode = 1101,
    max_player = 8,
    custom_param = 'unconnected-param',
})
assert_result_shape(unconnected_return_lobby, unconnected_return_lobby.action)
assert_equal(unconnected_return_lobby.accepted, true, 'return_lobby should execute without lobby connection')
assert_equal(client_factory_calls, 0, 'return_lobby without connection must not implicitly connect')
assert_equal(#unconnected_platform_requests, 1, 'return_lobby without connection should call platform request')
assert_equal(unconnected_platform_requests[1].level_id, 'unconnected-lobby', 'return_lobby without connection forwards level_id')
assert_equal(unconnected_platform_requests[1].custom_param, 'unconnected-param', 'return_lobby without connection forwards custom_param')
if #unconnected_frame_callbacks > 0 then
    unconnected_frame_callbacks[#unconnected_frame_callbacks]()
    assert_equal(unconnected_completions[#unconnected_completions].request_id, unconnected_return_lobby.request_id, 'return_lobby without connection completion request_id')
end

local before_unconnected_exit_completions = #unconnected_completions
local before_unconnected_exit_frames = #unconnected_frame_callbacks
local unconnected_exit_game = y3.lobby.exit_game()
assert_result_shape(unconnected_exit_game, unconnected_exit_game.action)
assert_equal(unconnected_exit_game.accepted, true, 'exit_game should execute without lobby connection')
assert_equal(client_factory_calls, 0, 'exit_game without connection must not implicitly connect')
assert_equal(unconnected_exit_game_calls, 0, 'exit_game without connection should publish completion before engine exit')
assert_equal(#unconnected_frame_callbacks >= before_unconnected_exit_frames + 1, true, 'exit_game without connection should schedule completion frame')
unconnected_frame_callbacks[before_unconnected_exit_frames + 1]()
assert_equal(#unconnected_completions, before_unconnected_exit_completions + 1, 'exit_game without connection should publish completion')
assert_equal(unconnected_completions[#unconnected_completions].request_id, unconnected_exit_game.request_id, 'exit_game without connection completion request_id')
assert_equal(unconnected_exit_game_calls, 0, 'exit_game without connection should not exit in completion frame')
assert_equal(#unconnected_frame_callbacks >= before_unconnected_exit_frames + 2, true, 'exit_game without connection should schedule actual exit frame')
unconnected_frame_callbacks[before_unconnected_exit_frames + 2]()
assert_equal(unconnected_exit_game_calls, 1, 'exit_game without connection should call engine exit exactly once')
unconnected_listener.remove()

local status = y3.lobby.get_connection_status()
assert_result_shape(status, '获取连接状态')
assert_equal(status.accepted, true, 'status query accepted')
assert_true(status.result_data.status == 'idle' or type(status.result_data.status) == 'string', 'status query exposes status')

local source = read_file(root .. '/game/lobby/init.lua')
assert_true(not source:find('connect%s*%([^%)]*options', 1), 'connect(options) must not be public API')
assert_true(not source:find('force%s*=', 1), 'connect force option must not be public API')

local lobby_source = ''
for _, path in ipairs({
    root .. '/game/lobby/init.lua',
    root .. '/game/lobby/client.lua',
    root .. '/game/lobby/eca.lua',
    root .. '/game/lobby/state.lua',
    root .. '/game/lobby/result.lua',
}) do
    lobby_source = lobby_source .. '\n' .. read_file(path)
end
assert_true(lobby_source:find('"2.0"', 1, true) or lobby_source:find("'2.0'", 1, true), 'player version must be internal constant 2.0')
assert_true(lobby_source:find('event_missing', 1, true), 'event_missing must be represented')
assert_true(lobby_source:find('failed_events', 1, true), 'failed_events must be represented')

local proto_source = read_file(root .. '/game/lobby/proto/proto_helper.lua')
assert_true(proto_source:find('custom/protocol/protocol.pb', 1, true), 'project protocol.pb must be loaded only by connect-time protocol helper')
assert_true(proto_source:find('game/lobby/proto/service.pb', 1, true), 'service.pb must be explicitly loaded as an internal module resource')

local official_lobby_source = ''
for _, path in ipairs({
    root .. '/game/lobby/bob.lua',
    root .. '/game/lobby/client.lua',
    root .. '/game/lobby/proto/proto_helper.lua',
    root .. '/game/lobby/service/client.lua',
    root .. '/game/lobby/network/message_handler.lua',
}) do
    official_lobby_source = official_lobby_source .. '\n' .. read_file(path)
end
assert_true(not official_lobby_source:find("Class 'Client'", 1, true), "official lobby module must not register global Class 'Client'")
assert_true(not official_lobby_source:find('Class "Client"', 1, true), 'official lobby module must not register global Class "Client"')
assert_true(not official_lobby_source:find("Class 'Bob'", 1, true), "official lobby module must not register global Class 'Bob'")
assert_true(not official_lobby_source:find('Class "Bob"', 1, true), 'official lobby module must not register global Class "Bob"')
assert_true(not official_lobby_source:find("Class 'ProtoHelper'", 1, true), "official lobby module must not register global Class 'ProtoHelper'")
assert_true(not official_lobby_source:find('Class "ProtoHelper"', 1, true), 'official lobby module must not register global Class "ProtoHelper"')
assert_true(not official_lobby_source:find("Class 'message_handler'", 1, true), "official lobby module must not register global Class 'message_handler'")
assert_true(not official_lobby_source:find('Class("message_handler")', 1, true), 'official lobby module must not register global Class("message_handler")')
assert_true(not official_lobby_source:find('Class "message_handler"', 1, true), 'official lobby module must not register global Class "message_handler"')
assert_true(official_lobby_source:find("Class 'LobbyBob'", 1, true) ~= nil, "official lobby module must register Class 'LobbyBob'")
assert_true(
    official_lobby_source:find("Extends('LobbyBob', 'CustomEvent')", 1, true) ~= nil
        or official_lobby_source:find("Extends('LobbyBob','CustomEvent')", 1, true) ~= nil
        or official_lobby_source:find('Extends("LobbyBob", "CustomEvent")', 1, true) ~= nil
        or official_lobby_source:find('Extends("LobbyBob","CustomEvent")', 1, true) ~= nil,
    "LobbyBob must extend CustomEvent"
)
assert_true(
    official_lobby_source:find("Extends('LobbyBob', 'GCHost')", 1, true) ~= nil
        or official_lobby_source:find("Extends('LobbyBob','GCHost')", 1, true) ~= nil
        or official_lobby_source:find('Extends("LobbyBob", "GCHost")', 1, true) ~= nil
        or official_lobby_source:find('Extends("LobbyBob","GCHost")', 1, true) ~= nil,
    "LobbyBob must extend GCHost"
)
assert_true(not official_lobby_source:find("New 'Bob'", 1, true), "official lobby module must not instantiate old New 'Bob'")
assert_true(official_lobby_source:find("New 'LobbyBob'", 1, true) ~= nil or official_lobby_source:find('New "LobbyBob"', 1, true) ~= nil, 'New class name must match LobbyBob')
assert_true(official_lobby_source:find("Class 'LobbyMessageHandler'", 1, true) ~= nil or official_lobby_source:find('Class("LobbyMessageHandler")', 1, true) ~= nil or official_lobby_source:find('Class "LobbyMessageHandler"', 1, true) ~= nil, 'official lobby module must register LobbyMessageHandler')
assert_true(not official_lobby_source:find("New 'message_handler'", 1, true), "official lobby module must not instantiate old New 'message_handler'")
assert_true(not official_lobby_source:find('New "message_handler"', 1, true), 'official lobby module must not instantiate old New "message_handler"')
assert_true(official_lobby_source:find("New 'LobbyMessageHandler'", 1, true) ~= nil or official_lobby_source:find('New "LobbyMessageHandler"', 1, true) ~= nil, 'New class name must match LobbyMessageHandler')
do
    local official_service_client_source = read_file(root .. '/game/lobby/service/client.lua')
    assert_true(not official_service_client_source:find('printTable', 1, true), 'official service client must not contain printTable')
    assert_true(not contains_bare_print_call(official_service_client_source), 'official service client must not contain bare print calls')
end

local client_api = require 'y3.game.lobby.client'
local state_api = require 'y3.game.lobby.state'
local completion_payloads = {}
local emitted_events = {}
local timeout_callbacks = {}
local frame_callbacks = {}
local timeout_timers = {}
local frame_timers = {}
local factory_calls = 0
local latest_client
local private_dungeon_requests = {}
local join_private_dungeon_requests = {}
local exit_game_calls = 0

y3.ctimer = {
    wait = function(delay, callback)
        timeout_callbacks[#timeout_callbacks + 1] = callback
        local timer = {
            delay = delay,
            removed = false,
            remove = function(self)
                self.removed = true
            end,
        }
        timeout_timers[#timeout_timers + 1] = timer
        return timer
    end,
    wait_frame = function(_, callback)
        frame_callbacks[#frame_callbacks + 1] = callback
        local timer = {
            removed = false,
            remove = function(self)
                self.removed = true
            end,
        }
        frame_timers[#frame_timers + 1] = timer
        return timer
    end,
}

local function new_fake_client()
    local fake = {
        aid = 9001 + factory_calls,
        ready = false,
        event_handlers = {},
        event_order = {},
        remove_count = 0,
        create_team_calls = 0,
        set_score_calls = 0,
        refresh_player_info_calls = 0,
        join_team_calls = 0,
        leave_team_calls = 0,
        dismiss_team_calls = 0,
        change_captain_calls = 0,
        kick_member_calls = 0,
        cancel_match_calls = 0,
        send_chat_calls = 0,
        send_world_chat_calls = 0,
        start_match_calls = 0,
        cross_room_payloads = {},
    }

    function fake:is_valid()
        return self.ready
    end

    function fake:event_on(event_name, callback)
        self.event_handlers[event_name] = self.event_handlers[event_name] or {}
        if #self.event_handlers[event_name] == 0 then
            self.event_order[#self.event_order + 1] = event_name
        end
        self.event_handlers[event_name][#self.event_handlers[event_name] + 1] = callback
        return {
            remove = function()
                fake.remove_count = fake.remove_count + 1
            end,
        }
    end

    function fake:emit(event_name, ...)
        for _, callback in ipairs(self.event_handlers[event_name] or {}) do
            callback(nil, ...)
        end
    end

    function fake:is_in_team()
        return self.team_info ~= nil
    end

    function fake:is_captain()
        return self.team_info and self.team_info.captain == self.aid
    end

    function fake:is_matching()
        return self.matching == true
    end

    function fake:is_launching()
        return self.launching == true
    end

    function fake:get_team_info(aid, callback)
        self.get_team_info_calls = (self.get_team_info_calls or 0) + 1
        self.last_get_team_info_aid = aid
        self.get_team_info_callback = callback
        return true
    end

    function fake:get_player_info(aid, callback)
        self.get_player_info_calls = (self.get_player_info_calls or 0) + 1
        self.last_get_player_info_aid = aid
        self.get_player_info_callback = callback
        return true
    end

    function fake:refresh_player_info(callback)
        self.refresh_player_info_calls = self.refresh_player_info_calls + 1
        self.refresh_player_info_callback = callback
        return true
    end

    function fake:can_match()
        return true
    end

    function fake:create_team(callback, member_limit)
        self.create_team_calls = self.create_team_calls + 1
        self.last_member_limit = member_limit
        self.create_team_callback = callback
        return true
    end

    function fake:set_score(score, callback)
        self.set_score_calls = self.set_score_calls + 1
        self.refresh_player_info_calls = self.refresh_player_info_calls + 1
        self.score = score
        self.set_score_callback = callback
        return true
    end

    function fake:join_team(team_id, callback)
        self.join_team_calls = self.join_team_calls + 1
        self.last_team_id = team_id
        self.join_team_callback = callback
        return true
    end

    function fake:leave_team(callback)
        self.leave_team_calls = self.leave_team_calls + 1
        self.leave_team_callback = callback
        return true
    end

    function fake:dismiss_team(callback)
        self.dismiss_team_calls = self.dismiss_team_calls + 1
        self.dismiss_team_callback = callback
        return true
    end

    function fake:change_captain(target_aid, callback)
        self.change_captain_calls = self.change_captain_calls + 1
        self.last_target_aid = target_aid
        self.change_captain_callback = callback
        return true
    end

    function fake:team_kick(target_aid, callback)
        self.kick_member_calls = self.kick_member_calls + 1
        self.last_kicked_aid = target_aid
        self.kick_member_callback = callback
        return true
    end

    function fake:start_match(game_mode, score, callback)
        self.start_match_calls = self.start_match_calls + 1
        self.last_match = { game_mode = game_mode, score = score }
        self.start_match_callback = callback
        return true
    end

    function fake:cancel_match(callback)
        self.cancel_match_calls = self.cancel_match_calls + 1
        self.cancel_match_callback = callback
        return true
    end

    function fake:send_chat(message, callback)
        self.send_chat_calls = self.send_chat_calls + 1
        self.last_team_message = message
        self.send_chat_callback = callback
        return true
    end

    function fake:send_world_chat(message, callback)
        self.send_world_chat_calls = self.send_world_chat_calls + 1
        self.last_world_message = message
        self.send_world_chat_callback = callback
        return true
    end

    function fake:start_privat_dungeon_game(dungeon_info, players, callback)
        self.cross_room_payloads[#self.cross_room_payloads + 1] = {
            dungeon_info = dungeon_info,
            players = players,
        }
        self.cross_room_callback = callback
        return true
    end

    function fake:cleanup_before_exit(callback)
        self.cleanup_before_exit_calls = (self.cleanup_before_exit_calls or 0) + 1
        self.cleanup_before_exit_callback = callback
        if self.cleanup_before_exit_error then
            error(self.cleanup_before_exit_error)
        end
        if self.cleanup_before_exit_returns_false then
            return false
        end
        if self.cleanup_before_exit_immediate ~= nil then
            callback(self.cleanup_before_exit_immediate, self.cleanup_before_exit_code)
        end
        return true
    end

    return fake
end

local function reset_lobby_with_factory(factory)
    completion_payloads = {}
    emitted_events = {}
    timeout_callbacks = {}
    frame_callbacks = {}
    timeout_timers = {}
    frame_timers = {}
    private_dungeon_requests = {}
    join_private_dungeon_requests = {}
    exit_game_calls = 0
    if y3.lobby._reset_for_test then
        y3.lobby._reset_for_test()
    end
    client_api._set_factory_for_test(factory)
    y3.lobby.on_complete(function(payload)
        completion_payloads[#completion_payloads + 1] = payload
    end)
end

first_factory_game_play_id = nil
first_factory_in_game = nil
reset_lobby_with_factory(function(game_play_id, in_game)
    first_factory_game_play_id = game_play_id
    first_factory_in_game = in_game
    factory_calls = factory_calls + 1
    latest_client = new_fake_client()
    return latest_client
end)

local eca_runtime_lobby = require 'y3.game.lobby'
local eca_runtime_completion_listener = eca_runtime_lobby.on_complete(function(payload)
    completion_payloads[#completion_payloads + 1] = payload
end)
local connect_result = eca_runtime_lobby.connect(TEST_GAME_PLAY_ID)
assert_result_shape(connect_result, '建立连接')
assert_equal(connect_result.accepted, true, 'connect should be accepted')
assert_equal(first_factory_game_play_id, TEST_GAME_PLAY_ID, 'connect must pass required game_play_id to client factory')
assert_equal(first_factory_in_game, false, 'connect should default in_game to false')
assert_equal(connect_result.sync, false, 'connect should complete asynchronously when client is not ready yet')
assert_equal(#completion_payloads, 0, 'connect must not report completion before ready callback')
local duplicate_connect = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(duplicate_connect.duplicate, true, 'duplicate connect should reuse pending request')
assert_equal(factory_calls, 1, 'duplicate connect must not create a second client')
emitted_events = {}
y3.eca._call_impls = { [eca_result.EVENT_NAME] = true }
y3.eca.call = function(event_name, payload)
    emitted_events[#emitted_events + 1] = { event_name = event_name, payload = payload }
    return true
end
local eca_duplicate_connect = registered[expected_eca_names[1]].callback(TEST_GAME_PLAY_ID)
assert_equal(eca_duplicate_connect.accepted, true, 'ECA duplicate connect should be accepted')
assert_equal(eca_duplicate_connect.duplicate, true, 'ECA duplicate connect should reuse pending request')
assert_equal(eca_duplicate_connect.request_id, connect_result.request_id, 'ECA duplicate connect request_id should match Lua pending request')
assert_equal(state_api.runtime.eca_request_ids[connect_result.request_id], true, 'ECA duplicate connect should mark Lua pending request for ECA completion')
assert_equal(factory_calls, 1, 'ECA duplicate connect must not create a second client')
local pending_business_result = y3.lobby.create_team(4)
assert_equal(pending_business_result.accepted, false, 'business request while connecting should be rejected synchronously')
assert_equal(pending_business_result.code, 'connection_pending', 'business request while connecting code')
latest_client.ready = true
latest_client:emit('准备就绪')
assert_equal(#completion_payloads, 1, 'connect ready should publish one completion payload')
assert_equal(completion_payloads[1].success, true, 'connect ready completion success')
assert_equal(#emitted_events, 1, 'ECA duplicate connect should publish one completion event when Lua pending request finishes')
assert_equal(emitted_events[1].event_name, eca_result.EVENT_NAME, 'ECA duplicate connect completion event name')
assert_equal(emitted_events[1].payload.request_id, connect_result.request_id, 'ECA duplicate connect completion request_id')
assert_equal(state_api.runtime.eca_request_ids[connect_result.request_id], nil, 'ECA duplicate connect marker should be cleared after completion event')
eca_runtime_completion_listener.remove()
assert_equal(y3.lobby.get_connection_status().result_data.status, 'connected', 'ready callback updates connection status')

do
    lobby_events = {}
    all_lobby_events = {}
    connection_listener = y3.lobby.on_event('connection_changed', function(payload)
        lobby_events[#lobby_events + 1] = payload
    end)
    all_listener = y3.lobby.on_event(function(payload)
        all_lobby_events[#all_lobby_events + 1] = payload
    end)

    connected_status_event = latest_client.event_order[3]
    assert_equal(type(connected_status_event), 'string', 'connected client status event is registered')
    latest_client:emit(connected_status_event, 'disconnect')
    assert_equal(y3.lobby.get_connection_status().result_data.status, 'disconnected', 'connected client disconnect updates status')
    disconnected_event_payload = lobby_events[#lobby_events]
    assert_equal(type(disconnected_event_payload), 'table', 'connection_changed payload should be stable table')
    assert_equal(disconnected_event_payload.event, 'connection_changed', 'connection_changed payload event')
    assert_equal(disconnected_event_payload.source, 'lobby', 'connection_changed payload source')
    assert_equal(disconnected_event_payload.status, 'disconnected', 'connection_changed payload status')
    assert_equal(type(disconnected_event_payload.sequence), 'number', 'connection_changed payload sequence')
    assert_equal(type(disconnected_event_payload.snapshot), 'table', 'connection_changed payload snapshot')
    disconnected_event_count = #lobby_events
    state_api.set_status('disconnected', 'updated diagnostic only')
    assert_equal(#lobby_events, disconnected_event_count, 'same connection status must not notify again when only reason changes')
    assert_equal(y3.lobby.get_state().result_data.last_error, 'updated diagnostic only', 'same connection status reason updates snapshot last_error')

    failed_event_count_before_listener_error = table_size(y3.lobby.get_state().result_data.failed_events)
    failing_event_listener = y3.lobby.on_event('connection_changed', function()
        error('ordinary listener failed')
    end)
    state_api.set_status('failed', 'listener failure probe')
    failed_events_after_listener_error = y3.lobby.get_state().result_data.failed_events
    failed_event_count_after_listener_error = table_size(failed_events_after_listener_error)
    for _, failed_event in pairs(failed_events_after_listener_error) do
        if failed_event.payload and failed_event.payload.event == 'connection_changed' then
            assert_equal(tostring(failed_event.error):find('ordinary listener failed', 1, true) ~= nil, true, 'ordinary on_event listener error is recorded')
        end
    end
    assert_equal(failed_event_count_after_listener_error, failed_event_count_before_listener_error + 1, 'ordinary on_event listener failure writes failed_events')
    failing_event_listener.remove()
    state_api.set_status('disconnected', 'listener removed probe')
    assert_equal(table_size(y3.lobby.get_state().result_data.failed_events), failed_event_count_after_listener_error, 'removed failing on_event listener no longer affects events')

    team_event_payload = nil
    team_listener = y3.lobby.on_event('team_changed', function(payload)
        team_event_payload = payload
    end)
    raw_team_event = {
        team_id = 7001,
        member_limit = 4,
        captain = latest_client.aid,
        team_state = '空闲',
        version = 1,
        internal_token = 'must-not-leak',
        members = {
            { aid = latest_client.aid, name = 'captain', internal_token = 'member-secret' },
        },
    }
    latest_client:emit('队伍变化', raw_team_event)
    assert_equal(team_event_payload.data.team == raw_team_event, false, 'team_changed must copy public data')
    assert_equal(team_event_payload.data.team.internal_token, nil, 'team_changed must hide internal team fields')
    assert_equal(team_event_payload.data.team.members[1].internal_token, nil, 'team_changed must hide internal member fields')
    team_listener.remove()

    message_event_payload = nil
    message_listener = y3.lobby.on_event('message_received', function(payload)
        message_event_payload = payload
    end)
    raw_message_event = {
        mode = '聊天',
        time = 123,
        message = 'hello',
        type = 4,
        chat = {
            sender = { aid = latest_client.aid, nickname = 'captain', head_icon = 'icon' },
            internal_token = 'chat-secret',
        },
    }
    latest_client:emit('收到消息', raw_message_event)
    assert_equal(message_event_payload.data.message == raw_message_event, false, 'message_received must copy public data')
    assert_equal(message_event_payload.data.message.chat, nil, 'message_received must hide internal chat fields')
    assert_equal(message_event_payload.data.message.sender.aid, latest_client.aid, 'message_received keeps public sender fields')
    message_listener.remove()

    removed_event_count = #lobby_events
    connection_listener.remove()
    latest_client:emit(connected_status_event, 'login')
    assert_equal(#lobby_events, removed_event_count, 'removed event listener must not receive events')
    assert_equal(all_lobby_events[#all_lobby_events].event, 'connection_changed', 'all-event listener receives filtered-out event')
    all_listener.remove()

    in_game_factory_value = nil
    reset_lobby_with_factory(function(_, in_game)
        in_game_factory_value = in_game
        factory_calls = factory_calls + 1
        latest_client = new_fake_client()
        return latest_client
    end)
    in_game_connect = y3.lobby.connect(TEST_GAME_PLAY_ID, true)
    assert_equal(in_game_connect.accepted, true, 'connect with in_game true should be accepted')
    assert_equal(in_game_factory_value, true, 'connect forwards in_game boolean to client factory')
    reset_lobby_with_factory(function(_, in_game)
        in_game_factory_value = in_game
        factory_calls = factory_calls + 1
        latest_client = new_fake_client()
        return latest_client
    end)
    invalid_in_game_connect = y3.lobby.connect(TEST_GAME_PLAY_ID, { in_game = true })
    assert_equal(invalid_in_game_connect.accepted, false, 'connect options table must be rejected')
    assert_equal(invalid_in_game_connect.code, 'invalid_argument', 'connect options table rejection code')
end

do
reset_lobby_with_factory(function()
    factory_calls = factory_calls + 1
    latest_client = new_fake_client()
    return latest_client
end)
local reconnect_after_disconnect = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(reconnect_after_disconnect.accepted, true, 'reconnect after disconnect should be accepted')
latest_client.ready = true
latest_client:emit(latest_client.event_order[1])
assert_equal(y3.lobby.get_connection_status().result_data.status, 'connected', 'reconnect after disconnect restores connected status')

assert_equal(y3.lobby.leave_team().code, 'not_in_team', 'leave_team local error code')
assert_equal(y3.lobby.dismiss_team().code, 'not_in_team', 'dismiss_team local error code')
assert_equal(y3.lobby.cancel_match().code, 'not_matching', 'cancel_match local error code')
assert_equal(y3.lobby.send_team_chat('hello').code, 'not_in_team', 'send_team_chat local error code')
latest_client.team_info = {
    team_id = 7002,
    captain = 99001,
    members = {
        { aid = latest_client.aid },
        { aid = 99001 },
    },
}
assert_equal(y3.lobby.dismiss_team().code, 'not_captain', 'dismiss_team captain error code')
assert_equal(y3.lobby.change_captain(99002).code, 'not_captain', 'change_captain captain error code')
latest_client.team_info.captain = latest_client.aid
assert_equal(y3.lobby.change_captain(99002).code, 'member_not_found', 'change_captain member error code')
assert_equal(y3.lobby.kick_member(99002).code, 'member_not_found', 'kick_member member error code')
latest_client.matching = true
assert_equal(y3.lobby.join_team(7003).code, 'state_conflict', 'join_team state error code')
assert_equal(y3.lobby.leave_team().code, 'state_conflict', 'leave_team state error code')
latest_client.matching = false
latest_client.team_info = nil

local sync_reject_cases = {
    { name = 'set_score invalid argument', call = function() return y3.lobby.set_score('bad') end, code = 'invalid_argument' },
    { name = 'join_team invalid argument', call = function() return y3.lobby.join_team(0) end, code = 'invalid_argument' },
    { name = 'change_captain invalid argument', call = function() return y3.lobby.change_captain(nil) end, code = 'invalid_argument' },
    { name = 'kick_member invalid argument', call = function() return y3.lobby.kick_member(nil) end, code = 'invalid_argument' },
    { name = 'start_match invalid argument', call = function() return y3.lobby.start_match({ game_mode = 1 }) end, code = 'invalid_argument' },
    { name = 'send_team_chat invalid argument', call = function() return y3.lobby.send_team_chat('  ') end, code = 'invalid_argument' },
    { name = 'send_world_chat invalid argument', call = function() return y3.lobby.send_world_chat('  ') end, code = 'invalid_argument' },
    { name = 'same_room_split invalid argument', call = function() return y3.lobby.same_room_split({ level_id = 'x' }) end, code = 'invalid_argument' },
    { name = 'cross_room_merge invalid argument', call = function() return y3.lobby.cross_room_merge({ game_map_id = 'm', level_id = 'l', game_mode = 1 }) end, code = 'invalid_argument' },
    { name = 'join_by_token invalid argument', call = function() return y3.lobby.join_by_token(' ') end, code = 'invalid_argument' },
    { name = 'return_lobby invalid argument', call = function() return y3.lobby.return_lobby({ level_id = 'l' }) end, code = 'invalid_argument' },
}
for _, case in ipairs(sync_reject_cases) do
    local value = case.call()
    assert_result_shape(value, value.action)
    assert_equal(value.accepted, false, case.name .. ' accepted')
    assert_equal(value.code, case.code, case.name .. ' code')
    assert_equal(value.sync, true, case.name .. ' sync')
end

local sync_query_cases = {
    { name = 'get_connection_status', result = y3.lobby.get_connection_status() },
    { name = 'get_members', result = y3.lobby.get_members() },
    { name = 'get_chat_history', result = y3.lobby.get_chat_history() },
    { name = 'get_token', result = y3.lobby.get_token() },
    { name = 'request_state', result = y3.lobby.request_state() },
    { name = 'get_state', result = y3.lobby.get_state() },
}
for _, case in ipairs(sync_query_cases) do
    assert_result_shape(case.result, case.result.action)
    assert_equal(case.result.accepted, true, case.name .. ' accepted')
    assert_equal(case.result.sync, true, case.name .. ' sync')
end

local score_result = y3.lobby.set_score(1200)
assert_equal(score_result.accepted, true, 'set_score should be accepted')
assert_equal(latest_client.score, 1200, 'set_score forwards score')
assert_equal(latest_client.refresh_player_info_calls, 1, 'set_score refreshes player info')
latest_client.set_score_callback(nil, nil)
assert_equal(completion_payloads[#completion_payloads].request_id, score_result.request_id, 'set_score completion request_id')
assert_equal(completion_payloads[#completion_payloads].result_data.score, 1200, 'set_score completion data')

local before_create_team_count = #completion_payloads
local create_team_result = y3.lobby.create_team(4)
assert_result_shape(create_team_result, '创建队伍')
assert_equal(create_team_result.accepted, true, 'create_team should be accepted when connected')
assert_equal(#completion_payloads, before_create_team_count, 'create_team must not complete before callback and state confirmation')
latest_client.create_team_callback(nil, nil)
assert_equal(#completion_payloads, before_create_team_count, 'create_team RPC success alone must not complete before team state changes')
latest_client.team_info = {
    team_id = 12345,
    captain = latest_client.aid,
    members = { { aid = latest_client.aid } },
}
latest_client:emit('队伍变化')
assert_equal(#completion_payloads, before_create_team_count + 1, 'create_team should complete after state confirmation')
assert_equal(completion_payloads[#completion_payloads].success, true, 'create_team completion success')
assert_equal(table_size(y3.lobby.get_state().result_data.failed_events), 0, 'pure Lua on_complete requests must not write failed_events when ECA completion event is missing')

local join_team_result = y3.lobby.join_team(345)
assert_equal(join_team_result.accepted, true, 'join_team should be accepted')
assert_equal(latest_client.last_team_id, 345, 'join_team forwards team_id')
latest_client.join_team_callback(nil, nil)
latest_client.team_info.team_id = 345
latest_client:emit('队伍变化')
assert_equal(completion_payloads[#completion_payloads].request_id, join_team_result.request_id, 'join_team completion request_id')

latest_client.team_info = {
    team_id = 345,
    captain = latest_client.aid,
    members = { { aid = latest_client.aid }, { aid = 99006 }, { aid = 99007 } },
}
local change_captain_result = y3.lobby.change_captain(99006)
assert_equal(change_captain_result.accepted, true, 'change_captain should be accepted')
assert_equal(latest_client.last_target_aid, 99006, 'change_captain forwards target aid')
latest_client.change_captain_callback(nil, nil)
latest_client.team_info.captain = 99006
latest_client:emit('队伍变化')
assert_equal(completion_payloads[#completion_payloads].request_id, change_captain_result.request_id, 'change_captain completion request_id')

latest_client.team_info.captain = latest_client.aid
local kick_member_result = y3.lobby.kick_member(99007)
assert_equal(kick_member_result.accepted, true, 'kick_member should be accepted')
assert_equal(latest_client.last_kicked_aid, 99007, 'kick_member forwards target aid')
latest_client.kick_member_callback(nil, nil)
latest_client.team_info.members = { { aid = latest_client.aid }, { aid = 99006 } }
latest_client:emit('队伍变化')
assert_equal(completion_payloads[#completion_payloads].request_id, kick_member_result.request_id, 'kick_member completion request_id')

local dismiss_result = y3.lobby.dismiss_team()
assert_equal(dismiss_result.accepted, true, 'dismiss_team should be accepted')
latest_client.dismiss_team_callback(nil, nil)
latest_client.team_info = nil
latest_client:emit('离开队伍')
assert_equal(completion_payloads[#completion_payloads].request_id, dismiss_result.request_id, 'dismiss_team completion request_id')

latest_client.team_info = {
    team_id = 456,
    captain = latest_client.aid,
    members = { { aid = latest_client.aid } },
}
local leave_result = y3.lobby.leave_team()
assert_equal(leave_result.accepted, true, 'leave_team should be accepted')
latest_client.leave_team_callback(nil, nil)
latest_client.team_info = nil
latest_client:emit('离开队伍')
assert_equal(completion_payloads[#completion_payloads].request_id, leave_result.request_id, 'leave_team completion request_id')

local match_missing_mode = y3.lobby.start_match({ game_mode = 3002 })
assert_equal(match_missing_mode.accepted, false, 'start_match without level_id must be rejected')
assert_equal(match_missing_mode.code, 'invalid_argument', 'start_match without level_id rejection code')
local match_result = y3.lobby.start_match({ level_id = 'target-level', game_mode = 3002 })
assert_equal(match_result.accepted, true, 'start_match requires level_id and game_mode and allows nil score')
assert_equal(latest_client.level_id, 'target-level', 'start_match forwards target level_id')
assert_equal(latest_client.last_match.game_mode, 3002, 'start_match forwards game_mode')
assert_equal(latest_client.last_match.score, nil, 'start_match keeps score optional')
latest_client.start_match_callback(nil, nil)
latest_client.matching = true
latest_client:emit('匹配状态变化')
assert_equal(completion_payloads[#completion_payloads].request_id, match_result.request_id, 'start_match should complete before the next operation-locked request')
latest_client.matching = false

latest_client.matching = true
latest_client.team_info = nil
local cancel_match_result = y3.lobby.cancel_match()
assert_equal(cancel_match_result.accepted, true, 'cancel_match should be accepted while matching')
latest_client.cancel_match_callback(nil, nil)
latest_client.matching = false
latest_client:emit('匹配状态变化')
assert_equal(completion_payloads[#completion_payloads].request_id, cancel_match_result.request_id, 'cancel_match completion request_id')

latest_client.team_info = {
    team_id = 346,
    captain = latest_client.aid,
    members = { { aid = latest_client.aid } },
}
local team_chat_result = y3.lobby.send_team_chat(' team hi ')
assert_equal(team_chat_result.accepted, true, 'send_team_chat should be accepted')
assert_equal(latest_client.last_team_message, 'team hi', 'send_team_chat trims and forwards message')
latest_client.send_chat_callback(nil, nil)
assert_equal(completion_payloads[#completion_payloads].request_id, team_chat_result.request_id, 'send_team_chat completion request_id')

local merge_result = y3.lobby.cross_room_merge({
    game_map_id = 'map-alpha',
    level_id = 'level-beta',
    game_mode = 7003,
    players = { { aid = 11 }, { aid = 12 } },
})
assert_equal(merge_result.accepted, true, 'cross_room_merge should accept required payload')
assert_equal(latest_client.cross_room_payloads[1].players[1].version, '2.0', 'cross_room_merge injects internal player version')
assert_equal(latest_client.cross_room_payloads[1].players[2].version, '2.0', 'cross_room_merge injects internal player version for each player')
latest_client.cross_room_callback(nil, nil)
latest_client.launching = true
latest_client:emit('启动状态变化')
latest_client.launching = false

y3.player = {
    with_local = function(callback)
        callback({
            handle = {
                request_create_private_dungeon = function(_, level_id, game_mode, max_player, custom_param)
                    private_dungeon_requests[#private_dungeon_requests + 1] = {
                        level_id = level_id,
                        game_mode = game_mode,
                        max_player = max_player,
                        custom_param = custom_param,
                    }
                end,
                request_join_private_dungeon = function(_, token)
                    join_private_dungeon_requests[#join_private_dungeon_requests + 1] = token
                end,
            },
            exit_game = function()
                exit_game_calls = exit_game_calls + 1
            end,
        })
    end,
}

local function connect_ready_with_cleanup(config)
    reset_lobby_with_factory(function()
        factory_calls = factory_calls + 1
        latest_client = new_fake_client()
        return latest_client
    end)
    local connected = y3.lobby.connect(TEST_GAME_PLAY_ID)
    assert_equal(connected.accepted, true, 'cleanup scenario connect should be accepted')
    latest_client.ready = true
    latest_client:emit('准备就绪')
    for key, value in pairs(config or {}) do
        latest_client[key] = value
    end
end

local function find_timer_by_delay(delay)
    for index = #timeout_timers, 1, -1 do
        if timeout_timers[index].delay == delay then
            return timeout_timers[index], timeout_callbacks[index]
        end
    end
    return nil, nil
end

local function assert_latest_cleanup(code, ok, attempted, message)
    local payload = completion_payloads[#completion_payloads]
    assert_equal(type(payload.result_data.cleanup), 'table', message .. ' cleanup diagnostic exists')
    assert_equal(payload.result_data.cleanup.code, code, message .. ' cleanup code')
    assert_equal(payload.result_data.cleanup.ok, ok, message .. ' cleanup ok')
    assert_equal(payload.result_data.cleanup.attempted, attempted, message .. ' cleanup attempted')
end

local function setup_pending_connect()
    reset_lobby_with_factory(function()
        factory_calls = factory_calls + 1
        latest_client = new_fake_client()
        return latest_client
    end)
    local result = y3.lobby.connect(TEST_GAME_PLAY_ID)
    assert_equal(result.accepted, true, 'pending connect setup should be accepted')
    assert_equal(result.sync, false, 'pending connect setup should be async')
    assert_equal(#completion_payloads, 0, 'pending connect setup should not complete before terminal')
    assert_equal(type(latest_client), 'table', 'pending connect setup should create fake client')
    return result, latest_client, timeout_callbacks[#timeout_callbacks]
end

function assert_sync_invalid_without_platform(call, message)
    local requests_before = #private_dungeon_requests
    local status_before = y3.lobby.get_state().result_data.status
    local result_value = call()
    assert_result_shape(result_value, result_value.action)
    assert_equal(result_value.accepted, false, message .. ' accepted')
    assert_equal(result_value.code, 'invalid_argument', message .. ' code')
    assert_equal(result_value.sync, true, message .. ' sync')
    assert_equal(#private_dungeon_requests, requests_before, message .. ' no platform request')
    local snapshot = y3.lobby.get_state().result_data
    assert_equal(snapshot.pending_count, 0, message .. ' no pending request')
    assert_equal(snapshot.status, status_before, message .. ' status unchanged')
end

local function emit_client_event(client, order_index, ...)
    local event_name = client.event_order[order_index]
    assert_equal(type(event_name), 'string', 'expected fake client event #' .. tostring(order_index))
    client:emit(event_name, ...)
end

local function emit_late_connect_callbacks(client, connect_timeout_callback)
    emit_client_event(client, 1)
    emit_client_event(client, 3, 'login')
    emit_client_event(client, 3, 'disconnect')
    emit_client_event(client, 2, 'service unavailable')
    if connect_timeout_callback then
        connect_timeout_callback()
    end
end

local function assert_completion(payload, request_id, action, success, code, message)
    assert_equal(type(payload), 'table', message .. ' completion payload')
    assert_equal(payload.request_id, request_id, message .. ' request_id')
    assert_equal(payload.action, action, message .. ' action')
    assert_equal(payload.success, success, message .. ' success')
    assert_equal(payload.code, code, message .. ' code')
end

local terminal_params = {
    level_id = 'cycle3-terminal-lobby',
    game_mode = 9401,
    max_player = 8,
}

terminal_lock_params = {
    level_id = 'cycle4-terminal-locked-lobby',
    game_mode = 9402,
    max_player = 8,
}

function assert_terminal_locked(result, message)
    assert_equal(type(result), 'table', message .. ' result')
    assert_equal(result.accepted, false, message .. ' accepted')
    assert_equal(result.code, 'terminal_locked', message .. ' code')
end

function assert_exit_terminal_settled(exit_result, completion_count_before, exit_calls_before, message)
    local count = 0
    for _, payload in ipairs(completion_payloads) do
        if payload.request_id == exit_result.request_id and payload.code == 'ok' then
            count = count + 1
        end
    end
    assert_equal(count, 1, message .. ' completion once')
    assert_equal(#completion_payloads, completion_count_before + 1, message .. ' no extra completions')
    assert_equal(exit_game_calls, exit_calls_before, message .. ' actual exit not in completion frame')
    assert_equal(#frame_callbacks, 1, message .. ' actual exit scheduled for next frame')
    frame_callbacks[1]()
    assert_equal(exit_game_calls, exit_calls_before + 1, message .. ' actual exit once')
    for index = 2, #frame_callbacks do
        frame_callbacks[index]()
    end
    assert_equal(exit_game_calls, exit_calls_before + 1, message .. ' no duplicate exit')
    assert_equal(y3.lobby.get_state().result_data.status, 'idle', message .. ' final idle')
end

connect_ready_with_cleanup({})
assert_sync_invalid_without_platform(function()
    return y3.lobby.return_lobby(nil)
end, 'return_lobby nil params')
assert_sync_invalid_without_platform(function()
    return y3.lobby.return_lobby('bad')
end, 'return_lobby non-table params')
assert_sync_invalid_without_platform(function()
    return y3.lobby.return_lobby({ level_id = '  ', game_mode = 9403, max_player = 2 })
end, 'return_lobby empty level_id')
assert_sync_invalid_without_platform(function()
    return y3.lobby.return_lobby({ level_id = 'invalid-mode', game_mode = 9403.5, max_player = 2 })
end, 'return_lobby non-integer game_mode')
assert_sync_invalid_without_platform(function()
    return y3.lobby.return_lobby({ level_id = 'invalid-max-player', game_mode = 9403, max_player = 0 })
end, 'return_lobby non-positive max_player')
assert_sync_invalid_without_platform(function()
    return y3.lobby.same_room_split({ level_id = 'split-invalid-players', game_mode = 9404, max_player = 2, players = 'bad' })
end, 'same_room_split players non-table')
assert_sync_invalid_without_platform(function()
    return y3.lobby.same_room_split({ level_id = 'split-invalid-player-entry', game_mode = 9404, max_player = 2, players = { 10086 } })
end, 'same_room_split player entry non-table')
assert_sync_invalid_without_platform(function()
    return y3.lobby.same_room_split({ level_id = 'split-invalid-aid', game_mode = 9404, max_player = 2, players = { { aid = 10086.5 } } })
end, 'same_room_split player aid non-integer')
split_all_before_requests = #private_dungeon_requests
split_all_players = y3.lobby.same_room_split({
    level_id = 'split-all-players',
    game_mode = 9404,
    max_player = 2,
    players = {},
})
assert_equal(split_all_players.accepted, true, 'same_room_split empty players means no filtering')
assert_equal(#private_dungeon_requests, split_all_before_requests + 1, 'same_room_split empty players calls platform')
assert_equal(private_dungeon_requests[#private_dungeon_requests].level_id, 'split-all-players', 'same_room_split empty players forwards level_id')

reset_lobby_with_factory(function()
    factory_calls = factory_calls + 1
    latest_client = new_fake_client()
    return latest_client
end)
y3.eca._call_impls = { [eca_result.EVENT_NAME] = true }
y3.eca.call = function(event_name, payload)
    emitted_events[#emitted_events + 1] = { event_name = event_name, payload = payload }
    return true
end
local eca_pending_completion_listener = eca_runtime_lobby.on_complete(function(payload)
    completion_payloads[#completion_payloads + 1] = payload
end)
local eca_pending_connect = registered[expected_eca_names[1]].callback(TEST_GAME_PLAY_ID)
local eca_pending_client = latest_client
local eca_pending_timeout_callback = timeout_callbacks[#timeout_callbacks]
local eca_return_result = registered[expected_eca_names[20]].callback(terminal_params)
assert_equal(eca_return_result.accepted, true, 'ECA return_lobby should accept while connect is pending')
assert_completion(completion_payloads[1], eca_pending_connect.request_id, eca_pending_connect.action, false, 'cancelled_by_terminal', 'pending ECA connect cancelled by return_lobby')
assert_equal(emitted_events[1].payload.request_id, eca_pending_connect.request_id, 'ECA pending connect cancellation should emit completion event')
assert_equal(state_api.runtime.eca_request_ids[eca_pending_connect.request_id], nil, 'ECA pending connect marker should be cleared by cancellation completion listener')
assert_equal(eca_pending_client.cleanup_before_exit_calls or 0, 0, 'return_lobby must not cleanup half-initialized pending connect client')
assert_equal(#frame_callbacks > 0, true, 'return_lobby terminal completion should defer when starter completes synchronously')
frame_callbacks[1]()
assert_equal(completion_payloads[#completion_payloads].request_id, eca_return_result.request_id, 'return_lobby completion should follow connect cancellation')
local after_eca_return_completion_count = #completion_payloads
emit_late_connect_callbacks(eca_pending_client, eca_pending_timeout_callback)
assert_equal(#completion_payloads, after_eca_return_completion_count, 'late ready/login/disconnect/unavailable/timeout after return_lobby must not complete again')
assert_equal(y3.lobby.get_connection_status().result_data.status ~= 'connected', true, 'late pending connect callbacks after return_lobby must not restore connected status')
eca_pending_completion_listener.remove()

local pending_exit_connect, pending_exit_client, pending_exit_timeout_callback = setup_pending_connect()
local exit_from_pending = y3.lobby.exit_game()
assert_equal(exit_from_pending.accepted, true, 'exit_game should accept while connect is pending')
assert_completion(completion_payloads[1], pending_exit_connect.request_id, pending_exit_connect.action, false, 'cancelled_by_terminal', 'pending connect cancelled by exit_game')
assert_equal(exit_game_calls, 0, 'exit_game pending connect should not exit before terminal completion')
assert_equal(#frame_callbacks > 0, true, 'exit_game pending connect should schedule terminal completion')
frame_callbacks[1]()
assert_equal(completion_payloads[#completion_payloads].request_id, exit_from_pending.request_id, 'exit_game completion should follow connect cancellation')
assert_equal(exit_game_calls, 0, 'exit_game pending connect should publish completion before next-frame engine exit')
assert_equal(#frame_callbacks > 1, true, 'exit_game pending connect should schedule actual exit after completion')
frame_callbacks[2]()
assert_equal(exit_game_calls, 1, 'exit_game pending connect should exit exactly once on next frame')
local after_pending_exit_completion_count = #completion_payloads
emit_late_connect_callbacks(pending_exit_client, pending_exit_timeout_callback)
assert_equal(#completion_payloads, after_pending_exit_completion_count, 'late pending connect callbacks after exit_game must be no-op')
assert_equal(y3.lobby.get_connection_status().result_data.status ~= 'connected', true, 'late pending connect callbacks after exit_game must not restore connected status')

connect_ready_with_cleanup({})
local connected_client_for_terminal = latest_client
local terminal_factory_before = factory_calls
local pending_operation = y3.lobby.create_team(4)
local pending_chat = y3.lobby.send_world_chat('terminal chat')
assert_equal(pending_operation.accepted, true, 'operation pending setup should be accepted')
assert_equal(pending_chat.accepted, true, 'chat pending setup should be accepted')
local completions_before_terminal_while_pending = #completion_payloads
local terminal_while_pending = y3.lobby.return_lobby(terminal_params)
assert_equal(terminal_while_pending.accepted, true, 'terminal should bypass operation/chat locks')
assert_completion(completion_payloads[completions_before_terminal_while_pending + 1], pending_operation.request_id, pending_operation.action, false, 'cancelled_by_terminal', 'pending operation cancelled by terminal')
assert_completion(completion_payloads[completions_before_terminal_while_pending + 2], pending_chat.request_id, pending_chat.action, false, 'cancelled_by_terminal', 'pending chat cancelled by terminal')
assert_equal(#completion_payloads, completions_before_terminal_while_pending + 2, 'terminal must wait for cleanup after cancelling operation/chat')
connected_client_for_terminal.cleanup_before_exit_callback(true, nil)
assert_equal(completion_payloads[#completion_payloads].request_id, terminal_while_pending.request_id, 'terminal completion should follow old request cancellations')
local completion_count_after_terminal = #completion_payloads
connected_client_for_terminal.create_team_callback(nil, nil)
connected_client_for_terminal.team_info = {
    team_id = 551,
    captain = connected_client_for_terminal.aid,
    members = { { aid = connected_client_for_terminal.aid } },
}
connected_client_for_terminal:emit('队伍变化')
connected_client_for_terminal.send_world_chat_callback(nil, nil)
emit_client_event(connected_client_for_terminal, 3, 'disconnect')
assert_equal(#completion_payloads, completion_count_after_terminal, 'late RPC/state callbacks after terminal cancellation must be no-op')
assert_equal(factory_calls, terminal_factory_before, 'terminal cancellation of pending operation/chat must not create a client')

local reentrant_connect_result
local reentrant_connect, reentrant_client, reentrant_timeout_callback = setup_pending_connect()
local reentrant_listener = y3.lobby.on_complete(function(payload)
    if payload.code == 'cancelled_by_terminal' then
        reentrant_connect_result = y3.lobby.connect(TEST_GAME_PLAY_ID)
    end
end)
local reentrant_factory_before = factory_calls
local reentrant_return = y3.lobby.return_lobby(terminal_params)
assert_equal(reentrant_return.accepted, true, 'return_lobby should accept pending connect before reentrant listener assertion')
assert_equal(reentrant_connect_result.accepted, false, 'connect reentered inside cancellation listener should reject')
assert_equal(reentrant_connect_result.code, 'connection_closing', 'connect reentered inside cancellation listener code')
assert_equal(factory_calls, reentrant_factory_before, 'reentrant connect during terminal cancellation must not create client')
reentrant_listener.remove()
emit_late_connect_callbacks(reentrant_client, reentrant_timeout_callback)

connect_ready_with_cleanup({ cleanup_before_exit_returns_false = true })
local terminal_in_progress = y3.lobby.return_lobby(terminal_params)
assert_equal(terminal_in_progress.accepted, true, 'return_lobby delayed cleanup should be accepted')
assert_equal(y3.lobby.get_connection_status().result_data.status, 'closing', 'terminal enters closing status')
latest_client:emit('准备就绪')
assert_equal(y3.lobby.get_connection_status().result_data.status, 'closing', 'late ready must not restore connected during terminal cleanup')
emit_client_event(latest_client, 3, 'login')
assert_equal(y3.lobby.get_connection_status().result_data.status, 'closing', 'late login must not restore connected during terminal cleanup')
local operation_during_terminal = y3.lobby.create_team(4)
assert_equal(operation_during_terminal.accepted, false, 'business request during terminal should be rejected')
assert_equal(operation_during_terminal.code, 'terminal_in_progress', 'business request during terminal code')
local query_during_terminal = y3.lobby.get_token()
assert_equal(query_during_terminal.accepted, false, 'query request during terminal should be rejected')
assert_equal(query_during_terminal.code, 'terminal_in_progress', 'query request during terminal code')
local second_terminal = y3.lobby.exit_game()
assert_equal(second_terminal.accepted, false, 'second terminal during terminal should be rejected')
assert_equal(second_terminal.code, 'terminal_locked', 'second terminal during terminal code')

do
    connect_ready_with_cleanup({})
    local listener_lock_client = latest_client
    local listener_lock_results
    local listener_lock_exit = y3.lobby.exit_game()
    local listener_lock_completion_count_before = #completion_payloads
    local listener_lock_exit_calls_before = exit_game_calls
    local listener_lock = y3.lobby.on_complete(function(payload)
        if payload.request_id == listener_lock_exit.request_id then
            listener_lock_results = {
                return_lobby = y3.lobby.return_lobby(terminal_lock_params),
                return_lobby_nil = y3.lobby.return_lobby(nil),
                exit_game = y3.lobby.exit_game(),
            }
        end
    end)
    assert_equal(listener_lock_exit.accepted, true, 'exit_game before completion listener reentry should be accepted')
    listener_lock_client.cleanup_before_exit_callback(true, nil)
    assert_equal(type(listener_lock_results), 'table', 'completion listener should reenter terminal requests')
    assert_terminal_locked(listener_lock_results.return_lobby, 'return_lobby reentered in completion listener')
    assert_terminal_locked(listener_lock_results.return_lobby_nil, 'return_lobby nil reentered in completion listener')
    assert_terminal_locked(listener_lock_results.exit_game, 'exit_game reentered in completion listener')
    assert_equal(#private_dungeon_requests, 0, 'completion listener reentry must not call platform return')
    listener_lock.remove()
    assert_exit_terminal_settled(listener_lock_exit, listener_lock_completion_count_before, listener_lock_exit_calls_before, 'completion listener terminal lock')
end

do
    connect_ready_with_cleanup({})
    local same_frame_client = latest_client
    local same_frame_exit = y3.lobby.exit_game()
    local same_frame_completion_count_before = #completion_payloads
    local same_frame_exit_calls_before = exit_game_calls
    assert_equal(same_frame_exit.accepted, true, 'exit_game before same-frame reentry should be accepted')
    same_frame_client.cleanup_before_exit_callback(true, nil)
    assert_terminal_locked(y3.lobby.return_lobby(terminal_lock_params), 'return_lobby after completion before exit frame')
    assert_terminal_locked(y3.lobby.return_lobby(nil), 'return_lobby nil after completion before exit frame')
    assert_terminal_locked(y3.lobby.exit_game(), 'exit_game after completion before exit frame')
    assert_equal(#private_dungeon_requests, 0, 'same-frame terminal reentry must not call platform return')
    assert_exit_terminal_settled(same_frame_exit, same_frame_completion_count_before, same_frame_exit_calls_before, 'same-frame terminal lock')
end

connect_ready_with_cleanup({})
local platform_fail_client = latest_client
y3.player = {
    with_local = function(callback)
        callback({
            handle = {
                request_create_private_dungeon = function()
                    error('platform return failed')
                end,
            },
        })
    end,
}
local platform_fail_return = y3.lobby.return_lobby(terminal_params)
assert_equal(platform_fail_return.accepted, true, 'return_lobby platform failure should be accepted before cleanup')
platform_fail_client.cleanup_before_exit_callback(true, nil)
assert_equal(completion_payloads[#completion_payloads].request_id, platform_fail_return.request_id, 'return_lobby platform failure completion request_id')
assert_equal(completion_payloads[#completion_payloads].success, false, 'return_lobby platform failure completion success')
assert_equal(y3.lobby.get_connection_status().result_data.status ~= 'connected', true, 'return_lobby platform failure should leave runtime non-connected')
assert_equal(state_api.runtime.client, nil, 'return_lobby platform failure should clear runtime client')

connect_ready_with_cleanup({})
local missing_player_client = latest_client
y3.player = {
    with_local = function(callback)
        callback(nil)
    end,
}
local missing_player_return = y3.lobby.return_lobby(terminal_params)
assert_equal(missing_player_return.accepted, true, 'return_lobby missing player should be accepted before cleanup')
missing_player_client.cleanup_before_exit_callback(true, nil)
assert_equal(completion_payloads[#completion_payloads].code, 'local_player_missing', 'return_lobby missing player completion code')
assert_equal(y3.lobby.get_connection_status().result_data.status ~= 'connected', true, 'return_lobby missing player should leave runtime non-connected')
assert_equal(state_api.runtime.client, nil, 'return_lobby missing player should clear runtime client')

y3.player = {
    with_local = function(callback)
        callback({
            handle = {
                request_create_private_dungeon = function(_, level_id, game_mode, max_player, custom_param)
                    private_dungeon_requests[#private_dungeon_requests + 1] = {
                        level_id = level_id,
                        game_mode = game_mode,
                        max_player = max_player,
                        custom_param = custom_param,
                    }
                end,
                request_join_private_dungeon = function(_, token)
                    join_private_dungeon_requests[#join_private_dungeon_requests + 1] = token
                end,
            },
            exit_game = function()
                exit_game_calls = exit_game_calls + 1
            end,
        })
    end,
}

connect_ready_with_cleanup({ cleanup_before_exit_immediate = true })
local delayed_factory_before = factory_calls
local delayed_completion_count = #completion_payloads
local delayed_return = y3.lobby.return_lobby(terminal_params)
assert_equal(delayed_return.accepted, true, 'return_lobby delayed completion window setup should be accepted')
assert_equal(#completion_payloads, delayed_completion_count, 'return_lobby synchronous cleanup should defer terminal completion')
local connect_during_delayed_completion_window = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(connect_during_delayed_completion_window.accepted, false, 'connect during return_lobby completion next-frame window should reject')
assert_equal(connect_during_delayed_completion_window.code, 'connection_closing', 'connect during return_lobby completion next-frame window code')
assert_equal(factory_calls, delayed_factory_before, 'connect during return_lobby completion next-frame window must not create client')
frame_callbacks[1]()
assert_equal(completion_payloads[#completion_payloads].request_id, delayed_return.request_id, 'return_lobby delayed completion window should publish terminal completion')

connect_ready_with_cleanup({})
local before_return_cleanup_requests = #private_dungeon_requests
local before_return_cleanup_completions = #completion_payloads
local return_cleanup_success = y3.lobby.return_lobby({
    level_id = 'return-cleanup-ok',
    game_mode = 903,
    max_player = 8,
    custom_param = 'cleanup-ok-param',
})
local return_cleanup_request_timer = timeout_timers[#timeout_timers]
assert_equal(return_cleanup_success.accepted, true, 'return_lobby cleanup success should be accepted')
assert_equal(#private_dungeon_requests, before_return_cleanup_requests, 'return_lobby must not request platform before cleanup callback')
assert_equal(#completion_payloads, before_return_cleanup_completions, 'return_lobby must not complete before cleanup callback')
assert_equal(type(latest_client.cleanup_before_exit_callback), 'function', 'return_lobby should wait for cleanup callback when connected')
latest_client.cleanup_before_exit_callback(true, nil)
assert_equal(#private_dungeon_requests, before_return_cleanup_requests + 1, 'return_lobby cleanup success should request platform once')
assert_equal(#completion_payloads, before_return_cleanup_completions + 1, 'return_lobby cleanup success should complete once')
assert_equal(private_dungeon_requests[#private_dungeon_requests].level_id, 'return-cleanup-ok', 'return_lobby cleanup success forwards level_id')
assert_equal(completion_payloads[#completion_payloads].request_id, return_cleanup_success.request_id, 'return_lobby cleanup success completion request_id')
assert_latest_cleanup('ok', true, true, 'return_lobby cleanup success')
assert_equal(return_cleanup_request_timer.removed, true, 'return_lobby cleanup success removes request timer')
latest_client.cleanup_before_exit_callback(true, nil)
assert_equal(#private_dungeon_requests, before_return_cleanup_requests + 1, 'return_lobby repeated cleanup callback must not request platform twice')
assert_equal(#completion_payloads, before_return_cleanup_completions + 1, 'return_lobby repeated cleanup callback must not complete twice')

connect_ready_with_cleanup({})
local before_return_failed_requests = #private_dungeon_requests
local before_return_failed_completions = #completion_payloads
local return_cleanup_failed = y3.lobby.return_lobby({
    level_id = 'return-cleanup-failed',
    game_mode = 904,
    max_player = 8,
})
assert_equal(return_cleanup_failed.accepted, true, 'return_lobby cleanup failure should still be accepted')
assert_equal(#private_dungeon_requests, before_return_failed_requests, 'return_lobby cleanup failure should wait for callback before platform request')
latest_client.cleanup_before_exit_callback(false, 'cleanup_failed')
assert_equal(#private_dungeon_requests, before_return_failed_requests + 1, 'return_lobby cleanup failure should still request platform')
assert_equal(#completion_payloads, before_return_failed_completions + 1, 'return_lobby cleanup failure should still complete')
assert_latest_cleanup('cleanup_failed', false, true, 'return_lobby cleanup failure')

connect_ready_with_cleanup({ cleanup_before_exit_error = 'cleanup exploded' })
local before_return_exception_requests = #private_dungeon_requests
local before_return_exception_completions = #completion_payloads
local return_cleanup_exception = y3.lobby.return_lobby({
    level_id = 'return-cleanup-exception',
    game_mode = 905,
    max_player = 8,
})
assert_equal(return_cleanup_exception.accepted, true, 'return_lobby cleanup exception should be converted to accepted platform request')
assert_equal(#private_dungeon_requests, before_return_exception_requests + 1, 'return_lobby cleanup exception should still request platform')
if #completion_payloads == before_return_exception_completions and #frame_callbacks > 0 then
    frame_callbacks[#frame_callbacks]()
end
assert_equal(#completion_payloads, before_return_exception_completions + 1, 'return_lobby cleanup exception should still complete')
assert_latest_cleanup('cleanup_exception', false, true, 'return_lobby cleanup exception')

connect_ready_with_cleanup({ cleanup_before_exit_returns_false = true })
local before_return_delayed_requests = #private_dungeon_requests
local before_return_delayed_completions = #completion_payloads
local return_cleanup_delayed = y3.lobby.return_lobby({
    level_id = 'return-cleanup-delayed',
    game_mode = 906,
    max_player = 8,
})
local cleanup_watchdog_timer, cleanup_watchdog_callback = find_timer_by_delay(8)
local request_timeout_timer = find_timer_by_delay(10)
assert_equal(return_cleanup_delayed.accepted, true, 'return_lobby cleanup false should be accepted')
assert_equal(#private_dungeon_requests, before_return_delayed_requests, 'return_lobby cleanup false must wait for delayed callback or watchdog')
assert_equal(#completion_payloads, before_return_delayed_completions, 'return_lobby cleanup false must not complete immediately')
assert_equal(type(cleanup_watchdog_callback), 'function', 'return_lobby cleanup false should install cleanup watchdog')
assert_equal(type(request_timeout_timer), 'table', 'return_lobby should keep request timeout timer')
assert_equal(cleanup_watchdog_timer.delay < request_timeout_timer.delay, true, 'cleanup watchdog must fire before request timeout')
latest_client.cleanup_before_exit_callback(false, 'cleanup_failed')
assert_equal(#private_dungeon_requests, before_return_delayed_requests + 1, 'return_lobby delayed cleanup callback should request platform once')
assert_equal(#completion_payloads, before_return_delayed_completions + 1, 'return_lobby delayed cleanup callback should complete once')
assert_latest_cleanup('cleanup_failed', false, true, 'return_lobby delayed cleanup failure')
assert_equal(cleanup_watchdog_timer.removed, true, 'return_lobby delayed cleanup callback removes cleanup watchdog')
assert_equal(request_timeout_timer.removed, true, 'return_lobby delayed cleanup callback removes request timeout')
cleanup_watchdog_callback()
latest_client.cleanup_before_exit_callback(true, nil)
assert_equal(#private_dungeon_requests, before_return_delayed_requests + 1, 'return_lobby cleanup callback/watchdog race must not request twice')
assert_equal(#completion_payloads, before_return_delayed_completions + 1, 'return_lobby cleanup callback/watchdog race must not complete twice')

connect_ready_with_cleanup({ cleanup_before_exit_returns_false = true })
local before_return_watchdog_requests = #private_dungeon_requests
local before_return_watchdog_completions = #completion_payloads
local return_cleanup_watchdog = y3.lobby.return_lobby({
    level_id = 'return-cleanup-watchdog',
    game_mode = 907,
    max_player = 8,
})
local cleanup_watchdog_timer_only, cleanup_watchdog_callback_only = find_timer_by_delay(8)
assert_equal(return_cleanup_watchdog.accepted, true, 'return_lobby cleanup watchdog should be accepted')
assert_equal(#private_dungeon_requests, before_return_watchdog_requests, 'return_lobby cleanup watchdog must not request before watchdog')
cleanup_watchdog_callback_only()
assert_equal(#private_dungeon_requests, before_return_watchdog_requests + 1, 'return_lobby cleanup watchdog should request platform once')
assert_equal(#completion_payloads, before_return_watchdog_completions + 1, 'return_lobby cleanup watchdog should complete once')
assert_latest_cleanup('cleanup_watchdog', false, true, 'return_lobby cleanup watchdog')
assert_equal(cleanup_watchdog_timer_only.removed, true, 'return_lobby cleanup watchdog removes cleanup timer')
latest_client.cleanup_before_exit_callback(true, nil)
assert_equal(#private_dungeon_requests, before_return_watchdog_requests + 1, 'return_lobby late cleanup callback after watchdog must not request twice')

connect_ready_with_cleanup({ cleanup_before_exit = nil })
latest_client.cleanup_before_exit = nil
local before_return_unavailable_requests = #private_dungeon_requests
local before_return_unavailable_completions = #completion_payloads
local return_cleanup_unavailable = y3.lobby.return_lobby({
    level_id = 'return-cleanup-unavailable',
    game_mode = 908,
    max_player = 8,
})
assert_equal(return_cleanup_unavailable.accepted, true, 'return_lobby without cleanup helper should be accepted')
assert_equal(#private_dungeon_requests, before_return_unavailable_requests + 1, 'return_lobby without cleanup helper should still request platform')
if #completion_payloads == before_return_unavailable_completions and #frame_callbacks > 0 then
    frame_callbacks[#frame_callbacks]()
end
assert_equal(#completion_payloads, before_return_unavailable_completions + 1, 'return_lobby without cleanup helper should complete')
assert_latest_cleanup('cleanup_unavailable', nil, false, 'return_lobby cleanup unavailable')

connect_ready_with_cleanup({})
do
    assert_equal(y3.lobby.get_state().result_data.has_team, false, 'snapshot has_team false without cached team')
    latest_client.team_info = {
        team_id = 7788,
        captain = latest_client.aid,
        members = {
            { aid = latest_client.aid, name = 'captain' },
            { aid = 99002, name = 'member-2' },
        },
    }
    assert_equal(y3.lobby.get_state().result_data.has_team, true, 'snapshot has_team true with cached team')
    latest_client.chat_history = {
        team = {
            { sequence = 1, channel = 'team', message = 'team-one', aid = latest_client.aid },
            { sequence = 3, channel = 'team', message = 'team-two', aid = 99002 },
            { time = 10, channel = 'team', message = 'team-time-ten', aid = latest_client.aid },
            { time = 20, channel = 'team', message = 'team-time-twenty', aid = latest_client.aid },
        },
        world = {
            { sequence = 2, channel = 'world', message = 'world-one', aid = 99003 },
            { time = 10, channel = 'world', message = 'world-time-ten', aid = 99003 },
            { time = 10, channel = 'world', message = 'world-time-ten-stable', aid = 99004 },
        },
    }
    latest_client.message_history = {}
    all_messages = y3.lobby.get_chat_history().result_data.messages
    assert_equal(all_messages[1].message, 'team-one', 'merged chat history order #1')
    assert_equal(all_messages[2].message, 'world-one', 'merged chat history order #2')
    assert_equal(all_messages[3].message, 'team-two', 'merged chat history order #3')
    assert_equal(all_messages[4].message, 'team-time-ten', 'merged chat history missing sequence time order #1')
    assert_equal(all_messages[5].message, 'world-time-ten', 'merged chat history missing sequence time order #2')
    assert_equal(all_messages[6].message, 'world-time-ten-stable', 'merged chat history missing sequence stable order')
    assert_equal(all_messages[7].message, 'team-time-twenty', 'merged chat history missing sequence time order #4')
    member_second = y3.lobby.get_member(2)
    assert_result_shape(member_second, member_second.action)
    assert_equal(member_second.accepted, true, 'get_member should read cached team member synchronously')
    assert_equal(member_second.sync, true, 'get_member cache query is synchronous')
    assert_equal(member_second.result_data.member.aid, 99002, 'get_member returns requested member')
    missing_member = y3.lobby.get_member(3)
    assert_equal(missing_member.accepted, true, 'get_member out of range is a successful empty lookup')
    assert_equal(missing_member.result_data.exists, false, 'get_member out of range reports exists=false')
    world_message = y3.lobby.get_chat_message(1, 'world')
    assert_result_shape(world_message, world_message.action)
    assert_equal(world_message.accepted, true, 'get_chat_message should read cached chat synchronously')
    assert_equal(world_message.sync, true, 'get_chat_message cache query is synchronous')
    assert_equal(world_message.result_data.message.message, 'world-one', 'get_chat_message returns requested message')
    missing_message = y3.lobby.get_chat_message(4, 'world')
    assert_equal(missing_message.accepted, true, 'get_chat_message out of range is a successful empty lookup')
    assert_equal(missing_message.result_data.exists, false, 'get_chat_message out of range reports exists=false')

    team_info_result = y3.lobby.get_team_info(99002)
    assert_result_shape(team_info_result, team_info_result.action)
    assert_equal(team_info_result.accepted, true, 'get_team_info should be async RPC when connected')
    assert_equal(team_info_result.sync, false, 'get_team_info async semantics')
    assert_equal(latest_client.last_get_team_info_aid, 99002, 'get_team_info forwards target aid')
    latest_client.get_team_info_callback({ team_id = 8899, members = { { aid = 99002 } } }, nil)
    assert_equal(completion_payloads[#completion_payloads].request_id, team_info_result.request_id, 'get_team_info completion request_id')
    assert_equal(completion_payloads[#completion_payloads].result_data.team.team_id, 8899, 'get_team_info completion data')
    assert_equal(completion_payloads[#completion_payloads].result_data.has_team, true, 'get_team_info team result flag')

    no_team_info_result = y3.lobby.get_team_info(99003)
    latest_client.get_team_info_callback(nil, nil)
    assert_equal(completion_payloads[#completion_payloads].request_id, no_team_info_result.request_id, 'get_team_info no-team completion request_id')
    assert_equal(completion_payloads[#completion_payloads].success, true, 'get_team_info no-team is successful')
    assert_equal(completion_payloads[#completion_payloads].result_data.has_team, false, 'get_team_info no-team result flag')

    player_info_result = y3.lobby.get_player_info(99002)
    assert_result_shape(player_info_result, player_info_result.action)
    assert_equal(player_info_result.accepted, true, 'get_player_info cache hit should be accepted')
    assert_equal(player_info_result.sync, true, 'get_player_info cache hit is synchronous')
    assert_equal(player_info_result.result_data.player.aid, 99002, 'get_player_info returns cached team member')

    latest_client.team_info = nil
    missing_player_info_result = y3.lobby.get_player_info(99004)
    latest_client.get_player_info_callback(nil, nil)
    assert_equal(completion_payloads[#completion_payloads].request_id, missing_player_info_result.request_id, 'get_player_info missing completion request_id')
    assert_equal(completion_payloads[#completion_payloads].success, false, 'get_player_info missing should fail')
    assert_equal(completion_payloads[#completion_payloads].code, 'player_not_found', 'get_player_info missing code')

    remote_player_info_result = y3.lobby.get_player_info(99005)
    latest_client.get_player_info_callback(nil, 'remote-string-error')
    assert_equal(completion_payloads[#completion_payloads].request_id, remote_player_info_result.request_id, 'get_player_info remote completion request_id')
    assert_equal(completion_payloads[#completion_payloads].code, 'rpc_failed', 'get_player_info remote completion code')
    assert_equal(completion_payloads[#completion_payloads].result_data.remote_error_code, 'remote-string-error', 'get_player_info preserves original remote error')

    refresh_info_result = y3.lobby.refresh_player_info()
    assert_result_shape(refresh_info_result, refresh_info_result.action)
    assert_equal(refresh_info_result.accepted, true, 'refresh_player_info should be async RPC when connected')
    assert_equal(refresh_info_result.sync, false, 'refresh_player_info async semantics')
    latest_client.refresh_player_info_callback({ aid = latest_client.aid, score = 1234 }, nil)
    assert_equal(completion_payloads[#completion_payloads].request_id, refresh_info_result.request_id, 'refresh_player_info completion request_id')
    assert_equal(completion_payloads[#completion_payloads].result_data.player.score, 1234, 'refresh_player_info completion data')
end

local requests_before_split_included = #private_dungeon_requests
local split_included = y3.lobby.same_room_split({
    level_id = 'level-included',
    game_mode = 801,
    max_player = 2,
    players = { { aid = latest_client.aid }, { aid = 99002 } },
})
assert_equal(split_included.accepted, true, 'same_room_split should accept when current BOB aid is selected')
assert_equal(#private_dungeon_requests, requests_before_split_included + 1, 'same_room_split should call platform request when current BOB aid is selected')
assert_equal(private_dungeon_requests[#private_dungeon_requests].level_id, 'level-included', 'same_room_split forwards selected level_id')
assert_equal(split_included.result_data.platform_requested, true, 'same_room_split reports platform request sent')
assert_equal(split_included.result_data.entered_target, 'unknown', 'same_room_split does not claim target entry synchronously')
assert_equal(split_included.result_data.confirm_by, 'platform_request_sent', 'same_room_split confirmation source')
frame_callbacks[#frame_callbacks]()
assert_equal(completion_payloads[#completion_payloads].request_id, split_included.request_id, 'same_room_split completion request_id')

local join_token_result = y3.lobby.join_by_token(' token-123 ')
assert_equal(join_token_result.accepted, true, 'join_by_token should be accepted')
assert_equal(join_private_dungeon_requests[#join_private_dungeon_requests], 'token-123', 'join_by_token trims and forwards token')
assert_equal(completion_payloads[#completion_payloads].request_id ~= join_token_result.request_id, true, 'join_by_token must not complete before deferred frame')
frame_callbacks[#frame_callbacks]()
assert_equal(completion_payloads[#completion_payloads].request_id, join_token_result.request_id, 'join_by_token completion request_id')

local return_lobby_result = y3.lobby.return_lobby({
    level_id = 'lobby-level',
    game_mode = 902,
    max_player = 8,
    custom_param = 'return-param',
})
assert_equal(return_lobby_result.accepted, true, 'return_lobby should be accepted')
assert_equal(private_dungeon_requests[#private_dungeon_requests].level_id, 'level-included', 'return_lobby should wait for cleanup before platform request')
latest_client.cleanup_before_exit_callback(true, nil)
assert_equal(private_dungeon_requests[#private_dungeon_requests].level_id, 'lobby-level', 'return_lobby forwards level_id')
assert_equal(private_dungeon_requests[#private_dungeon_requests].custom_param, 'return-param', 'return_lobby forwards custom_param')
if completion_payloads[#completion_payloads].request_id ~= return_lobby_result.request_id and #frame_callbacks > 0 then
    frame_callbacks[#frame_callbacks]()
end
assert_equal(completion_payloads[#completion_payloads].request_id, return_lobby_result.request_id, 'return_lobby completion request_id')
assert_equal(completion_payloads[#completion_payloads].result_data.platform_requested, true, 'return_lobby reports platform request')
assert_equal(completion_payloads[#completion_payloads].result_data.entered_target, 'unknown', 'return_lobby does not claim target entry')
assert_equal(completion_payloads[#completion_payloads].result_data.confirm_by, 'platform_request_sent', 'return_lobby confirmation source')

connect_ready_with_cleanup({})
local requests_before_split_excluded = #private_dungeon_requests
local split_excluded = y3.lobby.same_room_split({
    level_id = 'level-excluded',
    game_mode = 802,
    max_player = 2,
    players = { { aid = 99003 }, { aid = 99004 } },
})
assert_equal(split_excluded.accepted, false, 'same_room_split should synchronously reject when current BOB aid is not selected')
assert_equal(split_excluded.sync, true, 'same_room_split non-selected result should be synchronous')
assert_equal(split_excluded.code, 'player_not_selected', 'same_room_split non-selected rejection code')
assert_equal(#private_dungeon_requests, requests_before_split_excluded, 'same_room_split must not call platform request when current BOB aid is not selected')

remote_error_request = y3.lobby.create_team(4)
assert_equal(remote_error_request.accepted, true, 'remote error scenario should send request')
latest_client.create_team_callback(nil, 300123)
assert_equal(completion_payloads[#completion_payloads].request_id, remote_error_request.request_id, 'remote error completion request_id')
assert_equal(completion_payloads[#completion_payloads].code, 'rpc_failed', 'unknown remote error remains rpc_failed')
assert_equal(completion_payloads[#completion_payloads].result_data.remote_error_code, 300123, 'unknown remote error code is preserved')

local before_timeout_count = #completion_payloads
local world_chat = y3.lobby.send_world_chat('hello')
assert_equal(world_chat.accepted, true, 'send_world_chat should be accepted when connected')
local timeout_callback = timeout_callbacks[#timeout_callbacks]
timeout_callback()
assert_equal(#completion_payloads, before_timeout_count + 1, 'timeout should publish one failed completion')
assert_equal(completion_payloads[#completion_payloads].code, 'timeout', 'timeout completion code')
assert_equal(y3.lobby.get_state().result_data.failed_events ~= nil, true, 'state snapshot exposes failed_events')

reset_lobby_with_factory(function()
    factory_calls = factory_calls + 1
    latest_client = new_fake_client()
    return latest_client
end)
local connect_for_exit = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(connect_for_exit.accepted, true, 'exit sequence setup connect should be accepted')
latest_client.ready = true
latest_client:emit('准备就绪')
local before_exit_count = #completion_payloads
local exit_result = y3.lobby.exit_game()
assert_equal(exit_result.accepted, true, 'exit_game should be accepted when connected')
assert_equal(exit_game_calls, 0, 'exit_game must not exit before cleanup callback')
assert_equal(type(latest_client.cleanup_before_exit_callback), 'function', 'exit_game should wait for cleanup_before_exit callback')
latest_client.cleanup_before_exit_callback(true, nil)
assert_equal(#completion_payloads, before_exit_count + 1, 'exit_game should complete after cleanup callback')
assert_equal(completion_payloads[#completion_payloads].request_id, exit_result.request_id, 'exit_game completion request_id should match accepted result')
assert_equal(exit_game_calls, 0, 'exit_game must publish completion before actual exit')
assert_equal(#frame_callbacks, 1, 'exit_game should schedule actual exit on the next frame')
frame_callbacks[1]()
assert_equal(exit_game_calls, 1, 'exit_game should exit exactly once on next frame')
latest_client.cleanup_before_exit_callback(true, nil)
for index = 2, #frame_callbacks do
    frame_callbacks[index]()
end
assert_equal(exit_game_calls, 1, 'exit_game must not exit twice if cleanup callback repeats')

connect_ready_with_cleanup({ cleanup_before_exit_error = 'exit cleanup exploded' })
local before_exit_exception_completions = #completion_payloads
local before_exit_exception_calls = exit_game_calls
local exit_exception_result = y3.lobby.exit_game()
assert_equal(exit_exception_result.accepted, true, 'exit_game cleanup exception should be accepted')
assert_equal(exit_game_calls, before_exit_exception_calls, 'exit_game cleanup exception must not exit before completion')
if #completion_payloads == before_exit_exception_completions then
    assert_equal(#frame_callbacks > 0, true, 'exit_game cleanup exception should schedule completion frame when completion is deferred')
    frame_callbacks[#frame_callbacks]()
end
assert_equal(#completion_payloads, before_exit_exception_completions + 1, 'exit_game cleanup exception should complete once')
assert_equal(completion_payloads[#completion_payloads].request_id, exit_exception_result.request_id, 'exit_game cleanup exception completion request_id')
assert_latest_cleanup('cleanup_exception', false, true, 'exit_game cleanup exception')
assert_equal(exit_game_calls, before_exit_exception_calls, 'exit_game cleanup exception must publish completion before actual exit')
frame_callbacks[#frame_callbacks]()
assert_equal(exit_game_calls, before_exit_exception_calls + 1, 'exit_game cleanup exception should exit once on next frame')
for index = 1, #frame_callbacks do
    frame_callbacks[index]()
end
assert_equal(exit_game_calls, before_exit_exception_calls + 1, 'exit_game cleanup exception must not exit more than once')

connect_ready_with_cleanup({ cleanup_before_exit_returns_false = true })
local before_exit_watchdog_completions = #completion_payloads
local before_exit_watchdog_calls = exit_game_calls
local exit_watchdog_result = y3.lobby.exit_game()
local exit_cleanup_watchdog_timer, exit_cleanup_watchdog_callback = find_timer_by_delay(8)
local exit_request_timeout_timer = find_timer_by_delay(10)
assert_equal(exit_watchdog_result.accepted, true, 'exit_game cleanup watchdog should be accepted')
assert_equal(#completion_payloads, before_exit_watchdog_completions, 'exit_game cleanup watchdog must not complete before watchdog')
assert_equal(exit_game_calls, before_exit_watchdog_calls, 'exit_game cleanup watchdog must not exit before completion')
assert_equal(type(exit_cleanup_watchdog_callback), 'function', 'exit_game cleanup watchdog should install watchdog timer')
assert_equal(exit_cleanup_watchdog_timer.delay < exit_request_timeout_timer.delay, true, 'exit_game cleanup watchdog must fire before request timeout')
exit_cleanup_watchdog_callback()
assert_equal(#completion_payloads, before_exit_watchdog_completions + 1, 'exit_game cleanup watchdog should complete once')
assert_equal(completion_payloads[#completion_payloads].request_id, exit_watchdog_result.request_id, 'exit_game cleanup watchdog completion request_id')
assert_latest_cleanup('cleanup_watchdog', false, true, 'exit_game cleanup watchdog')
assert_equal(exit_game_calls, before_exit_watchdog_calls, 'exit_game cleanup watchdog must publish completion before actual exit')
assert_equal(exit_cleanup_watchdog_timer.removed, true, 'exit_game cleanup watchdog removes cleanup timer')
assert_equal(exit_request_timeout_timer.removed, true, 'exit_game cleanup watchdog removes request timer')
frame_callbacks[#frame_callbacks]()
assert_equal(exit_game_calls, before_exit_watchdog_calls + 1, 'exit_game cleanup watchdog should exit once on next frame')
latest_client.cleanup_before_exit_callback(true, nil)
for index = 1, #frame_callbacks do
    frame_callbacks[index]()
end
assert_equal(exit_game_calls, before_exit_watchdog_calls + 1, 'exit_game late cleanup callback after watchdog must not exit twice')

reset_lobby_with_factory(function()
    factory_calls = factory_calls + 1
    latest_client = new_fake_client()
    return latest_client
end)
local factory_calls_before_closing_connect = factory_calls
state_api.set_status('closing')
local closing_connect = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(closing_connect.accepted, false, 'connect while closing should be rejected synchronously')
assert_equal(closing_connect.sync, true, 'connect while closing should be synchronous')
assert_equal(closing_connect.code, 'connection_closing', 'connect while closing code')
assert_equal(factory_calls, factory_calls_before_closing_connect, 'connect while closing must not create client')

do
    local invalid_argument_factory_calls = 0
    reset_lobby_with_factory(function()
        invalid_argument_factory_calls = invalid_argument_factory_calls + 1
        return new_fake_client()
    end)
    local missing_game_play_connect = y3.lobby.connect()
    assert_equal(missing_game_play_connect.accepted, false, 'missing game_play_id connect should be rejected synchronously')
    assert_equal(missing_game_play_connect.sync, true, 'missing game_play_id connect should be synchronous')
    assert_equal(missing_game_play_connect.code, 'invalid_game_play_id', 'missing game_play_id connect code')
    local string_game_play_connect = y3.lobby.connect('10190356')
    assert_equal(string_game_play_connect.accepted, false, 'string game_play_id connect should be rejected synchronously')
    assert_equal(string_game_play_connect.code, 'invalid_game_play_id', 'string game_play_id connect code')
    local zero_game_play_connect = y3.lobby.connect(0)
    assert_equal(zero_game_play_connect.accepted, false, 'zero game_play_id connect should be rejected synchronously')
    assert_equal(zero_game_play_connect.code, 'invalid_game_play_id', 'zero game_play_id connect code')
    local negative_game_play_connect = y3.lobby.connect(-1)
    assert_equal(negative_game_play_connect.accepted, false, 'negative game_play_id connect should be rejected synchronously')
    assert_equal(negative_game_play_connect.code, 'invalid_game_play_id', 'negative game_play_id connect code')
    local fractional_game_play_connect = y3.lobby.connect(10190356.5)
    assert_equal(fractional_game_play_connect.accepted, false, 'fractional game_play_id connect should be rejected synchronously')
    assert_equal(fractional_game_play_connect.code, 'invalid_game_play_id', 'fractional game_play_id connect code')
    assert_equal(invalid_argument_factory_calls, 0, 'invalid game_play_id must not create client')
end

reset_lobby_with_factory(function()
    factory_calls = factory_calls + 1
    return nil, 'protocol_missing'
end)
local missing_protocol_connect = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(missing_protocol_connect.accepted, false, 'protocol missing connect should be rejected synchronously')
assert_equal(missing_protocol_connect.sync, true, 'protocol missing connect should be synchronous')
assert_equal(missing_protocol_connect.code, 'protocol_missing', 'protocol missing connect code')
assert_equal(#completion_payloads, 0, 'protocol missing synchronous connect rejection must not publish completion')

reset_lobby_with_factory(function()
    factory_calls = factory_calls + 1
    return nil, 'invalid_game_play_id', 'invalid_game_play_id: abc'
end)
local invalid_game_play_connect = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(invalid_game_play_connect.accepted, false, 'invalid game_play_id connect should be rejected synchronously')
assert_equal(invalid_game_play_connect.code, 'invalid_game_play_id', 'invalid game_play_id connect code')

reset_lobby_with_factory(function()
    factory_calls = factory_calls + 1
    latest_client = new_fake_client()
    return latest_client
end)
y3.eca._call_impls = nil
y3.const = nil
local eca_connect_definition = eca_by_action['建立连接']
local eca_status_definition = eca_by_action['获取连接状态']
local eca_members_definition = eca_by_action['获取队伍成员']
local eca_chat_history_definition = eca_by_action['获取聊天记录']
local eca_token_definition = eca_by_action['获取口令']
local eca_state_definition = eca_by_action['获取状态快照']
local factory_calls_before_eca_connect = factory_calls
do
    local eca_missing_game_play_id = registered[eca_connect_definition[1]].callback()
    assert_equal(eca_missing_game_play_id.accepted, false, 'ECA connect without game_play_id should be rejected synchronously')
    assert_equal(eca_missing_game_play_id.code, 'invalid_game_play_id', 'ECA connect without game_play_id code')
    assert_equal(factory_calls, factory_calls_before_eca_connect, 'ECA connect without game_play_id must not create BOB client')
end
local eca_connect_missing_event = registered[eca_connect_definition[1]].callback(TEST_GAME_PLAY_ID)
assert_equal(eca_connect_missing_event.accepted, false, 'ECA connect must reject when completion event is missing')
assert_equal(eca_connect_missing_event.code, 'event_missing', 'ECA connect missing event code')
assert_equal(factory_calls, factory_calls_before_eca_connect, 'ECA connect event_missing must not create BOB client')
assert_equal(registered[eca_status_definition[1]].callback().accepted, true, 'ECA connection status query may run without completion event')
assert_equal(registered[eca_state_definition[1]].callback().accepted, true, 'ECA state snapshot query may run without completion event')
local members_without_event = registered[eca_members_definition[1]].callback()
assert_equal(members_without_event.accepted, false, 'ECA get_members may run without completion event and preserve connection error')
assert_equal(members_without_event.code, 'not_connected', 'ECA get_members without connection should not become event_missing')
local chat_history_without_event = registered[eca_chat_history_definition[1]].callback(nil)
assert_equal(chat_history_without_event.accepted, false, 'ECA get_chat_history may run without completion event and preserve connection error')
assert_equal(chat_history_without_event.code, 'not_connected', 'ECA get_chat_history without connection should not become event_missing')
local token_without_event = registered[eca_token_definition[1]].callback()
assert_equal(token_without_event.accepted, true, 'ECA get_token may run without completion event or BOB connection')
assert_equal(token_without_event.sync, true, 'ECA get_token remains synchronous without BOB connection')

local reconnect_for_eca = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(reconnect_for_eca.accepted, true, 'Lua connect should still work without ECA event')
latest_client.ready = true
latest_client:emit('准备就绪')

local create_team_before_event = eca_by_action['创建队伍']
local calls_before_missing_event = latest_client.create_team_calls
local event_missing_result = registered[create_team_before_event[1]].callback(4)
assert_equal(event_missing_result.accepted, false, 'ECA business call must reject when completion event is missing')
assert_equal(event_missing_result.code, 'event_missing', 'ECA business call missing event code')
assert_equal(latest_client.create_team_calls, calls_before_missing_event, 'event_missing must not send underlying request')

y3.eca._call_impls = { ['大厅服务请求完成'] = true }
y3.eca.call = function(event_name, payload)
    emitted_events[#emitted_events + 1] = { event_name = event_name, payload = payload }
    return true
end
local eca_create_result = registered[create_team_before_event[1]].callback(3)
assert_equal(eca_create_result.accepted, true, 'ECA create_team should return accepted sync result')
assert_equal(#emitted_events, 0, 'ECA layer must not immediately fake async completion')
latest_client.create_team_callback(nil, nil)
latest_client.team_info = {
    team_id = 23456,
    captain = latest_client.aid,
    members = { { aid = latest_client.aid } },
}
latest_client:emit('队伍变化')
assert_equal(#emitted_events, 1, 'ECA completion event should be sent after real async completion')
assert_equal(emitted_events[1].payload.request_id, eca_create_result.request_id, 'ECA completion request_id should match accepted result')

emitted_events = {}
frame_callbacks = {}
local eca_split_definition = eca_by_action['同房分流']
local eca_split_result = registered[eca_split_definition[1]].callback({
    level_id = 'eca-split-level',
    game_mode = 901,
    max_player = 2,
    players = { { aid = latest_client.aid }, { aid = 99005 } },
})
assert_equal(eca_split_result.accepted, true, 'ECA same_room_split should be accepted when current BOB aid is selected')
assert_equal(#emitted_events, 0, 'ECA same_room_split synchronous completion must not re-enter before Bind result is assigned')
assert_equal(#frame_callbacks, 1, 'ECA same_room_split synchronous completion should delay completion event to next frame')
frame_callbacks[1]()
assert_equal(#emitted_events, 1, 'ECA same_room_split delayed synchronous completion should emit exactly one completion event')
assert_equal(emitted_events[1].payload.request_id, eca_split_result.request_id, 'ECA same_room_split completion request_id should match accepted result')
assert_equal(emitted_events[1].payload.success, true, 'ECA same_room_split completion should be successful')

emitted_events = {}
frame_callbacks = {}
state_api.runtime.failed_events = {}
y3.eca.call = function()
    error('eca completion send failed')
end
local eca_emit_failure_result = registered[eca_split_definition[1]].callback({
    level_id = 'eca-failed-event-level',
    game_mode = 902,
    max_player = 2,
    players = { { aid = latest_client.aid } },
})
assert_equal(eca_emit_failure_result.accepted, true, 'ECA same_room_split should accept before completion event send failure')
assert_equal(table_size(state_api.runtime.failed_events), 0, 'failed_events must not be written before async completion is sent')
frame_callbacks[1]()
local failed_event = state_api.runtime.failed_events[eca_emit_failure_result.request_id]
assert_equal(type(failed_event), 'table', 'ECA completion event send failure should be recorded')
assert_equal(failed_event.payload.request_id, eca_emit_failure_result.request_id, 'failed_events payload request_id')
assert_true(tostring(failed_event.error) ~= '', 'failed_events stores send error')

reset_lobby_with_factory(function()
    factory_calls = factory_calls + 1
    latest_client = new_fake_client()
    return latest_client
end)
local failing_connect = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(failing_connect.accepted, true, 'failing connect is initially accepted')
latest_client:emit('匹配服务不可用', 'service unavailable')
assert_equal(completion_payloads[#completion_payloads].success, false, 'connect failed callback should publish failed completion')
assert_equal(y3.lobby.get_connection_status().result_data.status, 'failed', 'failed connect should update status')
local cleaned_client = latest_client
local retry_connect = y3.lobby.connect(TEST_GAME_PLAY_ID)
assert_equal(retry_connect.accepted, true, 'connect should allow retry after failed status')
assert_true(latest_client ~= cleaned_client, 'retry after failed connect should create a new client')
assert_true(cleaned_client.remove_count > 0, 'retry after failed connect should remove old event handlers')
end

print('eca_lobby_api_contract_test: PASS')
