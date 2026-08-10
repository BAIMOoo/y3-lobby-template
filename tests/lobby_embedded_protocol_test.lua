local candidate_roots = {}
local configured_root = os.getenv('Y3_LUALIB_ROOT')
if configured_root and configured_root ~= '' then
    candidate_roots[#candidate_roots + 1] = configured_root
end
candidate_roots[#candidate_roots + 1] = '.omx/worktrees/y3-lualib-lobby'

local root
for _, candidate in ipairs(candidate_roots) do
    local file = io.open(candidate .. '/game/lobby/proto/proto_helper.lua', 'rb')
    if file then
        file:close()
        root = candidate
        break
    end
end
assert(root, 'lobby module root not found; set Y3_LUALIB_ROOT to a y3-lualib checkout')

package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path

local searchers = package.searchers or package.loaders
table.insert(searchers, 1, function(name)
    local prefix = 'y3.game.lobby'
    if name ~= prefix and name:sub(1, #prefix + 1) ~= prefix .. '.' then
        return nil
    end
    local suffix = name == prefix and 'init' or name:sub(#prefix + 2):gsub('%.', '/')
    local path = root .. '/game/lobby/' .. suffix .. '.lua'
    local file = io.open(path, 'rb')
    if not file then
        return nil
    end
    file:close()
    return function()
        return dofile(path)
    end
end)

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)), 2)
    end
end

local classes = {}

function Class(name)
    local class = {}
    class.__index = class
    classes[name] = class
    return class
end

function New(name)
    return function(...)
        local class = assert(classes[name], 'class not registered: ' .. tostring(name))
        local instance = setmetatable({}, class)
        if instance.__init then
            instance:__init(...)
        end
        return instance
    end
end

log = {
    info = function()
    end,
}

local loaded_protocol
local pb_load_calls = 0
package.preload['pb'] = function()
    return {
        load = function(content)
            pb_load_calls = pb_load_calls + 1
            loaded_protocol = content
            return true
        end,
        loadCustomProtocol = function()
            return true
        end,
        types = function()
            return function()
                return nil
            end
        end,
        option = function()
        end,
    }
end
package.preload['y3.game.lobby.proto.proto_desc'] = function()
    return {
        args = {},
        ret = {},
        method = {},
    }
end

local real_io_open = io.open
local service_file_reads = 0
io.open = function(path, mode)
    local normalized_path = tostring(path):gsub('\\', '/')
    if normalized_path:match('/game/lobby/proto/service%.pb$') then
        service_file_reads = service_file_reads + 1
        return nil, 'service.pb is unavailable in published virtual_script'
    end
    return real_io_open(path, mode)
end

package.loaded['pb'] = nil
package.loaded['y3.game.lobby.proto.proto_desc'] = nil
package.loaded['y3.game.lobby.proto.service_pb'] = nil
package.loaded['y3.game.lobby.proto.proto_helper'] = nil

local helper_api = require 'y3.game.lobby.proto.proto_helper'
local loaded, load_error = helper_api.load_all()

io.open = real_io_open

assert_equal(loaded, true, 'protocol helper loads without runtime service.pb')
assert_equal(load_error ~= nil, true, 'protocol helper returns its initialized instance')
assert_equal(service_file_reads, 0, 'protocol helper must not read service.pb at runtime')
assert_equal(pb_load_calls, 1, 'embedded service protocol is loaded once')

local embedded_protocol = require 'y3.game.lobby.proto.service_pb'
assert_equal(type(embedded_protocol), 'string', 'embedded protocol type')
assert_equal(#embedded_protocol, 42014, 'embedded protocol length')
assert_equal(loaded_protocol, embedded_protocol, 'pb.load receives the embedded protocol')

local source_file = real_io_open(root .. '/game/lobby/proto/service.pb', 'rb')
if source_file then
    local source_protocol = source_file:read('*a')
    source_file:close()
    assert_equal(embedded_protocol, source_protocol, 'embedded protocol bytes')
end

print('lobby_embedded_protocol_test: PASS')
