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

local pending_timers = {}
y3 = {
    inspect = function()
        return ''
    end,
    player = {
        get_local = function()
            return {}
        end,
    },
    ctimer = {
        wait = function(_, callback)
            local timer = {
                removed = false,
                remove = function(self)
                    self.removed = true
                end,
            }
            pending_timers[#pending_timers + 1] = {
                callback = callback,
                timer = timer,
            }
            return timer
        end,
    },
}

GameAPI = {
    visual_pyexec = function()
    end,
}

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function run_case(path)
    classes.Bob = nil
    pending_timers = {}
    dofile(path)
    local Bob = assert(classes.Bob)

    local order = {}
    local listeners = {}
    local matching = true
    local in_team = true
    local cancel_done
    local leave_done
    local delete_done
    local completion = {}
    local removed_listeners = 0
    local client_close_reason
    local forced_leave

    local bob = setmetatable({
        aid = 1001,
        request_handlers = {},
        team_info = { team_id = 2001 },
        player_infos = { [1001] = { aid = 1001 } },
        client = {
            close = function(_, reason)
                client_close_reason = reason
            end,
        },
    }, { __index = Bob })

    bob.event_on = function(_, event, callback)
        order[#order + 1] = 'listen:' .. event
        listeners[event] = callback
        return {
            remove = function()
                removed_listeners = removed_listeners + 1
            end,
        }
    end
    bob.is_matching = function()
        return matching
    end
    bob.is_launching = function()
        return false
    end
    bob.is_in_team = function()
        return in_team
    end
    bob.cancel_match = function(_, done)
        order[#order + 1] = 'cancel'
        cancel_done = done
        return true
    end
    bob.leave_team = function(_, done, force)
        order[#order + 1] = 'leave'
        leave_done = done
        forced_leave = force
        return true
    end
    bob.delete_player_info = function(_, done)
        order[#order + 1] = 'delete'
        delete_done = done
        return true
    end

    local started = bob:cleanup_before_exit(function(ok, reason)
        completion[#completion + 1] = { ok = ok, reason = reason }
        order[#order + 1] = 'done'
    end, 5)
    assert_equal(started, true, path .. ' cleanup starts')
    assert_equal(order[1], 'listen:匹配状态变化', path .. ' listens before cancel')
    assert_equal(order[2], 'cancel', path .. ' cancel request order')
    assert_equal(order[3], nil, path .. ' leave waits for matching state')

    local joined = bob:cleanup_before_exit(function(ok, reason)
        completion[#completion + 1] = { ok = ok, reason = reason }
    end, 5)
    assert_equal(joined, false, path .. ' repeated cleanup joins existing flow')
    assert_equal(order[3], nil, path .. ' repeated cleanup sends no request')

    cancel_done({}, nil)
    assert_equal(order[3], nil, path .. ' cancel response alone does not leave')
    matching = false
    listeners['匹配状态变化'](nil, false)
    assert_equal(order[3], 'listen:离开队伍', path .. ' listens before leave')
    assert_equal(order[4], 'leave', path .. ' leave starts after matching clears')
    assert_equal(forced_leave, true, path .. ' exit cleanup forces leave after cancel')

    leave_done({}, nil)
    assert_equal(order[5], nil, path .. ' leave response alone does not delete')
    in_team = false
    bob.team_info = nil
    listeners['离开队伍'](nil, '离开')
    assert_equal(order[5], 'delete', path .. ' delete starts after leave push')

    delete_done({}, nil)
    assert_equal(order[6], 'done', path .. ' completion after player deletion')
    assert_equal(#completion, 2, path .. ' all joined callbacks complete')
    assert_equal(completion[1].ok, true, path .. ' cleanup succeeds')
    assert_equal(completion[1].reason, nil, path .. ' cleanup success reason')
    assert_equal(removed_listeners, 2, path .. ' temporary listeners removed')
    assert_equal(pending_timers[1].timer.removed, true, path .. ' timeout removed')
    assert_equal(bob.team_info, nil, path .. ' local team state cleared')
    assert_equal(bob.player_infos[1001], nil, path .. ' local player state cleared')
    assert_equal(client_close_reason, 'exit cleanup', path .. ' client closes after cleanup')
    assert_equal(bob._exiting, true, path .. ' exit marker remains set after cleanup')

    local reconnect_count = 0
    local refresh_bob = setmetatable({
        aid = 1003,
        icon = '',
        name = 'test',
        score = 0,
        map_id = 'map',
        game_play_id_num = 1,
        request_handlers = {},
        client = {
            Team_UpdatePlayerInfo = function()
            end,
            reconnect = function()
                reconnect_count = reconnect_count + 1
            end,
        },
    }, { __index = Bob })
    refresh_bob.request = function(_, _, sender)
        sender()
        return true
    end
    refresh_bob:refresh_player_info()
    local refresh_timeout = pending_timers[#pending_timers]
    refresh_bob._exiting = true
    refresh_timeout.callback(refresh_timeout.timer)
    assert_equal(reconnect_count, 0, path .. ' stale refresh timeout cannot reconnect while exiting')

    local timeout_result
    local timeout_delete_done
    local timeout_bob = setmetatable({
        aid = 1002,
        request_handlers = {},
        team_info = { team_id = 2002 },
    }, { __index = Bob })
    timeout_bob.event_on = function()
        return { remove = function() end }
    end
    timeout_bob.is_matching = function()
        return false
    end
    timeout_bob.is_launching = function()
        return false
    end
    timeout_bob.is_in_team = function()
        return true
    end
    timeout_bob.leave_team = function()
        return true
    end
    timeout_bob.delete_player_info = function(_, done)
        timeout_delete_done = done
        return true
    end
    timeout_bob:cleanup_before_exit(function(ok, reason)
        timeout_result = { ok = ok, reason = reason }
    end, 5)
    local timeout = pending_timers[#pending_timers]
    timeout.callback(timeout.timer)
    assert(timeout_delete_done, path .. ' leave timeout continues player deletion')
    timeout_delete_done({}, nil)
    assert_equal(timeout_result.ok, false, path .. ' timeout fails cleanup')
    assert_equal(timeout_result.reason, 'leave-team-timeout', path .. ' timeout reason')
end

run_case('maps/EntryMap/script/pub/core/bob.lua')
run_case('maps/MapName001/script/pub/core/bob.lua')

print('bob_exit_cleanup_test: PASS')
