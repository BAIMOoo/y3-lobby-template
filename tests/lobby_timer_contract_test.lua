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

local function is_lualib_root(path)
    local file = io.open(path .. '/game/lobby/init.lua', 'rb')
    if not file then
        return false
    end
    file:close()
    return true
end

local function add_unique(values, value)
    for _, current in ipairs(values) do
        if current == value then
            return
        end
    end
    values[#values + 1] = value
end

local published_roots = {}
local configured_root = os.getenv('Y3_LUALIB_ROOT')
if configured_root and configured_root ~= '' and is_lualib_root(configured_root) then
    add_unique(published_roots, configured_root)
end
for _, candidate in ipairs({
    'maps/EntryMap/script/y3',
    'maps/MapName001/script/y3',
    'docs/游戏大厅系统/迁移包/script/y3',
}) do
    if is_lualib_root(candidate) then
        add_unique(published_roots, candidate)
    end
end
if #published_roots == 0 and is_lualib_root('.omx/worktrees/y3-lualib-lobby') then
    published_roots[1] = '.omx/worktrees/y3-lualib-lobby'
end
assert_true(#published_roots > 0, 'lobby module root not found; set Y3_LUALIB_ROOT to a y3-lualib checkout')

local root = published_roots[1]

do
    local lobby_files = {
        'bob.lua',
        'client.lua',
        'eca.lua',
        'init.lua',
        'network/coder.lua',
        'network/fsm.lua',
        'network/message_handler.lua',
        'network/net_event.lua',
        'network/protocol.lua',
        'proto/proto_desc.lua',
        'proto/proto_helper.lua',
        'proto/service_pb.lua',
        'result.lua',
        'service/client.lua',
        'service/define.lua',
        'state.lua',
    }
    local canonical_sources = {}
    for _, published_root in ipairs(published_roots) do
        for _, relative_path in ipairs(lobby_files) do
            local source = read_file(published_root .. '/game/lobby/' .. relative_path)
            assert_true(
                not source:find('y3.ctimer', 1, true),
                'published lobby source must not use y3.ctimer: ' .. published_root .. '/' .. relative_path
            )
            if canonical_sources[relative_path] then
                assert_equal(source, canonical_sources[relative_path], 'published lobby copies differ: ' .. relative_path)
            else
                canonical_sources[relative_path] = source
            end
        end
        for _, relative_path in ipairs({ 'util/local_timer.lua', 'util/network.lua' }) do
            local source = read_file(published_root .. '/' .. relative_path)
            if relative_path == 'util/network.lua' then
                assert_true(
                    not source:find('y3.ctimer', 1, true),
                    'published util/network.lua must not use y3.ctimer: ' .. published_root
                )
            end
            if canonical_sources[relative_path] then
                assert_equal(source, canonical_sources[relative_path], 'published lualib copies differ: ' .. relative_path)
            else
                canonical_sources[relative_path] = source
            end
        end
    end
end

do
    local remote_callback
    local completion_count = 0
    local completion_value
    local request_options
    local timer_calls = 0
    local bob_class = {}

    package.loaded['y3.game.lobby.service.client'] = nil
    package.preload['y3.game.lobby.service.client'] = function()
        return {}
    end

    Class = function(class_name)
        assert_equal(class_name, 'LobbyBob', 'bob class name')
        return bob_class
    end
    Extends = function() end
    GameAPI = {
        get_dungeon_info = function()
            return { env = 'prod' }
        end,
        visual_pyexec = function() end,
    }
    log = {
        debug = function() end,
        error = function() end,
        info = function() end,
        warn = function() end,
    }
    y3 = {
        game = {
            is_debug_mode = function()
                return false
            end,
            request_url = function(_, _, _, callback, options)
                remote_callback = callback
                request_options = options
            end,
        },
        json = {
            decode = function()
                return {
                    ['2.0'] = {
                        ['@metadata@'] = {
                            ['@displayversion@'] = '100',
                        },
                    },
                }
            end,
        },
        ltimer = {
            wait = function()
                timer_calls = timer_calls + 1
                error('check_update must not install an extra timer')
            end,
        },
        player = {
            get_local = function()
                return {
                    get_id = function()
                        return 1
                    end,
                }
            end,
        },
    }
    _G['_SVN_VERSION'] = '100'

    dofile(root .. '/game/lobby/bob.lua')
    local check_ok, check_error = pcall(bob_class.check_update, { aid = 1, level_id = 'test' }, function(need_update)
        completion_count = completion_count + 1
        completion_value = need_update
    end)
    assert_true(check_ok, 'check_update must start without a client timer: ' .. tostring(check_error))
    assert_equal(timer_calls, 0, 'check_update extra timer count')
    assert_true(type(remote_callback) == 'function', 'check_update must submit the HTTP request')
    assert_equal(type(request_options), 'table', 'check_update HTTP options type')
    assert_equal(request_options.timeout, 5, 'check_update HTTP native timeout')

    local nil_ok, nil_error = pcall(remote_callback, nil)
    assert_true(nil_ok, 'nil HTTP callback must not raise: ' .. tostring(nil_error))
    assert_equal(completion_count, 1, 'nil HTTP callback completion count')
    assert_equal(completion_value, false, 'nil HTTP callback must allow the client to continue')

    local duplicate_ok, duplicate_error = pcall(remote_callback, '{}')
    assert_true(duplicate_ok, 'late duplicate HTTP callback must be ignored: ' .. tostring(duplicate_error))
    assert_equal(completion_count, 1, 'late duplicate HTTP callback completion count')
end

do
    local scheduled = {}
    local network_class = {}

    local function new_timer(kind, delay, callback)
        local timer = {
            kind = kind,
            delay = delay,
            callback = callback,
            removed = false,
        }
        function timer:remove()
            self.removed = true
        end
        scheduled[#scheduled + 1] = timer
        return timer
    end

    Class = function(class_name)
        assert_equal(class_name, 'Network', 'network class name')
        return network_class
    end
    KKNetwork = function()
        return {}
    end
    log = {
        debug = function() end,
    }
    y3 = {
        ltimer = {
            loop = function(delay, callback)
                return new_timer('loop', delay, callback)
            end,
            wait = function(delay, callback)
                return new_timer('wait', delay, callback)
            end,
            wait_frame = function(delay, callback)
                return new_timer('wait_frame', delay, callback)
            end,
        },
    }

    dofile(root .. '/util/network.lua')
    local instance = {}
    network_class.__init(instance, '127.0.0.1', 12345, {})

    assert_equal(#scheduled, 3, 'network scheduler call count')
    assert_equal(scheduled[1].kind, 'loop', 'network update scheduler kind')
    assert_equal(scheduled[1].delay, 0.2, 'network update interval')
    assert_equal(instance.update_timer, scheduled[1], 'network update timer ownership')
    assert_equal(scheduled[2].kind, 'wait_frame', 'network initial update scheduler kind')
    assert_equal(scheduled[2].delay, 1, 'network initial update delay')
    assert_equal(scheduled[3].kind, 'loop', 'network retry scheduler kind')
    assert_equal(scheduled[3].delay, 5, 'network retry interval')
    assert_equal(instance.retry_timer, scheduled[3], 'network retry timer ownership')
end

print('lobby_timer_contract_test: PASS')
