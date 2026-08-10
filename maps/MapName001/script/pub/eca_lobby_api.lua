-- custom-built: ECA-facing facade for lobby, match, chat, and private-dungeon services.

local M = {}

M.EVENT_NAME = '大厅服务请求完成'
M.EVENT_ID = 1876423410
M.EVENT_PARAM_NAME = '回调数据'

local MATCH_GAME_MODE = 1002
local PRIVATE_GAME_MODE = 1003
local EXPECTED_PRIVATE_PLAYERS = 2
local DUNGEON_PLAYER_VERSION = '2.0'
local REQUEST_TIMEOUT = 10
local MAX_MEMBER_ITEMS = 8
local MAX_CHAT_ITEMS = 5

local runtime = rawget(_G, '__ECA_LOBBY_API_RUNTIME') or {
    sequence = 0,
    pending = {},
    locks = {},
}
runtime.pending = runtime.pending or {}
runtime.locks = runtime.locks or {}
runtime.failed_events = runtime.failed_events or {}
_G.__ECA_LOBBY_API_RUNTIME = runtime

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function to_integer(value)
    local ok, result = pcall(math.tointeger, value)
    if ok then
        return result
    end
    return nil
end

local function get_event_id()
    local names = y3.const and y3.const.CustomEventName
    local event_id = to_integer(names and names[M.EVENT_NAME])
    if event_id and event_id ~= 0 then
        return event_id
    end
    return M.EVENT_ID
end

local function safe_json(value)
    if y3.json and y3.json.encode then
        local ok, result = pcall(y3.json.encode, value)
        if ok then
            return result
        end
    end
    return '[]'
end

local function log_failure(message)
    if log and log.error then
        log.error('[ECA Lobby API] ' .. tostring(message))
    end
end

local function get_bob()
    local bob = rawget(_G, 'BOB')
    if not bob then
        return nil
    end
    local is_valid = rawget(_G, 'IsValid')
    if is_valid then
        local ok, valid = pcall(is_valid, bob)
        if not ok or not valid then
            return nil
        end
    end
    return bob
end

local function require_ready_bob()
    local bob = get_bob()
    if not bob then
        return nil, '大厅连接尚未创建'
    end
    if not bob.client or not bob:is_valid() then
        return nil, '大厅连接尚未就绪'
    end
    return bob
end

local function make_result(accepted, reason, request_id, action, sync, result_data)
    return {
        accepted = accepted == true,
        reason = tostring(reason or ''),
        request_id = tostring(request_id or ''),
        action = tostring(action or ''),
        sync = sync == true,
        result_data = result_data or {},
    }
end

local function rejected(action, reason, result_data)
    return make_result(false, reason, '', action, true, result_data)
end

local function accepted(request)
    return make_result(true, '请求已受理', request.id, request.action, false)
end

local function remove_resource(resource)
    if resource and resource.remove then
        pcall(resource.remove, resource)
    end
end

local function cleanup_request(request)
    remove_resource(request.timer)
    request.timer = nil
    for _, cleanup in ipairs(request.cleanups) do
        pcall(cleanup)
    end
    request.cleanups = {}
    runtime.pending[request.id] = nil
    if runtime.locks[request.lock] == request.id then
        runtime.locks[request.lock] = nil
    end
end

function M.emit_result(payload)
    local name_error
    if y3.eca and y3.eca.call then
        local ok, err = pcall(y3.eca.call, M.EVENT_NAME, payload)
        if ok then
            return true
        end
        name_error = tostring(err)
    else
        name_error = '当前运行时不支持按名称调用 ECA 自定义事件'
    end

    local event_id = get_event_id()
    local id_error
    if event_id == 0 then
        id_error = '当前地图尚未生成自定义事件“' .. M.EVENT_NAME .. '”的元数据'
    elseif y3.game and y3.game.send_custom_event then
        local event_args = {
            [M.EVENT_PARAM_NAME] = payload,
        }
        local ok, err = pcall(y3.game.send_custom_event, event_id, event_args)
        if ok then
            return true
        end
        id_error = tostring(err)
    else
        id_error = '当前运行时不支持按编号发送 ECA 自定义事件'
    end

    local message = '按名称事件通道失败：' .. name_error
        .. '；按编号事件通道失败：' .. id_error
    log_failure(message)
    return false, message
end

local function commit_finish(request, success, reason, result_data)
    if not request or request.done then
        return false
    end
    request.done = true
    cleanup_request(request)
    local payload = {
        request_id = request.id,
        action = request.action,
        success = success == true,
        reason = tostring(reason or ''),
        result_data = result_data or {},
    }
    local event_emitted, emit_error = M.emit_result(payload)
    if not event_emitted then
        runtime.failed_events[request.id] = {
            payload = payload,
            error = emit_error,
        }
    end
    return true
end

function M.finish(request, success, reason, result_data)
    if not request or request.done then
        return false
    end
    if not request.acceptance_decided then
        if not request.deferred_finish then
            request.deferred_finish = {
                success = success,
                reason = reason,
                result_data = result_data,
            }
        end
        return true
    end
    return commit_finish(request, success, reason, result_data)
end

local function cancel_request(request)
    if not request or request.done then
        return
    end
    request.done = true
    cleanup_request(request)
end

local function cleanup_stale_runtime()
    if not runtime.module then
        return
    end
    local stale = {}
    for _, request in pairs(runtime.pending) do
        stale[#stale + 1] = request
    end
    for _, request in ipairs(stale) do
        cancel_request(request)
    end
    runtime.pending = {}
    runtime.locks = {}
    runtime.exiting = false
end

cleanup_stale_runtime()

local function new_request(action, lock)
    if runtime.locks[lock] then
        return nil, '已有同类请求处理中'
    end
    if not y3.ctimer or not y3.ctimer.wait then
        return nil, '请求计时器不可用'
    end
    runtime.sequence = runtime.sequence + 1
    local bob = get_bob()
    local aid = bob and bob.aid or 0
    local request = {
        id = string.format('eca-%s-%s-%d', tostring(aid), tostring(os.time()), runtime.sequence),
        action = action,
        lock = lock,
        done = false,
        acceptance_decided = false,
        cleanups = {},
    }
    runtime.pending[request.id] = request
    runtime.locks[lock] = request.id
    local timer_ok, timer = pcall(y3.ctimer.wait, REQUEST_TIMEOUT, function()
        M.finish(request, false, '请求超时')
    end)
    if not timer_ok or not timer then
        cleanup_request(request)
        return nil, '创建请求计时器失败'
    end
    request.timer = timer
    return request
end

local function run_async(action, lock, starter)
    if runtime.exiting and action ~= '退出游戏' then
        return rejected(action, '正在退出游戏')
    end
    local request, reason = new_request(action, lock)
    if not request then
        return rejected(action, reason)
    end
    local ok, sent, send_reason = xpcall(function()
        return starter(request)
    end, function(err)
        return tostring(err)
    end)
    if not ok then
        request.deferred_finish = nil
        cancel_request(request)
        return rejected(action, '调用失败：' .. tostring(sent))
    end
    if sent == false then
        request.deferred_finish = nil
        cancel_request(request)
        return rejected(action, send_reason or '请求未发送')
    end
    request.acceptance_decided = true
    local result = accepted(request)
    local deferred = request.deferred_finish
    request.deferred_finish = nil
    if deferred then
        M.finish(request, deferred.success, deferred.reason, deferred.result_data)
    end
    return result
end

local function rpc_done(request, success_reason, result_data)
    return function(_, err)
        if err then
            M.finish(request, false, tostring(err))
        else
            M.finish(request, true, success_reason, result_data)
        end
    end
end

local function state_done(request, bob, event_name, predicate, success_reason, result_data)
    local rpc_succeeded = false
    local function check_state()
        if request.done or not rpc_succeeded then
            return
        end
        local ok, confirmed = pcall(predicate)
        if not ok then
            M.finish(request, false, '状态确认失败：' .. tostring(confirmed))
        elseif confirmed then
            M.finish(request, true, success_reason, result_data)
        end
    end
    if bob.event_on then
        local ok, trigger = pcall(bob.event_on, bob, event_name, function()
            check_state()
        end)
        if ok and trigger then
            request.cleanups[#request.cleanups + 1] = function()
                remove_resource(trigger)
            end
        end
    end
    return function(_, err)
        if err then
            M.finish(request, false, tostring(err))
            return
        end
        rpc_succeeded = true
        check_state()
    end
end

local function get_local_player()
    local result
    if y3.player and y3.player.with_local then
        y3.player.with_local(function(player)
            result = player
        end)
    end
    return result
end

local function get_mode_id()
    local mode
    if y3.game.get_current_game_mode then
        mode = y3.game.get_current_game_mode()
    end
    if (not mode or tostring(mode) == '0') and y3.game.get_current_game_mode_new then
        mode = y3.game.get_current_game_mode_new()
    end
    local game_api = rawget(_G, 'GameAPI')
    if (not mode or tostring(mode) == '0') and game_api and game_api.get_dungeon_info then
        local info = game_api.get_dungeon_info()
        mode = info and info.game_mode
    end
    return to_integer(mode) or mode or 0
end

local function get_mode_label(mode)
    if mode == 0 or mode == 1001 then
        return '大厅模式'
    elseif mode == MATCH_GAME_MODE then
        return '匹配对局'
    elseif mode == PRIVATE_GAME_MODE then
        return '私人副本'
    end
    return '未知模式'
end

local function is_battle_context()
    if MatchTestIsBattleContext then
        return MatchTestIsBattleContext()
    end
    local mode = get_mode_id()
    return mode == MATCH_GAME_MODE or mode == PRIVATE_GAME_MODE
end

local function contains_member(bob, target_aid)
    for _, member in ipairs(bob.team_info and bob.team_info.members or {}) do
        if to_integer(member.aid) == target_aid then
            return true
        end
    end
    return false
end

function M.rebuild_connection()
    local action = '重建大厅连接'
    if not CreateBobInLobby then
        return rejected(action, '大厅连接入口不可用')
    end
    return run_async(action, 'operation', function(request)
        local bob = CreateBobInLobby()
        if not bob then
            return false, '创建大厅连接失败'
        end
        if bob.event_on then
            local ready = bob:event_on('准备就绪', function()
                M.finish(request, true, '大厅连接已就绪', { aid = bob.aid or 0 })
            end)
            local update = bob:event_on('客户端需要更新', function()
                M.finish(request, false, '客户端需要更新')
            end)
            local unavailable = bob:event_on('匹配服务不可用', function()
                M.finish(request, false, '匹配服务不可用')
            end)
            request.cleanups[#request.cleanups + 1] = function() remove_resource(ready) end
            request.cleanups[#request.cleanups + 1] = function() remove_resource(update) end
            request.cleanups[#request.cleanups + 1] = function() remove_resource(unavailable) end
        end
        if bob.client and bob:is_valid() then
            M.finish(request, true, '大厅连接已就绪', { aid = bob.aid or 0 })
        end
        return true
    end)
end

function M.set_score(score)
    local action = '设置匹配分数'
    score = to_integer(score)
    if not score then
        return rejected(action, '请输入有效的整数分数')
    end
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    return run_async(action, 'operation', function(request)
        bob.score = score
        bob:refresh_player_info(rpc_done(request, '匹配分数已更新', { score = score }))
        return true
    end)
end

function M.create_team()
    local action = '创建队伍'
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if bob:is_in_team() then return rejected(action, '当前已在队伍中') end
    return run_async(action, 'operation', function(request)
        bob:create_team(state_done(request, bob, '队伍变化', function()
            return bob:is_in_team()
        end, '队伍创建成功'), EXPECTED_PRIVATE_PLAYERS)
        return true
    end)
end

function M.join_team(team_id)
    local action = '加入队伍'
    team_id = to_integer(team_id)
    if not team_id or team_id <= 0 then return rejected(action, '请输入有效的队伍编号') end
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if bob:is_matching() or bob:is_launching() then return rejected(action, '匹配或启动中不能加入队伍') end
    return run_async(action, 'operation', function(request)
        bob:refresh_player_info(function(_, refresh_err)
            if refresh_err then
                M.finish(request, false, tostring(refresh_err))
                return
            end
            bob:join_team(team_id, state_done(request, bob, '队伍变化', function()
                return bob.team_info and to_integer(bob.team_info.team_id) == team_id
            end, '已加入队伍', { team_id = team_id }))
        end)
        return true
    end)
end

function M.leave_team()
    local action = '离开队伍'
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if not bob:is_in_team() then return rejected(action, '当前不在队伍中') end
    return run_async(action, 'operation', function(request)
        return bob:leave_team(state_done(request, bob, '离开队伍', function()
            return not bob:is_in_team()
        end, '已离开队伍'))
    end)
end

function M.dismiss_team()
    local action = '解散队伍'
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if not bob:is_captain() then return rejected(action, '只有队长可以解散队伍') end
    return run_async(action, 'operation', function(request)
        return bob:dismiss_team(state_done(request, bob, '离开队伍', function()
            return not bob:is_in_team()
        end, '队伍已解散'))
    end)
end

function M.change_captain(target_aid)
    local action = '转移队长'
    target_aid = to_integer(target_aid)
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if not target_aid or target_aid == to_integer(bob.aid) then return rejected(action, '请输入有效的目标成员 AID') end
    if not bob:is_captain() then return rejected(action, '只有队长可以转移队长') end
    if not contains_member(bob, target_aid) then return rejected(action, '目标玩家不在当前队伍中') end
    return run_async(action, 'operation', function(request)
        return bob:change_captain(target_aid, state_done(request, bob, '队伍变化', function()
            return bob.team_info and to_integer(bob.team_info.captain) == target_aid
        end, '队长已转移', { target_aid = target_aid }))
    end)
end

function M.kick_member(target_aid)
    local action = '移出队员'
    target_aid = to_integer(target_aid)
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if not target_aid or target_aid == to_integer(bob.aid) then return rejected(action, '请输入有效的目标成员 AID') end
    if not bob:is_captain() then return rejected(action, '只有队长可以移出成员') end
    if not contains_member(bob, target_aid) then return rejected(action, '目标玩家不在当前队伍中') end
    return run_async(action, 'operation', function(request)
        return bob:team_kick(target_aid, state_done(request, bob, '队伍变化', function()
            return not contains_member(bob, target_aid)
        end, '成员已移出', { target_aid = target_aid }))
    end)
end

function M.start_match(score)
    local action = '开始匹配'
    score = to_integer(score)
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    local can_match, match_reason = bob:can_match()
    if not can_match then return rejected(action, match_reason) end
    return run_async(action, 'operation', function(request)
        return bob:start_match(MATCH_GAME_MODE, score, state_done(request, bob, '匹配状态变化', function()
            return bob:is_matching()
        end, '匹配已开始'))
    end)
end

function M.cancel_match()
    local action = '取消匹配'
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if not bob:is_matching() then return rejected(action, '当前未在匹配中') end
    if bob:is_in_team() and not bob:is_captain() then return rejected(action, '只有队长可以取消匹配') end
    return run_async(action, 'operation', function(request)
        return bob:cancel_match(state_done(request, bob, '匹配状态变化', function()
            return not bob:is_matching()
        end, '匹配已取消'))
    end)
end

local function finish_cross_map_request(request, reason)
    M.finish(request, true, reason, {
        cross_map_tracking = 'degraded',
    })
end

function M.create_private_dungeon()
    local action = '创建私人副本'
    if is_battle_context() then return rejected(action, '当前已在副本中') end
    if not MatchTestLocalPrivate then return rejected(action, '私人副本入口不可用') end
    return run_async(action, 'operation', function(request)
        local sent, reason = MatchTestLocalPrivate()
        if sent == false then return false, reason end
        finish_cross_map_request(request, '平台已受理创建副本请求')
        return true
    end)
end

function M.start_private_dungeon()
    local action = '启动多人私人副本'
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if not bob:is_in_team() then return rejected(action, '请先创建或加入队伍') end
    if not bob:is_captain() then return rejected(action, '只有队长可以进入多人副本') end
    local count = bob:get_player_count()
    if count < EXPECTED_PRIVATE_PLAYERS then return rejected(action, '队伍人数不足') end
    return run_async(action, 'operation', function(request)
        bob:refresh_player_info(function(_, refresh_err)
            if refresh_err then
                M.finish(request, false, tostring(refresh_err))
                return
            end
            local players = {}
            for _, member in ipairs(bob.team_info and bob.team_info.members or {}) do
                players[#players + 1] = {
                    aid = tostring(member.aid),
                    version = DUNGEON_PLAYER_VERSION,
                }
            end
            local sent, send_reason = bob:start_privat_dungeon_game({
                game_map_id = bob.map_id,
                level_id = bob.level_id,
                game_mode = PRIVATE_GAME_MODE,
            }, players, state_done(request, bob, '启动状态变化', function()
                return bob:is_launching() or is_battle_context()
            end, '多人私人副本已启动'))
            if sent == false then M.finish(request, false, send_reason) end
        end)
        return true
    end)
end

function M.join_private_dungeon(token)
    local action = '加入口令副本'
    token = trim(token)
    if token == '' then return rejected(action, '请输入副本口令') end
    if is_battle_context() then return rejected(action, '当前已在副本中') end
    if not MatchTestJoinPrivateDungeon then return rejected(action, '口令加入入口不可用') end
    return run_async(action, 'operation', function(request)
        local sent, reason = MatchTestJoinPrivateDungeon(token)
        if sent == false then return false, reason end
        finish_cross_map_request(request, '平台已受理加入副本请求')
        return true
    end)
end

function M.return_lobby()
    local action = '返回大厅'
    if not MatchTestReturnLobby then return rejected(action, '返回大厅入口不可用') end
    return run_async(action, 'operation', function(request)
        local sent, reason = MatchTestReturnLobby()
        if sent == false then return false, reason end
        finish_cross_map_request(request, '平台已受理返回大厅请求')
        return true
    end)
end

function M.exit_game()
    local action = '退出游戏'
    if runtime.exiting then return rejected(action, '正在退出游戏') end
    local player = get_local_player()
    if not player then return rejected(action, '未找到本地玩家') end
    return run_async(action, 'operation', function(request)
        runtime.exiting = true
        local function leave_after_event()
            local function leave()
                player:exit_game()
            end
            if y3.ctimer and y3.ctimer.wait_frame then
                y3.ctimer.wait_frame(1, leave)
            else
                leave()
            end
        end
        local bob = get_bob()
        if not bob then
            M.finish(request, true, '退出前清理完成')
            leave_after_event()
            return true
        end
        bob:cleanup_before_exit(function(ok, reason)
            local is_valid = rawget(_G, 'IsValid')
            local delete = rawget(_G, 'Delete')
            if bob == rawget(_G, 'BOB') and is_valid and delete then
                local valid_ok, valid = pcall(is_valid, bob)
                if valid_ok and valid then
                    delete(bob)
                    BOB = nil
                end
            end
            M.finish(request, ok, reason or (ok and '退出前清理完成' or '退出前清理失败'))
            leave_after_event()
        end)
        return true
    end)
end

local function send_chat(action, message, world)
    message = trim(message)
    if message == '' then return rejected(action, '消息不能为空') end
    local bob, reason = require_ready_bob()
    if not bob then return rejected(action, reason) end
    if not world and not bob:is_in_team() then return rejected(action, '当前不在队伍中') end
    return run_async(action, 'chat', function(request)
        local done = rpc_done(request, '消息发送成功', {
            channel = world and 'world' or 'team',
            message = message,
        })
        if world then
            return bob:send_world_chat(message, done)
        end
        return bob:send_chat(message, done)
    end)
end

function M.send_team_chat(message)
    return send_chat('发送队伍聊天', message, false)
end

function M.send_world_chat(message)
    return send_chat('发送世界聊天', message, true)
end

function M.get_state()
    local bob = get_bob()
    local mode = get_mode_id()
    local team_count, max_count = 0, 0
    if bob and bob.get_player_count then
        team_count, max_count = bob:get_player_count()
    end
    return {
        mode_id = mode,
        mode_label = get_mode_label(mode),
        is_battle_context = is_battle_context(),
        bob_exists = bob ~= nil,
        bob_ready = bob ~= nil and bob.client ~= nil and bob:is_valid() or false,
        aid = bob and bob.aid or 0,
        team_id = bob and bob.team_info and bob.team_info.team_id or 0,
        member_count = team_count,
        member_limit = max_count,
        is_captain = bob and bob:is_captain() or false,
        matching = bob and bob:is_matching() or false,
        launching = bob and bob:is_launching() or false,
        dungeon_token = MatchTestGetDungeonToken and MatchTestGetDungeonToken() or '',
        result_event_id = get_event_id(),
        result_event_name = M.EVENT_NAME,
    }
end

function M.request_state()
    local action = '获取状态快照'
    if not y3.ctimer or not y3.ctimer.wait_frame then
        return rejected(action, '帧计时器不可用')
    end
    return run_async(action, 'state_snapshot', function(request)
        local ok, frame = pcall(y3.ctimer.wait_frame, 1, function()
            local state_ok, state = pcall(M.get_state)
            if state_ok then
                M.finish(request, true, '状态快照已获取', state)
            else
                M.finish(request, false, '获取状态快照失败：' .. tostring(state))
            end
        end)
        if not ok or not frame then
            return false, '创建状态快照回调失败'
        end
        request.cleanups[#request.cleanups + 1] = function()
            remove_resource(frame)
        end
        return true
    end)
end

function M.get_members()
    local bob = get_bob()
    local members = bob and bob.team_info and bob.team_info.members or {}
    local data = {
        count = #members,
        members_json = safe_json(members),
    }
    for i = 1, math.min(#members, MAX_MEMBER_ITEMS) do
        local member = members[i]
        local prefix = 'item_' .. i .. '_'
        data[prefix .. 'aid'] = member.aid or 0
        data[prefix .. 'name'] = member.nickname or member.name or ''
        data[prefix .. 'state'] = member.state or ''
        data[prefix .. 'score'] = member.score or 0
        data[prefix .. 'is_captain'] = bob.team_info.captain == member.aid
    end
    return data
end

function M.get_chat_history()
    local bob = get_bob()
    local history = bob and bob.message_history or {}
    local data = {
        count = #history,
        chat_json = safe_json(history),
    }
    local first = math.max(1, #history - MAX_CHAT_ITEMS + 1)
    local index = 0
    for i = first, #history do
        index = index + 1
        local item = history[i]
        local prefix = 'item_' .. index .. '_'
        data[prefix .. 'message'] = item.message or ''
        data[prefix .. 'time'] = item.time or 0
        data[prefix .. 'channel'] = item.type or (item.chat and item.chat.chat_type) or 0
        data[prefix .. 'sender_aid'] = item.chat and item.chat.sender and item.chat.sender.aid or 0
        data[prefix .. 'sender_name'] = item.chat and item.chat.sender and item.chat.sender.nickname or ''
    end
    return data
end

function M.get_dungeon_token()
    return {
        dungeon_token = MatchTestGetDungeonToken and MatchTestGetDungeonToken() or '',
    }
end

local function register(name, params, callback)
    local definition = y3.eca.def(name)
    for _, param in ipairs(params or {}) do
        definition:with_param(param[1], param[2])
    end
    definition:with_return('结果', 'table'):call(callback)
end

register('大厅服务 - 重建大厅连接', nil, M.rebuild_connection)
register('大厅服务 - 设置匹配分数', { { '分数', 'integer' } }, M.set_score)
register('大厅服务 - 创建队伍', nil, M.create_team)
register('大厅服务 - 加入队伍', { { '队伍编号', 'integer' } }, M.join_team)
register('大厅服务 - 离开队伍', nil, M.leave_team)
register('大厅服务 - 解散队伍', nil, M.dismiss_team)
register('大厅服务 - 转移队长', { { '目标AID', 'integer' } }, M.change_captain)
register('大厅服务 - 移出队员', { { '目标AID', 'integer' } }, M.kick_member)
register('大厅服务 - 开始匹配', { { '分数', 'integer?' } }, M.start_match)
register('大厅服务 - 取消匹配', nil, M.cancel_match)
register('大厅服务 - 创建私人副本', nil, M.create_private_dungeon)
register('大厅服务 - 启动多人私人副本', nil, M.start_private_dungeon)
register('大厅服务 - 加入口令副本', { { '副本口令', 'string' } }, M.join_private_dungeon)
register('大厅服务 - 返回大厅', nil, M.return_lobby)
register('大厅服务 - 退出游戏', nil, M.exit_game)
register('大厅服务 - 发送队伍聊天', { { '消息', 'string' } }, M.send_team_chat)
register('大厅服务 - 发送世界聊天', { { '消息', 'string' } }, M.send_world_chat)
register('大厅服务 - 获取状态快照', nil, M.request_state)
register('大厅服务 - 获取队伍成员', nil, M.get_members)
register('大厅服务 - 获取聊天记录', nil, M.get_chat_history)
register('大厅服务 - 获取副本口令', nil, M.get_dungeon_token)

runtime.module = M
return M
