---@class PubUI
local M = {}

local MATCH_GAME_MODE = 1002
local PRIVATE_GAME_MODE = 1003
-- DungeonPlayerField.version 是多人副本 RPC 的必填字段，当前协议版本固定为 2.0。
local DUNGEON_PLAYER_VERSION = '2.0'

--组队系统
local MAIN = y3.local_ui.create('[0]F1_main_hall')

local MEMBER = y3.local_ui.prefab('layout_player_block_leader')

MEMBER:on_refresh('', function(ui, local_player, instance)
    if BOB.team_info then
        ui:set_visible(true)
    else
        ui:set_visible(false)
    end
    local index = instance:storage_get('index')
    ui:set_pos(300, 860 - 80 * index)
end)

MEMBER:on_refresh('leader', function(ui, local_player, instance)
    local index = instance:storage_get('index')
    local member = BOB.team_info and BOB.team_info.members[index]
    if not member then
        ui:set_visible(false)
        return
    end
    if member.aid == BOB.team_info.captain then
        ui:get_child('leader_icon'):set_visible(true)
        ui:get_child('assignor'):set_visible(false)
    else
        ui:get_child('leader_icon'):set_visible(false)
        ui:get_child('assignor'):set_visible(true)
    end
end)

MEMBER:on_refresh('layout_leader_info_block.head_icon.image_head_icon', function(ui, local_player, instance)
    local index = instance:storage_get('index')
    local member = BOB.team_info and BOB.team_info.members[index]
    if not member then
        return
    end
    ui:set_image_url(member.head_icon)
end)

MEMBER:on_refresh('layout_leader_info_block.label_player_name', function(ui, local_player, instance)
    local index = instance:storage_get('index')
    local member = BOB.team_info and BOB.team_info.members[index]
    if not member then
        return
    end
    ui:set_text(member.name)
end)

MEMBER:on_refresh('layout_leader_info_block.image_mark_bg.label_mark', function(ui, local_player, instance)
    local index = instance:storage_get('index')
    local member = BOB.team_info and BOB.team_info.members[index]
    if not member then
        ui:set_text('伪人')
        return
    end
    if member.state == '空闲' then
        ui:set_text('就绪')
    else
        ui:set_text(member.state)
    end
end)

MEMBER:on_refresh('leader.assignor', function(ui, local_player, instance)
    local index = instance:storage_get('index')
    local member = BOB.team_info and BOB.team_info.members[index]
    if not member then
        return
    end
    if BOB:is_captain() and BOB.aid ~= member.aid then
        ui:set_visible(true)
    else
        ui:set_visible(false)
    end
end)

MEMBER:on_refresh('kick_out', function(ui, local_player, instance)
    local index = instance:storage_get('index')
    local member = BOB.team_info and BOB.team_info.members[index]
    if not member then
        return
    end
    if BOB:is_captain() and BOB.aid ~= member.aid then
        ui:set_visible(true)
    else
        ui:set_visible(false)
    end
end)

MAIN:bind_prefab('[9_2]layout_team_info.grid_view_team', MEMBER)

-- MAIN:on_init('玩家信息.玩家名字文本', function (ui, local_player, instance)
--     ui:set_text(BOB.name)
-- end)

-- MAIN:on_init('玩家信息.头像区域.头像裁剪.头像', function (ui, local_player, instance)
--     ui:set_image_url(BOB.icon)
-- end)

MAIN:on_refresh('[9_2]layout_team_info', function(ui, local_player, instance)
    if BOB:is_in_team() then
        ui:set_visible(true)
        MAIN:refresh_prefab(MEMBER, #BOB.team_info.members)
    else
        ui:set_visible(false)
    end
end)

MAIN:on_refresh('[9_2]layout_team_info.layout_share.button_team_code.label', function(ui, local_player, instance)
    if BOB.team_info then
        ui:set_text('派对代码\n' .. BOB.team_info.team_id)
    end
end)

MAIN:on_refresh('[9_2]layout_team_info.button_close_team_up', function(ui, local_player, instance)
    if M.is_matching() then
        ui:set_button_enable(false)
    else
        ui:set_button_enable(true)
    end
    if BOB:is_captain() then
        ui:set_visible(true)
    else
        ui:set_visible(false)
    end
end)

MAIN:on_refresh('[9_2]layout_team_info.layout_ready_status.bg.time', function(ui, local_player, instance)
    local team_count, max = BOB:get_player_count()

    ui:set_text(string.format('%d/%d已就绪', team_count, max))
end)

-- MAIN:on_refresh('多人游戏', function (ui, local_player, instance)
--     if BOB:is_in_team() then
--         ui:set_visible(false)
--     else
--         ui:set_visible(true)
--     end
-- end)

MAIN:on_refresh('[9_3]layout_search_join_room', function(ui, local_player, instance)
    if not BOB:is_in_team() and M.is_join_room() then
        ui:set_visible(true)
    else
        ui:set_visible(false)
    end
end)

MAIN:on_refresh('[1]layout_match_function.button_create_room', function(ui, local_player, instance)
    ui:set_visible(true)
    if BOB:is_valid() and not M.is_matching() and not BOB:is_in_team() and not M.is_join_room() then
        ui:set_button_enable(true)
        ui:set_visible(true)
    else
        ui:set_button_enable(false)
        ui:set_visible(false)
    end
end)

MAIN:on_refresh('[1]layout_match_function.button_join_room', function(ui, local_player, instance)
    ui:set_visible(true)
    if BOB:is_valid() and not M.is_matching() and not BOB:is_in_team() and not M.is_join_room() then
        ui:set_button_enable(true)
        ui:set_visible(true)
    else
        ui:set_button_enable(false)
        ui:set_visible(false)
    end
end)

-- 多人游戏.输入框.文本
---@type UI?
local team_id_ui = nil
MAIN:on_init('[9_3]layout_search_join_room.input_field', function(ui, local_player, instance)
    team_id_ui = ui
end)

-- 以下是界面刷新事件 多人游戏.创建按钮
MAIN:on_event('[1]layout_match_function.button_create_room', '左键-点击', function(ui, local_player, instance)
    if M.is_matching() or M.is_launching() then
        return
    end
    ui:set_button_enable(false)
    BOB:create_team(function()
        ui:set_button_enable(true)
    end)
end)

-- 以下是界面刷新事件 多人游戏.加入房间
MAIN:on_event('[1]layout_match_function.button_join_room', '左键-点击', function(ui, local_player, instance)
    -- if M.is_matching() or M.is_launching() then
    --     return
    -- end
    M.join_room = true
    MAIN:refresh('*')
end)

-- 以下是界面刷新事件 多人游戏.加入房间
MAIN:on_event('[9_3]layout_search_join_room.button_close_join_wnd', '左键-点击', function(ui, local_player, instance)
    -- if M.is_matching() or M.is_launching() then
    --     return
    -- end
    M.join_room = false
    MAIN:refresh('*')
end)

-- 多人游戏.加入按钮
MAIN:on_event('[9_3]layout_search_join_room.button_confirm_to_join', '左键-点击', function(ui, local_player, instance)
    if M.is_matching() or M.is_launching() then
        return
    end
    ui:set_button_enable(false)
    if not team_id_ui then
        y3.ctimer.wait(0.5, function()
            ui:set_button_enable(true)
        end)
        return
    end
    local text = team_id_ui:get_input_field_content()
    local team_id = math.tointeger(text)
    if not team_id then
        y3.ctimer.wait(0.5, function()
            ui:set_button_enable(true)
        end)
        return
    end
    BOB:join_team(team_id, function()
        ui:set_button_enable(true)
    end)
end)

MAIN:on_event('[9_2]layout_team_info.button_close_team_up', '左键-点击', function(ui, local_player, instance)
    if M.is_matching() or M.is_launching() then
        return
    end
    BOB:dismiss_team()
end)

local share_cd

MAIN:on_event('[9_2]layout_team_info.layout_share.button_invitation_share', '左键-点击', function(ui, local_player, instance)
    if M.is_launching() or M.is_matching() then
        return
    end

    if BOB:is_in_team() then
        local team_id = BOB.team_info.team_id
        local chat_text = string.format('加入房间#04f800(%d)#E，我们一起方块乱斗！#fed257>>点击加入<<#E', team_id)

        if share_cd and share_cd:is_running() then
            local_player.MainTips:create_active_mouse_tips('你刚刚分享了房间邀请，请稍候再试')
        else
            BOB:send_world_chat(chat_text)
            share_cd = y3.timer.wait(15, function(timer)
                share_cd:remove()
            end)
        end
    end
end)

MAIN:on_event('[9_2]layout_team_info.button_quit_from_team', '左键-点击', function(ui, local_player, instance)
    if M.is_matching() then
        local_player.MainTips:create_active_mouse_tips('游戏匹配中无法离开')
        return
    elseif M.is_launching() then
        local_player.MainTips:create_active_mouse_tips('游戏启动中无法离开')
        return
    end
    BOB:leave_team()
end)

MAIN:on_event('[1]layout_match_function.button_match', '左键-点击', function(ui, local_player, instance)
    if M.is_launching() then
        return
    end
    if M.is_matching() then
        ui:set_button_enable(false)
        M.cancel_match(function()
            ui:set_button_enable(true)
        end)
    else
        local_player.PlayerSave:set_game_model('单人匹配')
        if BOB:get_player_count() >= 8 then
            ui:set_button_enable(false)
            local dungeon_info = {
                game_map_id = BOB.map_id,
                level_id = BOB.level_id,
                game_mode = PRIVATE_GAME_MODE,
            }
            local players = {}
            for index, PlayerInfo in pairs(BOB.team_info.members) do
                table.insert(players, {
                    aid = tostring(PlayerInfo.aid),
                    version = DUNGEON_PLAYER_VERSION,
                })
            end
            BOB:start_privat_dungeon_game(dungeon_info, players)
            y3.timer.wait(2, function(timer)
                ui:set_button_enable(true)
            end)
        else
            ui:set_button_enable(false)
            M.start_match(MATCH_GAME_MODE, nil, function()
                ui:set_button_enable(true)
            end)
        end
    end
end)

MAIN:on_event('[1]layout_match_function.button_ai_match', '左键-点击', function(ui, local_player, instance)
    if BOB then
        BOB:start_ai(true)
    end
end)

MAIN:on_refresh('[1]layout_match_function.button_match', function(ui, local_player, instance)
    if BOB.state ~= 'connected' then
        ui:set_button_enable(false)
    end
    if M.is_launching() then
        ui:set_button_enable(false)
        return
    end
    if BOB:is_in_team() and not BOB:is_captain() then
        ui:set_button_enable(false)
    else
        ui:set_button_enable(true)
    end
end)

MAIN:on_refresh('[1]layout_match_function.button_match.文本', function(ui, local_player, instance)
    if BOB.state == 'connecting' then
        ui:set_text('登录中')
    elseif BOB.state == 'disconnect' then
        ui:set_text('已掉线')
    elseif M.is_matching() then
        ui:set_text('取消匹配')
    elseif M.is_launching() then
        ui:set_text('启动中')
    else
        ui:set_text('开始匹配')
    end
end)

MAIN:on_refresh('[1]layout_match_function.matching.game_matching', function(ui, local_player, instance)
    if M.is_matching() then
        ui:set_visible(true)
    else
        ui:set_visible(false)
    end
end)

MEMBER:on_event('leader.assignor', '左键-点击', function(ui, local_player, instance)
    if M.is_matching() or M.is_launching() then
        return
    end
    local index = instance:storage_get('index')
    local member = BOB.team_info and BOB.team_info.members[index]
    if not member then
        return
    end
    BOB:change_captain(member.aid)
end)

MEMBER:on_event('kick_out', '左键-点击', function(ui, local_player, instance)
    if M.is_matching() or M.is_launching() then
        return
    end
    local index = instance:storage_get('index')
    local member = BOB.team_info and BOB.team_info.members[index]
    print(member)
    if not member then
        return
    end
    BOB:team_kick(member.aid)
end)

function M.init()
    BOB:event_on('准备就绪', function(trg)
        print("ui 准备就绪, 开始refresh")
        MAIN:refresh('*')
    end)

    BOB:event_on('加入队伍', function(trg)
        MAIN:refresh('[1]layout_match_function.button_match')
        MAIN:refresh('[9_2]layout_team_info')
        MAIN:refresh('[9_3]layout_search_join_room')
        MAIN:refresh('[1]layout_match_function')
    end)

    BOB:event_on('队伍变化', function(trg)
        MAIN:refresh('[1]layout_match_function.button_match')
        MAIN:refresh('[9_2]layout_team_info')
        MAIN:refresh('[9_3]layout_search_join_room')
    end)

    ---@type LocalTimer?
    local mathing_timer

    BOB:event_on('匹配状态变化', function(trg, state)
        MAIN:refresh('[1]layout_match_function.button_match')
        MAIN:refresh('[1]layout_match_function.matching.game_matching')
        MAIN:refresh('[9_2]layout_team_info')
        MAIN:refresh('[9_3]layout_search_join_room')
        MAIN:refresh('[1]layout_match_function')
        if mathing_timer then
            mathing_timer:remove()
        end
        if state == true then
            y3.player.with_local(function(local_player)
                local ui_2 = y3.ui.get_ui(local_player,
                    '[0]F1_main_hall.[1]layout_match_function.matching.game_matching')
                local ui = y3.ui.get_ui(local_player,
                    '[0]F1_main_hall.[1]layout_match_function.matching.game_matching.time')
                ui:set_text(string.format('%02d:%02d', 0, 0))
                mathing_timer = y3.ltimer.loop(1, function(timer, count)
                    ui_2:set_visible(true)
                    if ui then
                        ui:set_text(string.format('%02d:%02d', count // 60, count % 60))
                    end
                end)
            end)

            y3.player.with_local(function(local_player)
                if M.is_matching() then
                    local_player.PlayerSave:set_game_model('单人匹配')
                end
            end)
        end
    end)

    BOB:event_on('启动状态变化', function(trg, launching)
        MAIN:refresh('[1]layout_match_function.button_match')
        MAIN:refresh('[1]layout_match_function.matching.game_matching')
        MAIN:refresh('[9_2]layout_team_info')
        MAIN:refresh('[1]layout_match_function')
    end)

    -- --以下是系统消息
    -- BOB:event_on('收到消息', function(trg, data)
    --     y3.player.with_local(function(local_player)
    --         -- if data.chat and data.chat.sender.aid == BOB.aid then
    --         --     return
    --         -- end
    --         log.debug('收到消息', BOB:format_message(data))
    --         local ui = y3.ui.get_ui(local_player, '[0]F1_main_hall.[16]chat')
    --         local text = y3.ui_prefab.create(local_player, 'chat_text', ui):get_child()
    --         local chat_text = BOB:format_message(data)
    --         if text then
    --             text:set_text(chat_text)
    --         end
    --         ui:set_slider_value(1)

    --         print('格式化新i 信息 ', chat_text)
    --         -- local_player:event_dispatch('显示信息', chat_text)

    --         if local_player.uiGM then
    --             if data.chat then
    --                 local_player.uiGM:show_one_chat(data.chat.chat_type, chat_text)
    --             else
    --                 local_player.uiGM:show_one_chat(4, chat_text)
    --             end
    --         end
    --     end)
    -- end)

    BOB:event_on('加入队伍', function(trg)
        if BOB:is_captain() then
            BOB:display_message('你创建了队伍')
        else
            BOB:get_player_info(BOB.team_info.captain, function(result)
                if result then
                    BOB:display_message(string.format('你加入了[%s]的队伍', result.name))
                end
            end)
        end
    end)

    BOB:event_on('离开队伍', function(trg)
        MAIN:refresh('[1]layout_match_function.button_match')
        MAIN:refresh('[9_2]layout_team_info')
        MAIN:refresh('[9_3]layout_search_join_room')
        MAIN:refresh('[1]layout_match_function')
    end)

    BOB:event_on('离开队伍', function(trg, reason)
        if reason == '离开' then
            BOB:display_message('你退出了队伍')
        elseif reason == '踢出' then
            BOB:display_message('你被踢出了队伍')
        elseif reason == '解散' then
            BOB:display_message('队伍已被解散')
        end
    end)

    BOB:event_on('有人加入队伍', function(trg, data)
        BOB:display_message(string.format('[%s]加入了队伍', data.name))
    end)

    BOB:event_on('有人离开队伍', function(trg, data)
        BOB:display_message(string.format('[%s]离开了队伍', data.name))
    end)

    BOB:event_on('在线状态变化', function(trg, state)
        MAIN:refresh('[1]layout_match_function.button_match')
    end)

    MAIN:refresh('*')
end

---@param state boolean
function M.set_welfare_mode(state)
    M.welfare_mode = state
    log.debug('福利模式已设置为', state)
end

function M.is_welfare_valid()
    if not M.welfare_mode then
        return false
    end
    if BOB:is_in_team() and #BOB.team_info.members > 1 then
        return false
    end
    return true
end

---@param game_mode integer
---@param score? integer
---@param done? fun()
function M.start_match(game_mode, score, done)
    if M.is_welfare_valid() then
        log.info('【福利模式】请求匹配')
        y3.ctimer.wait(0.3, function()
            if done then
                done()
            end
            log.info('【福利模式】开始匹配')
            M.welfare_matching = y3.ctimer.wait(math.random_banned(6, 12), function()
                M.welfare_matching = nil
                log.info('【福利模式】正在启动')
                BOB:event_notify('匹配状态变化', false)
                M.welfare_launching = y3.ctimer.wait(math.random_banned(1, 3), function(timer, count, local_player)
                    M.welfare_launching = nil
                    log.info('【福利模式】已启动')
                    local_player.handle:request_create_private_dungeon(y3.game.get_level(), PRIVATE_GAME_MODE, 1)
                end)
                BOB:event_notify('启动状态变化', true)
            end)
            BOB:event_notify('匹配状态变化', true)
        end)
    else
        BOB:start_match(game_mode, score, done)
    end
end

---@param done? fun()
function M.cancel_match(done)
    if M.welfare_matching then
        log.info('【福利模式】请求取消匹配')
        y3.ctimer.wait(0.3, function()
            if done then
                done()
            end
            if not M.welfare_matching then
                log.info('【福利模式】取消匹配失败，已经进入启动流程')
                return
            end
            M.welfare_matching:remove()
            M.welfare_matching = nil
            BOB:event_notify('匹配状态变化', false)
        end)
    else
        BOB:cancel_match(done)
    end
end

function M.is_join_room()
    return M.join_room or false
end

function M.is_launching()
    return M.welfare_launching ~= nil
        or BOB:is_launching()
end

---是否正在匹配
---@return boolean
function M.is_matching()
    return M.welfare_matching ~= nil
        or BOB:is_matching()
end

return M
