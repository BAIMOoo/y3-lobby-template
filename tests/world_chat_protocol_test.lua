local classes = {}

function Class(name)
    local class = {}
    classes[name] = class
    return class
end

package.preload['pub.core.service.define'] = function()
    return true
end
package.preload['pub.core.network.protocol'] = function()
    return {}
end
package.preload['pub.core.network.fsm'] = function()
    return {}
end
package.preload['pub.core.proto.proto_helper'] = function()
    return {}
end
package.preload['pub.core.network.message_handler'] = function()
    return {}
end

log = {
    warn = function()
    end,
    info = function()
    end,
}

y3 = {
    util = {
        dump = function()
            return ''
        end,
    },
}

dofile('maps/EntryMap/script/pub/core/service/client.lua')

local Client = assert(classes.Client)

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local events = {}
local client = setmetatable({}, { __index = Client })
client.notify_event_handler = function(_, ...)
    events[#events + 1] = { ... }
end

local world_chat = { sender = { aid = 201 }, chat_message = 'world' }
client:NotifyWorldChat({ arg3 = { world_chat } })
assert_equal(events[1][1], 'chat', 'world push event')
assert_equal(events[1][2].arg1, world_chat, 'world push message')

local multi_chat = { sender = { aid = 202 }, chat_message = 'multi' }
client:NotifyPushMultiChat({ arg2 = { multi_chat } })
assert_equal(events[2][1], 'chat', 'multi push event')
assert_equal(events[2][2].arg1, multi_chat, 'multi push message')

client:NotifyWorldChat({ arg2 = { world_chat } })
client:NotifyPushMultiChat({ arg1 = { multi_chat } })
assert_equal(#events, 2, 'wrong push fields must not emit chat events')

local legacy_chat = { sender = { aid = 203 }, chat_message = 'legacy' }
client:NotifyMultiChat({ arg1 = { legacy_chat } })
assert_equal(events[3][1], 'chat', 'legacy multi push event')
assert_equal(events[3][2].arg1, legacy_chat, 'legacy multi push message')

client:ApiRouter_UpdateChannel_ret(1, { arg3 = 10000 }, { ret1 = 0 })
assert_equal(events[4][1], 'ret', 'subscription return event')
assert_equal(events[4][2], 'Chat_UpdateChannel', 'subscription return method')

local delete_request = { arg1 = 201 }
local delete_response = { ret1 = 0 }
client:Team_DelPlayerInfo_ret(1, delete_request, delete_response)
assert_equal(events[5][1], 'ret', 'delete player return event')
assert_equal(events[5][2], 'Team_DelPlayerInfo', 'delete player return method')
assert_equal(events[5][4], delete_request, 'delete player request bridge')
assert_equal(events[5][5], delete_response, 'delete player response bridge')

local shutdown_count = 0
client.message_handler = {
    shutdown = function()
        shutdown_count = shutdown_count + 1
    end,
}
assert_equal(client:close('test exit'), true, 'client first close')
assert_equal(client:close('test exit again'), false, 'client repeated close')
assert_equal(shutdown_count, 1, 'client shutdown once')
assert_equal(client:start(), false, 'closed client cannot restart')
assert_equal(client:do_disconnect(), true, 'closed client accepts disconnect notification')
assert_equal(shutdown_count, 1, 'disconnect notification does not reconnect or shutdown again')

local proto_desc = dofile('maps/EntryMap/script/pub/core/proto/proto_desc.lua')
local client_push = proto_desc.ret[3847458462905599201]
assert_equal(client_push[8].method_name, 'NotifyWorldChat', 'world push method index')
assert_equal(client_push[9].method_name, 'NotifyPushMultiChat', 'multi push method index')
assert_equal(client_push[8].args_pb_name, 'protocol.ClientPush_NotifyWorldChat_args', 'world push protobuf')
assert_equal(client_push[9].args_pb_name, 'protocol.ClientPush_NotifyMultiChat_args', 'multi push protobuf')

print('world_chat_protocol_test: PASS')
