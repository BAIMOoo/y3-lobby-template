local work = require 'pub.core.service.client'

---@diagnostic disable-next-line: deprecated
local local_player = y3.player.get_local()

---@enum(key) Bob.PlayerState
local player_state = {
    ['空闲'] = 1,
    ['匹配中'] = 2,
    ['游戏中'] = 3,
}

---@enum(key) Bob.TeamState
local team_state = {
    ['空闲'] = 1,
    ['匹配中'] = 2,
}

---@enum(key) Bob.LeaveReason
local leave_reason = {
    ['离开'] = 1,
    ['踢出'] = 2,
    ['解散'] = 3,
}

---@alias Bob.State
---| 'none'
---| 'connecting'
---| 'connected'
---| 'disconnect'
---| 'login'

---@class Bob: CustomEvent, GCHost
---@field event_on fun(self: Bob, event: '准备就绪', callback: fun(trg: Trigger)): Trigger
---@field event_on fun(self: Bob, event: '在线状态变化', callback: fun(trg: Trigger, state: Bob.State)): Trigger
---@field event_on fun(self: Bob, event: '匹配状态变化', callback: fun(trg: Trigger, state: boolean)): Trigger
---@field event_on fun(self: Bob, event: '启动状态变化', callback: fun(trg: Trigger, state: boolean)): Trigger
---@field event_on fun(self: Bob, event: '收到消息', callback: fun(trg: Trigger, data: Bob.ChatInfo)): Trigger
---@field event_on fun(self: Bob, event: '队伍变化', callback: fun(trg: Trigger, data: Bob.TeamInfo)): Trigger
---@field event_on fun(self: Bob, event: '加入队伍', callback: fun(trg: Trigger)): Trigger
---@field event_on fun(self: Bob, event: '离开队伍', callback: fun(trg: Trigger, reason: Bob.LeaveReason, last_team_info: Bob.TeamInfo)): Trigger
---@field event_on fun(self: Bob, event: '有人加入队伍', callback: fun(trg: Trigger, data: Bob.PlayerInfo)): Trigger
---@field event_on fun(self: Bob, event: '有人离开队伍', callback: fun(trg: Trigger, data: Bob.PlayerInfo)): Trigger
---@field event_on fun(self: Bob, event: '客户端需要更新', callback: fun(trg: Trigger)): Trigger
---@overload fun():Bob
local M = Class 'Bob'

local CHANNEL_OP_JOIN = 2
local WORLD_CHANNEL_TYPE = 5
local WORLD_CHANNEL_ID = 10000

Extends('Bob', 'CustomEvent')
Extends('Bob', 'GCHost')

---@type Bob.State
M.state = 'none'

---@type string
M.ip = ''
---@type integer
M.port = 0
---@type string
M.token = nil

--我的分数
M.score = 0

---@alias Bob.ChatType '聊天' | '系统'

---@class Bob.ChatInfo
---@field mode Bob.ChatType
---@field time integer
---@field message string
---@field chat? Bob.ChatData

function M:__init()
    log.debug('【BOB】正在初始化bob')
    --我的平台唯一id
    self.aid = local_player:get_platform_id()
    log.debug('【BOB】aid:', self.aid)
    --我的昵称
    self.name = local_player:get_platform_name()
    log.debug('【BOB】name:', self.name)
    --我的头像
    self.icon = local_player:get_platform_icon_url()
    log.debug('【BOB】icon:', self.icon)
    --我的商城token
    pcall(function()
        local store_params = local_player.handle:api_get_role_store_params()
        if store_params ~= '' then
            self.token = y3.json.decode(store_params).sign
        end
        log.debug('【BOB】token:', self.token)
        --地图版本
        self.map_id = GameAPI.get_dungeon_info and tostring(GameAPI.get_dungeon_info().map_id) or ''
        log.debug('【BOB】map_id:', self.map_id)
        --还不知道这个怎么来
        self.game_play_id = GameAPI.get_dungeon_info and tostring(GameAPI.get_dungeon_info().game_play_id) or ''
        --本地多开下, 该值不是一个数字, 取固定10000
        local num = tonumber(self.game_play_id) or 10000
        self.game_play_id_num = math.floor(num)
        log.debug('【BOB】game_play_id:', self.game_play_id)
        --关卡id
        self.level_id = GameAPI.get_dungeon_info and GameAPI.get_dungeon_info().level_id or ''
        log.debug('【BOB】level_id:', self.level_id)
    end)
    --缓存请求回包处理
    ---@private
    self.request_handlers = {}
    --收到的聊天
    ---@type Bob.ChatInfo[]
    self.message_history = {}
    --已知的玩家信息
    ---@private
    ---@type table<integer, Bob.PlayerInfo>
    self.player_infos = {}

    if y3.game.is_debug_mode() then
        self.game_play_id_num = 188836
    end

    --正式大厅 UI 是可选的；测试地图没有这些节点时仍需正常派发聊天事件。
    self.chat_event = self:event_on('收到消息', function(trg, data)
        y3.player.with_local(function(local_player)
            local ok, chat_text = pcall(self.format_message, self, data)
            if not ok then
                chat_text = tostring(data.message or '')
            end
            log.debug('收到消息', chat_text)

            pcall(function()
                local ui = y3.ui.get_ui(local_player, '[0]F1_main_hall.[16]chat')
                local prefab = y3.ui_prefab.create(local_player, 'chat_text', ui)
                local text = prefab and prefab:get_child()
                if text then
                    text:set_text(chat_text)
                end
                ui:set_slider_value(1)
            end)

            if local_player.uiGM then
                if data.chat then
                    local_player.uiGM:show_one_chat(data.chat.chat_type, chat_text)
                else
                    local_player.uiGM:show_one_chat(4, chat_text)
                end
            end
        end)
    end)
end

function M:__del()
    if self.client then
        Delete(self.client)
    end
    if self.chat_event then
        self.chat_event:remove()
    end
end

---@private
M._in_game = false

---@param in_game boolean
function M:set_in_game(in_game)
    log.debug('【BOB】设置游戏状态：', in_game)
    self._in_game = in_game
end

function M:start()
    if not IsValid(self) then
        return
    end
    log.debug('【BOB】启动匹配系统')
    self:check_update(function(need_update)
        if need_update then
            log.debug('【BOB】启动失败：客户端需要更新')
            self:event_notify('客户端需要更新')
        else
            if not IsValid(self) then
                return
            end
            --真正的客户端对象
            ---@private
            local ok, client = pcall(work.new_client, self.ip, self.port, self.aid, self.token, self.game_play_id_num)
            if not ok then
                log.warn('【BOB】启动失败：自定义协议不可用，匹配与RPC功能已禁用', client)
                self:event_notify('匹配服务不可用', client)
                return
            end
            self.client = client
            self:register_methods()
            self.client:start()
        end
    end)
end

---@private
function M:login()
    log.debug('【BOB】开始登录')
    self:request_login(function(result, err)
        if err then
            log.debug('【BOB】登录错误：', y3.inspect(err))
            return
        end
        self:get_team_info(self.aid, function(result, team_err)
            if team_err then
                log.warn('【BOB】登录后获取队伍信息失败：', team_err)
                return
            end
            self.team_info = result
            self:refresh_player_info(function(_, refresh_err)
                if refresh_err then
                    log.warn('【BOB】登录后更新玩家信息失败：', refresh_err)
                    return
                end
                log.debug('【BOB】发起事件：准备就绪')
                self:event_notify('准备就绪')
            end)
        end)
    end)
end

---@return boolean
function M:is_valid()
    return self.state == 'login'
end

---@private
---@type fun(msg: string)?
M.error_handler = nil

---@param handler fun(msg: string, errid: integer)
function M:set_error_handler(handler)
    self.error_handler = handler
end

---@alias Bob.Receiver fun(result: any, err: any): boolean?

---@private
function M:get_request_handler(id)
    if not self.request_handlers[id] then
        local handler = {
            id = id,
            map = {},
        }
        self.request_handlers[id] = handler
        handler.callback = function(errid, data, arg)
            local receiver = handler.last_receiver
            handler.last_receiver = nil
            if not receiver then
                if handler.token_getter then
                    local token = handler.token_getter(arg.arg1)
                    receiver = handler.map[token]
                    handler.map[token] = nil
                end
            end
            if not receiver then
                log.warn('【BOB】收到无接收者回包，忽略：', id)
                return
            end
            if errid ~= 1 then
                local suc, ignore = xpcall(receiver, log.error, nil, errid)
                if suc and ignore then
                else
                    local msg = string.format('【BOB】请求[%s]失败，error_id = %s', id, errid)
                    log.warn(msg)
                    if self.error_handler then
                        xpcall(self.error_handler, log.error, msg, errid)
                    end
                end
            elseif type(data.ret1) == 'table'
                and ((data.ret1.errnu and data.ret1.errnu ~= 0) or (data.ret1.error_code and data.ret1.error_code ~= 0)) then
                local err = data.ret1.errnu or data.ret1.error_code
                local suc, ignore = xpcall(receiver, log.error, nil, err)
                if suc and ignore then
                else
                    local msg = string.format('【BOB】请求[%s]失败，err = %s, data = %s', id, err, tostring(data.ret1.data))
                    log.warn(msg)
                    if self.error_handler then
                        xpcall(self.error_handler, log.error, msg, err)
                    end
                end
            else
                log.debug('【BOB】请求成功：', id, '返回值：', y3.inspect(data))
                xpcall(receiver, log.error, data.ret1, nil)
            end
        end
    end
    return self.request_handlers[id]
end

---@private
---@param id string
---@return boolean
function M:can_request(id)
    local handler = self:get_request_handler(id)
    if handler.last_receiver then
        return false
    end
    return true
end

---@private
---@param id string
---@param sender fun()
---@param receiver Bob.Receiver
---@return boolean
function M:request(id, sender, receiver)
    log.debug('【BOB】发起请求', id)
    if not self:can_request(id) then
        log.debug('【BOB】请求失败：', '不能重入')
        receiver(nil, '请求不能重入')
        return false
    end
    local handler = self:get_request_handler(id)
    handler.last_receiver = receiver
    sender()
    return true
end

---@private
---@generic T
---@param id string
---@param sender fun()
---@param receiver Bob.Receiver
---@param token T
---@param token_getter fun(request_data: any):T
function M:request_with_token(id, sender, receiver, token, token_getter)
    log.debug('【BOB】发起请求(带token)', id, token)
    local handler = self:get_request_handler(id)
    handler.map[token] = receiver
    handler.token_getter = token_getter
    sender()
end

---@diagnostic disable-next-line: undefined-field
GameAPI.visual_pyexec([[
import clients.G as G
import shipping

G.black_box.lua_rt.globals()['_SVN_VERSION'] = shipping.CUR_SVN_VERSION
]])

---检查客户端是否需要更新
---@param callback fun(need_update: boolean)
function M:check_update(callback)
    if y3.game.is_debug_mode(true) then
        callback(false)
        return
    end
    if GameAPI.get_dungeon_info().env ~= 'prod' then
        callback(false)
        return
    end

    local timeout = y3.ctimer.wait(5, function(timer, count)
        error('【BOB】请求远端版本号超时！')
    end)

    y3.game:request_url('https://up5.update.netease.com/pl/patchmd5_windows64_produp5_release.txt', nil, function(body)
        timeout:remove()
        if not body then
            callback(false)
            return
        end
        local data = y3.json.decode(body)
        local remote_version = data['2.0']['@metadata@']['@displayversion@']
        local local_version = _G['_SVN_VERSION']
        callback(local_version ~= remote_version)
    end)
end

---@private
---@param done Bob.Receiver
function M:request_login(done)
    log.debug('【BOB】请求登录')
    self:request('Team_Login', function()
        ---@type PlayerInfo
        local data = {
            aid = self.aid,
            head_icon = self.icon,
            name = self.name,
            state = 0,
            score = self.score,
            map_id = self.map_id,
            in_game = self._in_game,
            game_play_id = self.game_play_id_num,
        }
        log.debug('【BOB】Team_Login', y3.inspect(data))
        self.client:Team_Login(data)
    end, function(result, err)
        if err then
            done(nil, err)
            return
        end
        self:subscribe_world_chat(function(_, subscribe_err)
            if subscribe_err then
                done(nil, subscribe_err)
                return
            end
            done(result, nil)
        end)
    end)
end

---@private
---@param done Bob.Receiver
function M:subscribe_world_chat(done)
    self:request('Chat_UpdateChannel', function()
        self.client:ApiRouter_UpdateChannel(
            CHANNEL_OP_JOIN,
            WORLD_CHANNEL_TYPE,
            WORLD_CHANNEL_ID,
            { self.aid },
            self.game_play_id_num
        )
    end, function(result, err)
        if err then
            done(nil, err)
            return
        end
        if result ~= nil and result ~= 0 and result ~= 'default_ErrCode' then
            done(nil, result)
            return
        end
        done(result, nil)
    end)
end

---@private
---@param done? fun(result: any?, err: any?)
function M:refresh_player_info(done)
    log.debug('【BOB】请求更新玩家信息')
    if self._refreshing_player_info then
        log.debug('【BOB】更新玩家信息已在请求中，等待已有回包')
        if done then
            self._refresh_player_info_callbacks = self._refresh_player_info_callbacks or {}
            self._refresh_player_info_callbacks[#self._refresh_player_info_callbacks + 1] = done
        end
        return false
    end
    ---@type PlayerInfo
    local data = {
        aid = self.aid,
        head_icon = self.icon,
        name = self.name,
        state = 0,
        score = self.score,
        map_id = self.map_id,
        in_game = self._in_game,
        game_play_id = self.game_play_id_num,
    }
    self._refreshing_player_info = true
    self._refresh_player_info_callbacks = done and { done } or {}
    local finished = false
    local timeout
    local finish = function(result, err)
        if finished then
            return
        end
        finished = true
        if timeout then
            timeout:remove()
        end
        self._refreshing_player_info = false
        log.debug('【BOB】更新玩家信息回包', y3.inspect({ result = result, err = err }))
        local callbacks = self._refresh_player_info_callbacks or {}
        self._refresh_player_info_callbacks = {}
        for _, callback in ipairs(callbacks) do
            xpcall(callback, log.error, result, err)
        end
    end
    timeout = y3.ctimer.wait(3, function()
        -- 保留占位接收器，避免迟到回包被下一次刷新请求错误消费。
        finish(nil, 'timeout')
        if self.client then
            self.client:reconnect('玩家信息刷新超时')
        end
    end)
    self:request('Team_UpdatePlayerInfo', function()
        log.debug('【BOB】Team_UpdatePlayerInfo', y3.inspect(data))
        self.client:Team_UpdatePlayerInfo(data)
    end, finish)
    return true
end

--创建队伍
---@param done? fun() # 创建完成后调用
---@param member_limit? integer # 队伍人数限制，默认8人
function M:create_team(done, member_limit)
    log.debug('【BOB】尝试创建队伍')
    member_limit = member_limit or 8
    self:check_update(function(need_update)
        if need_update then
            log.debug('【BOB】创建队伍失败：客户端需要更新')
            if done then done() end
        else
            self:request('Team_CreateTeam', function()
                log.debug('【BOB】Team_CreateTeam', self.aid)
                self.client:Team_CreateTeam(self.aid, member_limit)
            end, function(result, err)
                log.debug('【BOB】创建队伍回包', y3.inspect({ result = result, err = err }))
                if done then
                    done()
                end
            end)
        end
    end)
end

--离开队伍
---@param done? fun() # 离开完成后调用
function M:leave_team(done)
    log.debug('【BOB】尝试离开队伍')
    if self:is_matching() or self:is_launching() then
        log.debug('【BOB】离开队伍失败：正在匹配中或启动中')
        if done then done() end
        return
    end
    self:request('Team_LeaveTeam', function()
        log.debug('【BOB】Team_LeaveTeam', self.aid)
        self.client:Team_LeaveTeam(self.aid)
    end, function(result, err)
        log.debug('【BOB】离开队伍回包', y3.inspect({ result = result, err = err }))
        if done then
            done()
        end
    end)
end

--加入队伍
---@param team_id integer
---@param done? fun() # 加入完成后调用
function M:join_team(team_id, done)
    log.debug('【BOB】尝试加入队伍', team_id)
    if self:is_matching() or self:is_launching() then
        log.debug('【BOB】加入队伍失败：正在匹配中或启动中')
        if done then done() end
        return
    end
    self:check_update(function(need_update)
        if need_update then
            log.debug('【BOB】加入队伍失败：客户端需要更新')
            if done then done() end
        else
            self:request('Team_JoinTeam', function()
                log.debug('【BOB】Team_JoinTeam', self.aid, team_id)
                self.client:Team_JoinTeam(self.aid, team_id)
            end, function(result, err)
                log.debug('【BOB】加入队伍回包', y3.inspect({ result = result, err = err }))
                if done then
                    done()
                end
            end)
        end
    end)
end

--解散队伍
---@param done? fun() # 解散完成后调用
function M:dismiss_team(done)
    log.debug('【BOB】尝试解散队伍')
    if self:is_matching() or self:is_launching() then
        log.debug('【BOB】解散队伍失败：正在匹配中或启动中')
        if done then done() end
        return
    end
    self:request('Team_DismissTeam', function()
        log.debug('【BOB】Team_DismissTeam', self.aid)
        self.client:Team_DismissTeam(self.aid)
    end, function(result, err)
        log.debug('【BOB】解散队伍回包', y3.inspect({ result = result, err = err }))
        if done then
            done()
        end
    end)
end

--踢出队伍
---@param lick_aid integer
function M:team_kick(lick_aid)
    log.debug('【BOB】尝试踢出队伍', lick_aid)
    if self:is_matching() or self:is_launching() then
        log.debug('【BOB】踢出队伍失败：正在匹配中或启动中')
        return
    end
    log.debug('【BOB】Team_TeamKick', self.aid, lick_aid)
    self.client:Team_TeamKick(self.aid, lick_aid)
end

--转移队长
---@param new_leader_aid integer
---@param done? fun() # 转移完成后调用
function M:change_captain(new_leader_aid, done)
    log.debug('【BOB】尝试转移队长', new_leader_aid)
    if self:is_matching() or self:is_launching() then
        log.debug('【BOB】转移队长失败：正在匹配中或启动中')
        return
    end
    self:request('Team_ChangeTeamLeader', function()
        log.debug('【BOB】Team_ChangeTeamLeader', self.aid, new_leader_aid)
        self.client:Team_ChangeTeamLeader(self.aid, new_leader_aid)
    end, function(result, err)
        log.debug('【BOB】转移队长回包', y3.inspect({ result = result, err = err }))
        if done then
            done()
        end
    end)
end

--多开战场
function M:create_multi_battle_space(battle_info)
    log.debug('【BOB】尝试多开战场', y3.inspect(battle_info))
    self.client:BattleCreate_CreateMultiBattleSpace(battle_info)
end

---@class Bob.PlayerInfo
---@field aid integer
---@field head_icon string
---@field name string
---@field team_id integer
---@field score integer
---@field state Bob.PlayerState

---@class Bob.TeamInfo
---@field member_limit integer
---@field team_id integer
---@field team_state Bob.TeamState
---@field captain integer
---@field members Bob.PlayerInfo[]
---@field version integer

function M:convert_player_info(player_info)
    if player_info.in_game then
        player_info.state = '游戏中'
    else
        for key, state in pairs(player_state) do
            if state == player_info.state then
                player_info.state = key
                break
            end
        end
    end
    self.player_infos[player_info.aid] = player_info
end

---@private
---@param team_info table
---@return Bob.TeamInfo
function M:convert_team_info(team_info)
    for key, state in pairs(team_state) do
        if state == team_info.state then
            team_info.team_state = key
            break
        end
    end
    for _, player_info in ipairs(team_info.members) do
        self:convert_player_info(player_info)
    end
    return team_info
end

--获取队伍信息
---@param aid integer
---@param response fun(result: Bob.TeamInfo?, err: any?)
function M:get_team_info(aid, response)
    log.debug('【BOB】请求队伍信息', aid)
    self:request_with_token('Team_GetTeamInfoByAid', function()
        log.debug('【BOB】Team_GetTeamInfoByAid', aid)
        self.client:Team_GetTeamInfoByAid(aid)
    end, function(result, err)
        if not result then
            --PLAYER_HAS_NO_TEAM
            if err == 1402 then
                log.debug('【BOB】玩家没有队伍')
                response(nil, nil)
                return true
            end
            log.debug('【BOB】获取队伍信息失败：', y3.inspect(err))
            response(nil, err)
            return
        end
        local team_info = self:convert_team_info(result.team_info)
        log.debug('【BOB】获取队伍信息成功：', y3.inspect(team_info))
        response(team_info)
    end, aid, function(arg)
        return arg
    end)
end

--获取玩家信息
---@param aid integer
---@param done fun(result: Bob.PlayerInfo?)
function M:get_player_info(aid, done)
    log.debug('【BOB】请求玩家信息', aid)
    if self.player_infos[aid] then
        log.debug('【BOB】从缓存中掏出玩家信息', y3.inspect(self.player_infos[aid]))
        done(self.player_infos[aid])
        return
    end
    log.debug('【BOB】将通过队伍信息获取玩家信息', aid)
    self:get_team_info(aid, function(team_info)
        log.debug('【BOB】获取玩家信息成功：', y3.inspect(self.player_infos[aid]))
        done(self.player_infos[aid])
    end)
end

--是否可以匹配
---@return boolean
---@return ('不是队长' | '正在匹配' | '失去连接' | '有人在游戏中' | '有人在匹配' | '正在启动')?
function M:can_match()
    if self.team_info and not self:is_captain() then
        return false, '不是队长'
    end
    if self:is_matching() then
        return false, '正在匹配'
    end
    if self:is_launching() then
        return false, '正在启动'
    end
    if not self:is_valid() then
        return false, '失去连接'
    end
    if self.team_info then
        for _, member in ipairs(self.team_info.members) do
            if member.state == '游戏中' then
                return false, '有人在游戏中'
            end
            if member.state == '匹配中' then
                return false, '有人在匹配'
            end
        end
    end
    return true
end

---@private
M._matching_state = false

---@private
function M:update_matching_state()
    local matching_state = self:is_matching()
    if matching_state == self._matching_state then
        return false
    end
    self._matching_state = matching_state
    log.debug('【BOB】匹配状态变化：', local_player, matching_state)
    self:event_notify('匹配状态变化', matching_state)
    return true
end

--是否正在匹配
function M:is_matching()
    if self.team_info then
        if self.team_info.team_state == '匹配中' then
            return true
        else
            return false
        end
    else
        local self_info = self.player_infos[self.aid]
        if self_info and self_info.state == '匹配中' then
            return true
        end
    end
    return false
end

---@private
M._is_launching = false

---是否正在启动游戏
function M:is_launching()
    return self._is_launching
end

---@private
---@param game_mode integer # 匹配成功后进入的游戏模式
---@param score integer? # 匹配分数，默认使用平均分
---@param done? fun()
function M:_start_match(game_mode, score, done)
    ---@private
    self:update_matching_state()
    log.debug('【BOB】开始请求匹配')
    self:request('Match_startMatch', function()
        ---@type MatchInfo
        local match_info = {
            map_id = self.map_id,
            level_id = self.level_id,
            game_mode = game_mode,
            game_play_id = self.game_play_id,
        }
        if self.team_info then
            log.debug('【BOB】在队伍中')
            if not score then
                score = 0
                for _, player_info in ipairs(self.team_info.members) do
                    score = score + player_info.score
                end
                score = score // #self.team_info.members
                log.debug('【BOB】没有设置分数，使用队伍平均分', score)
            end
            log.debug('【BOB】Match_startMatch', self.team_info.team_id, score, true, y3.inspect(match_info))
            self.client:Match_startMatch(self.team_info.team_id, score, true, match_info)
        else
            log.debug('【BOB】不在队伍中')
            log.debug('【BOB】Match_startMatch', self.aid, score or self.score, false, y3.inspect(match_info))
            self.client:Match_startMatch(self.aid, score or self.score, false, match_info)
        end
    end, function(result, err)
        log.debug('【BOB】开始匹配回包', y3.inspect({ result = result, err = err }))
        if done then done() end
    end)
end

--开始匹配
---@param game_mode integer # 匹配成功后进入的游戏模式
---@param score integer? # 匹配分数，默认使用平均分
---@param done? fun()
function M:start_match(game_mode, score, done)
    log.debug('【BOB】尝试开始匹配', game_mode, score)
    if not self:can_match() then
        log.debug('【BOB】开始匹配失败：', self:can_match())
        if done then done() end
        return
    end
    self:check_update(function(need_update)
        if need_update then
            log.debug('【BOB】开始匹配失败：客户端需要更新')
            if done then done() end
        else
            self:_start_match(game_mode, score, done)
        end
    end)
end

--取消匹配
---@param done? fun() # 取消完成后调用
function M:cancel_match(done)
    log.debug('【BOB】尝试取消匹配')
    self:request('Match_cancelMatch', function()
        log.debug('【BOB】Match_cancelMatch', self.team_info and self.team_info.team_id or self.aid)
        self.client:Match_cancelMatch(self.team_info and self.team_info.team_id or self.aid)
    end, function(result, err)
        log.debug('【BOB】取消匹配回包', y3.inspect({ result = result, err = err }))
        if done then
            done()
        end
    end)
end

--发送聊天消息
---@param message string
---@return boolean, string|nil
function M:send_chat(message)
    log.debug('【BOB】发送聊天消息', message)
    if not self.team_info or not self.team_info.team_id or self.team_info.team_id == 0 then
        return false, '当前不在队伍中'
    end
    return self.client:ApiRouter_SendChatMsg(
        self.aid
        , message
        , 4
        , self.team_info.team_id
        , 0
    )
end

--发送世界聊天消息
---@param message string
---@return boolean, string|nil
function M:send_world_chat(message)
    log.debug('【BOB】发送世界聊天消息', message)
    return self.client:ApiRouter_SendChatMsg(
        self.aid
        , message
        , WORLD_CHANNEL_TYPE
        , WORLD_CHANNEL_ID
        , 0
    )
end

--多人切换副本
---@param dungeon_info DungeonSpaceField
---@param players DungeonPlayerField[]
function M:start_privat_dungeon_game(dungeon_info, players)
    log.debug('【BOB】发送私人副本消息', dungeon_info, players)
    self.client:DungeonManager_StartMatchPrivateDungeonGame(dungeon_info, players)
end

--格式化聊天消息
---@param chat_data Bob.ChatInfo
---@return string
function M:format_message(chat_data)
    if chat_data.mode == '系统' then
        return string.format('[%s]<系统>: %s'
        , os.date('%H:%M:%S', chat_data.time)
        , chat_data.message)
    else
        local chat_type = {
            [4] = '房',
            [5] = '世',
        }
        return string.format('[%s][%s]<#fafe06%s#E>: %s'
        , os.date('%H:%M:%S', chat_data.time)
        , chat_type[chat_data.chat.chat_type]
        , chat_data.chat.sender.nickname
        , chat_data.message)
    end
end

--发送系统消息
---@param message string
function M:display_message(message)
    local message_info = {
        mode    = '系统',
        message = message,
        time    = os.time(),
    }
    self.message_history[#self.message_history + 1] = message_info
    log.debug('【BOB】收到<系统>消息', y3.inspect(message_info))
    self:event_notify('收到消息', message_info)
end

--我是否在队伍中
function M:is_in_team()
    return self.team_info ~= nil
end

--我是否是队长
function M:is_captain()
    if not self.team_info then
        return false
    end
    return self.team_info.captain == self.aid
end

--修改自己的分数
---@param score integer
function M:set_score(score)
    log.debug('【BOB】设置分数', score)
    self.score = score
    if self.state == 'login' then
        self:refresh_player_info()
    else
        self:event_on('准备就绪', function(trg)
            trg:remove()
            self:refresh_player_info()
        end)
    end
end

---@class Bob.ChatData
---@field sender ChatSender # 发送者信息
---@field chat_message string # 聊天消息
---@field chat_time integer # 时间戳
---@field chat_type integer # 信息类型

---@private
---@param chat_data Bob.ChatData
---@return Bob.ChatInfo
function M:record_chat(chat_data)
    local message_info = {
        mode    = '聊天',
        message = chat_data.chat_message,
        time    = chat_data.chat_time,
        type    = chat_data.chat_type,
        chat    = chat_data,
    }
    self.message_history[#self.message_history + 1] = message_info
    log.debug('【BOB】记录<聊天>消息', y3.inspect(message_info))
    self:event_notify('收到消息', message_info)
    return message_info
end

---@private
---@param message string
---@param chat_type integer
function M:display_local_chat(message, chat_type)
    self:record_chat({
        sender = {
            aid = self.aid,
            nickname = self.name,
            head_icon = self.icon,
        },
        chat_message = message,
        chat_time = os.time(),
        chat_type = chat_type,
    })
end

---@private
function M:notify_chat(data)
    ---@type Bob.ChatData
    local chat_data = data.arg1
    if chat_data.sender and chat_data.sender.aid == self.aid then
        log.debug('【BOB】忽略已由成功回包显示的自身聊天消息', y3.inspect(chat_data))
        return
    end
    self:record_chat(chat_data)
end

---@private
function M:notify_update_team_info(data)
    local old_team_info = self.team_info
    log.debug('【BOB】收到新的队伍信息', y3.inspect(data.arg1.team_info))
    log.debug('【BOB】当前的队伍信息', y3.inspect(old_team_info))

    if old_team_info and old_team_info.version > data.arg1.team_info.version then
        log.debug('【BOB】新的队伍信息版本过低，忽略')
        return
    end

    --当前所在的队伍信息
    local new_team_info = self:convert_team_info(data.arg1.team_info)
    self.team_info = new_team_info
    log.debug('【BOB】触发队伍变化', y3.inspect(new_team_info))
    self:event_notify('队伍变化', new_team_info)

    if not old_team_info or old_team_info.team_id ~= new_team_info.team_id then
        log.debug('【BOB】触发加入队伍')
        self:event_notify('加入队伍')
        return
    end

    local old_members = {}
    local new_members = {}
    if old_team_info then
        for _, member in ipairs(old_team_info.members) do
            old_members[member.aid] = true
        end
    end
    for _, member in ipairs(new_team_info.members) do
        new_members[member.aid] = true
    end

    if old_team_info then
        for _, member in ipairs(old_team_info.members) do
            if not new_members[member.aid] and member.aid ~= self.aid then
                log.debug('【BOB】触发有人离开队伍', y3.inspect(member))
                self:event_notify('有人离开队伍', member)
            end
        end
    end

    for _, member in ipairs(new_team_info.members) do
        if not old_members[member.aid] and member.aid ~= self.aid then
            log.debug('【BOB】触发有人加入队伍', y3.inspect(member))
            self:event_notify('有人加入队伍', member)
        end
    end
end

---@private
function M:notify_leave_team(data)
    log.debug('【BOB】收到离开队伍通知', y3.inspect(data))
    local last_team_info = self.team_info
    self.team_info = nil
    local reason = '未知'
    if data.arg1 == 1 then
        reason = '离开'
    elseif data.arg1 == 2 then
        reason = '踢出'
    elseif data.arg1 == 3 then
        reason = '解散'
    end
    log.debug('【BOB】触发离开队伍', reason, y3.inspect(last_team_info))
    self:event_notify('离开队伍', reason, last_team_info)
    self:update_matching_state()
end

---@private
function M:notify_player_info(data)
    ---@type PlayerInfo
    local player_info = data.arg1
    self:convert_player_info(player_info)
    log.debug('【BOB】收到玩家信息', y3.inspect(player_info))
    self:update_matching_state()

    if player_info.state_change_reason == 1 then
        log.debug('【BOB】正在启动游戏')
        self._is_launching = true
        self:event_notify('启动状态变化', self._is_launching)
        y3.ctimer.wait(10, function()
            log.warn('【BOB】未能在10秒内启动游戏！')
            self._is_launching = false
            self:event_notify('启动状态变化', self._is_launching)
        end)
    end
end

---@private
function M:notify_battle_info(data)
    local battle_info = data.arg1
    log.debug('【BOB】收到战场信息', y3.inspect(battle_info))
end

---@private
function M:notify_state_change(state)
    if state == 'disconnect' then
        -- 连接已关闭，不会再收到旧连接回包；结束所有待处理请求后允许重连重新发起。
        local receivers = {}
        for _, handler in pairs(self.request_handlers) do
            local receiver = handler.last_receiver
            local token_receivers = handler.map
            handler.last_receiver = nil
            handler.map = {}
            if receiver then
                receivers[#receivers + 1] = receiver
            end
            for _, token_receiver in pairs(token_receivers) do
                receivers[#receivers + 1] = token_receiver
            end
        end
        for _, receiver in ipairs(receivers) do
            xpcall(receiver, log.error, nil, '连接断开')
        end
    end
    self.state = state
    if state == 'login' then
        self:login()
    end
    log.debug('【BOB】在线状态变化', state)
    self:event_notify('在线状态变化', state)
end

---@private
function M:notify_ret(method_name, errid, arg, ret)
    if method_name == 'Chat_SendChatMsg' then
        local ret1 = ret and ret.ret1
        local business_error = type(ret1) == 'table'
            and ((ret1.errnu and ret1.errnu ~= 0) or (ret1.error_code and ret1.error_code ~= 0))
        if errid == 1 and not business_error then
            self:display_local_chat(arg.arg2, arg.arg3)
        end
    end
    local handler = self.request_handlers[method_name]
    if handler then
        handler.callback(errid, ret, arg)
    end
end

---@private
function M:register_methods()
    self.client:on_event(function(event, ...)
        if event == 'connecting'
            or event == 'connected'
            or event == 'login'
            or event == 'disconnect' then
            self:notify_state_change(event)
            return
        end
        if event == 'chat' then
            self:notify_chat(...)
            return
        end
        if event == 'update_team_info' then
            self:notify_update_team_info(...)
            return
        end
        if event == 'leave_team' then
            self:notify_leave_team(...)
            return
        end
        if event == 'notify_player_info' then
            self:notify_player_info(...)
            return
        end
        if event == 'notify_battle_info' then
            self:notify_battle_info(...)
            return
        end
        if event == 'ret' then
            self:notify_ret(...)
            return
        end
    end)
end

local p_count = 8
---comment
---@return integer,integer
function M:get_player_count()
    local team_count = 0
    for i = 1, p_count do
        local member = self.team_info and self.team_info.members[i]
        if member then
            team_count = team_count + 1
        end
    end
    return team_count, p_count
end

---玩家
function M:create_room()
    local player_data = y3.save_data.load_table(local_player, 2, true)
    if not player_data.game_stats or player_data.game_stats.total_games == 0 then
        self:event_on('准备就绪', function(trg)
            self:start_ai(false)

            y3.timer.wait(5, function(timer)
                local_player.SquadUi:shelters_hide()
            end)
        end)
    else
        y3.timer.wait(2, function(timer)
            local_player.SquadUi:shelters_hide()
        end)
    end
end

---运行人机模式
---@param is_ai boolean
function M:start_ai(is_ai)
    local team_count, max = BOB:get_player_count()
    if team_count > 1 then
        local_player.MainTips:create_active_mouse_tips('人机模式只能单人体验哦')
        return
    elseif self:is_matching() then
        local_player.MainTips:create_active_mouse_tips('匹配中，请耐心等待')
        return
    end
    xpcall(function()
        y3.ui.get_ui(local_player, '[0]F1_main_hall.[1]layout_match_function.button_join_room'):set_visible(false)
        y3.ui.get_ui(local_player, '[0]F1_main_hall.[1]layout_match_function.button_create_room'):set_visible(false)
        y3.ui.get_ui(local_player, '[0]F1_main_hall.[1]layout_match_function.button_match'):set_button_enable(false)
        y3.ui.get_ui(local_player, '[0]F1_main_hall.[1]layout_match_function.button_ai_match'):set_button_enable(false)

        print('触发了人机模式：', is_ai)

        if is_ai then
            local_player.PlayerSave:set_game_model('人机模式')
        else
            local_player.PlayerSave:set_game_model('单人匹配')
        end
        local_player.handle:request_create_private_dungeon(y3.game.get_level(), 1002, 1)

        y3.timer.wait(3, function(timer)
            if not self:is_launching() and not self:is_matching() then
                y3.ui.get_ui(local_player, '[0]F1_main_hall.[1]layout_match_function.button_join_room'):set_visible(true)
                y3.ui.get_ui(local_player, '[0]F1_main_hall.[1]layout_match_function.button_create_room'):set_visible(true)
                y3.ui.get_ui(local_player, '[0]F1_main_hall.[1]layout_match_function.button_match'):set_button_enable(true)
                y3.ui.get_ui(local_player, '[0]F1_main_hall.[1]layout_match_function.button_ai_match'):set_button_enable(true)
            end
        end)
    end, log.warn)
end

-- function M:create_room()
--     local player_count = 0
--     local min_id = 10
--     for index, p in pairs(y3.player_group:get_all_players():pick()) do
--         if p and p:get_controller() == y3.const.RoleType.USER and p:get_state() == y3.const.RoleStatus['PLAYING'] then
--             player_count = player_count + 1
--             if p:get_id() < min_id then
--                 min_id = p:get_id()
--             end
--         end
--     end

--     -- 玩家进入游戏后 根据人数判定是否走 组队逻辑
--     if player_count > 1 then
--         -- local ctra
--         if min_id == local_player:get_id() then
--             -- 确定人数大于 1 并且自己是队长

--             local create_room = function(fun)
--                 y3.timer.wait(0.2, function(timer)
--                     self:create_team(nil, 8)
--                     self:event_on('队伍变化', function(create_team_trg, data)
--                         print('RoomNew:队伍变化 创建房间完成', data.team_state, data.team_id)
--                         if data.team_state == "空闲" then
--                             y3.timer.wait(0.2, function(_)
--                                 if self:is_in_team() then
--                                     y3.sync.send('join_the_team', {
--                                         team_id = data.team_id,
--                                     })
--                                 end
--                             end)

--                             create_team_trg:remove()
--                         end
--                     end)

--                     if fun then
--                         fun()
--                     end
--                     local_player.SquadUi:shelters_hide()
--                 end)
--             end

--             -- 玩登录完成
--             self:event_on('准备就绪', function(trg)
--                 print('RoomNew:准备就绪 准备就绪')
--                 if self:is_in_team() then
--                     -- 有队伍 先进行离开 再创建队伍
--                     print('RoomNew:有队伍')
--                     self:leave_team()
--                     self:event_on('离开队伍', function(team_trg, type)
--                         if type == '离开' then
--                             create_room()
--                             team_trg:remove()
--                         end
--                     end)
--                 else
--                     print('RoomNew:没有队伍')
--                     create_room()
--                 end
--                 trg:remove()
--             end)
--         else
--             local team_id
--             local login_bool = false

--             local function join_team()
--                 y3.timer.wait(0.2, function(timer)
--                     if login_bool and team_id then
--                         print('RoomNew:触发了 加入房间', local_player, team_id)
--                         self:join_team(team_id)
--                         local_player.SquadUi:shelters_hide()
--                     end
--                 end)
--             end

--             -- 玩登录完成
--             self:event_on('准备就绪', function(trg_2)
--                 print('RoomNew:准备就绪 准备就绪')
--                 y3.timer.wait(0.2, function(timer)
--                     if self:is_in_team() then
--                         self:leave_team()
--                         self:event_on('离开队伍', function(team_trg, type)
--                             print('RoomNew:触发 离开队伍')
--                             if type == '离开' then
--                                 login_bool = true
--                                 join_team()
--                                 team_trg:remove()
--                             end
--                         end)
--                     else
--                         login_bool = true
--                         join_team()
--                     end
--                     trg_2:remove()
--                 end)
--             end)

--             y3.sync.onSync('join_the_team', function(data, source)
--                 if data and data.team_id then
--                     team_id = data.team_id
--                     join_team()
--                 end
--             end)
--         end
--     else
--         y3.timer.wait(2, function(timer)
--             local_player.SquadUi:shelters_hide()
--         end)
--     end
-- end
