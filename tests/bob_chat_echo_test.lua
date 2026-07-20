local classes = {}

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

y3 = {
    inspect = function()
        return ''
    end,
    player = {
        get_local = function()
            return {}
        end,
    },
}

log = {
    debug = function()
    end,
    info = function()
    end,
    warn = function()
    end,
    error = function(message)
        error(message)
    end,
}

GameAPI = {
    visual_pyexec = function()
    end,
}

dofile('maps/EntryMap/script/pub/core/bob.lua')

local Bob = assert(classes.Bob)

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function new_bob(send_ok, send_err, in_team)
    local sent
    local events = {}
    local team_info
    if in_team ~= false then
        team_info = { team_id = 202 }
    end
    local bob = setmetatable({
        aid = 101,
        name = 'Local Player',
        icon = 'local-icon',
        message_history = {},
        request_handlers = {},
        team_info = team_info,
    }, { __index = Bob })

    bob.client = {
        ApiRouter_SendChatMsg = function(_, sender, message, channel_type, dst_id, flag)
            sent = {
                sender = sender,
                message = message,
                channel_type = channel_type,
                dst_id = dst_id,
                flag = flag,
            }
            return send_ok, send_err
        end,
    }
    bob.event_notify = function(_, event, data)
        events[#events + 1] = { event = event, data = data }
    end

    return bob, function()
        return sent, events
    end
end

local function complete_chat_request(bob, sent, errid, ret1)
    bob:notify_ret('Chat_SendChatMsg', errid, {
        arg1 = sent.sender,
        arg2 = sent.message,
        arg3 = sent.channel_type,
        arg4 = sent.dst_id,
        arg5 = sent.flag,
    }, { ret1 = ret1 })
end

do
    local bob, result = new_bob(true)
    local ok, err = bob:send_chat('team message')
    local sent, events = result()

    assert_equal(ok, true, 'team send result')
    assert_equal(err, nil, 'team send error')
    assert_equal(sent.channel_type, 4, 'team channel')
    assert_equal(sent.dst_id, 202, 'team destination')
    assert_equal(#bob.message_history, 0, 'team message waits for server response')

    complete_chat_request(bob, sent, 1, { errnu = 0 })
    assert_equal(#bob.message_history, 1, 'team response echo count')
    assert_equal(bob.message_history[1].message, 'team message', 'team response echo text')
    assert_equal(bob.message_history[1].chat.sender.aid, 101, 'team local sender')
    assert_equal(#events, 1, 'team response event count')

    bob:notify_chat({ arg1 = bob.message_history[1].chat })
    assert_equal(#bob.message_history, 1, 'self push deduplication')
    assert_equal(#events, 1, 'self push event deduplication')
end

do
    local bob, result = new_bob(true)
    bob:send_world_chat('world message')
    local sent = result()

    assert_equal(sent.channel_type, 5, 'world channel')
    assert_equal(sent.dst_id, 10000, 'world destination')
    complete_chat_request(bob, sent, 1, {})
    assert_equal(bob.message_history[1].chat.chat_type, 5, 'world response echo channel')
end

do
    local bob, result = new_bob(true)
    bob:send_world_chat('protocol failure')
    local sent = result()
    complete_chat_request(bob, sent, 2, {})
    assert_equal(#bob.message_history, 0, 'protocol failure must not echo')
end

do
    local bob, result = new_bob(true)
    bob:send_world_chat('business failure')
    local sent = result()
    complete_chat_request(bob, sent, 1, { error_code = 17 })
    assert_equal(#bob.message_history, 0, 'business failure must not echo')
end

do
    local bob, result = new_bob(false, 'network is not running')
    local ok, err = bob:send_world_chat('not queued')
    local sent = result()

    assert_equal(ok, false, 'network failure result')
    assert_equal(err, 'network is not running', 'network failure error')
    assert_equal(sent.message, 'not queued', 'network failure request attempt')
    assert_equal(#bob.message_history, 0, 'network failure must not echo')
end

do
    local bob, result = new_bob(true, nil, false)
    local ok, err = bob:send_chat('no team')

    assert_equal(ok, false, 'no-team send result')
    assert_equal(err, '当前不在队伍中', 'no-team send error')
    assert_equal(result(), nil, 'no-team request must not be sent')
    assert_equal(#bob.message_history, 0, 'no-team message must not echo')
end

do
    local bob, result = new_bob(true)
    bob:notify_chat({
        arg1 = {
            sender = { aid = 303, nickname = 'Remote Player', head_icon = 'remote-icon' },
            chat_message = 'remote message',
            chat_time = 123456,
            chat_type = 4,
        },
    })
    local _, events = result()

    assert_equal(#bob.message_history, 1, 'remote message count')
    assert_equal(bob.message_history[1].message, 'remote message', 'remote message text')
    assert_equal(#events, 1, 'remote event count')
end

print('bob_chat_echo_test: PASS')
