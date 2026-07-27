---@class BobTestUI
local M = {}

local PLATFORM_LOBBY_GAME_MODE = 0
local LOBBY_GAME_MODE = 1001
local MATCH_GAME_MODE = 1002
local PRIVATE_GAME_MODE = 1003
local EXPECTED_PRIVATE_PLAYERS = 2
local MAX_MEMBER_ROWS = 4
local UI_LAYOUT_VERSION = 12

local COLOR_TEXT = { 235, 240, 246, 255 }
local COLOR_MUTED = { 162, 180, 193, 255 }
local COLOR_SUCCESS = { 111, 207, 151, 255 }
local COLOR_WARNING = { 237, 185, 93, 255 }

local runtime = rawget(_G, '__BOB_TEST_UI_RUNTIME') or {}
_G.__BOB_TEST_UI_RUNTIME = runtime

if runtime.layout_version ~= UI_LAYOUT_VERSION then
    if runtime.refresh_timer then
        pcall(function() runtime.refresh_timer:remove() end)
    end
    for _, ui in ipairs({
        runtime.full_panel,
        runtime.status_bg,
        runtime.status_text,
        runtime.battle_chat_panel,
        runtime.return_button,
        runtime.exit_button,
        runtime.exit_confirm_overlay,
    }) do
        if ui then
            pcall(function() ui:set_visible(false) end)
        end
    end
    runtime.built = false
    runtime.layout_version = UI_LAYOUT_VERSION
end

local BUTTON_IMAGES = {
    normal = 107525,
    hover = 107526,
    pressed = 107527,
    disabled = 107528,
}

local BUTTON_STATUSES = { '常态', '悬浮', '按下', '禁用' }

local function set_button_text(ui, text)
    for _, status in ipairs(BUTTON_STATUSES) do
        ui:set_btn_status_string(y3.const.UIButtonStatus[status], text)
    end
end

local function current_mode()
    local mode
    if y3.game.get_current_game_mode then
        mode = y3.game.get_current_game_mode()
    end
    if (not mode or tostring(mode) == '0') and y3.game.get_current_game_mode_new then
        mode = y3.game.get_current_game_mode_new()
    end
    local info = GameAPI.get_dungeon_info and GameAPI.get_dungeon_info()
    if (not mode or tostring(mode) == '0') and info then
        mode = info.game_mode
    end
    return math.tointeger(mode) or mode or 0
end

local function is_lobby_mode(mode)
    mode = math.tointeger(mode) or mode
    return mode == PLATFORM_LOBBY_GAME_MODE or mode == LOBBY_GAME_MODE
end

local function mode_label(mode)
    if is_lobby_mode(mode) then
        return '大厅'
    end
    if mode == MATCH_GAME_MODE then
        return '匹配对局'
    end
    if mode == PRIVATE_GAME_MODE then
        return '私人副本'
    end
    return '未知'
end

local function add_image(parent, x, y, width, height, image, color)
    local ui = parent:create_child('图片')
    ui:set_anchor(0, 0)
    ui:set_pos(x, y)
    ui:set_ui_size(width, height)
    ui:set_image(image)
    if color then
        ui:set_image_color(color[1], color[2], color[3], color[4])
    end
    return ui
end

local function add_text(parent, x, y, width, height, text, size, color, h, v)
    local ui = parent:create_child('文本')
    ui:set_anchor(0, 0)
    ui:set_pos(x, y)
    ui:set_ui_size(width, height)
    ui:set_text(text or '')
    ui:set_font_size(size or 18)
    ui:set_text_color((color or { 235, 240, 246, 255 })[1],
        (color or { 235, 240, 246, 255 })[2],
        (color or { 235, 240, 246, 255 })[3],
        (color or { 235, 240, 246, 255 })[4])
    ui:set_text_alignment(h or '左', v or '中')
    return ui
end

local function add_button(parent, x, y, width, height, text, callback)
    local ui = parent:create_child('按钮')
    ui:set_anchor(0, 0)
    ui:set_pos(x, y)
    ui:set_ui_size(width, height)
    ui:set_font_size(17)
    ui:set_text_color(242, 246, 250, 255)
    set_button_text(ui, text)
    ui:set_btn_status_image(y3.const.UIButtonStatus['常态'], BUTTON_IMAGES.normal)
    ui:set_btn_status_image(y3.const.UIButtonStatus['悬浮'], BUTTON_IMAGES.hover)
    ui:set_btn_status_image(y3.const.UIButtonStatus['按下'], BUTTON_IMAGES.pressed)
    ui:set_btn_status_image(y3.const.UIButtonStatus['禁用'], BUTTON_IMAGES.disabled)
    ui:add_local_event('左键-点击', callback)
    return ui
end

local function add_input(parent, x, y, width, height)
    add_image(parent, x, y, width, height, 109589, { 34, 42, 52, 245 })
    local ui = parent:create_child('输入框')
    ui:set_anchor(0, 0)
    ui:set_pos(x + 8, y + 2)
    ui:set_ui_size(width - 16, height - 4)
    ui:set_font_size(17)
    ui:set_text_color(238, 242, 247, 255)
    ui:set_text('')
    return ui
end

local function safe_action(name, action)
    local ok, action_ok, action_err = xpcall(action, function(message)
        return tostring(message)
    end)
    if not ok then
        runtime.notice = name .. '：' .. tostring(action_ok)
        log.error('[BobTestUI] ' .. runtime.notice)
        return false
    end
    if action_ok == false then
        runtime.notice = name .. '：' .. tostring(action_err or '操作失败')
        return false
    end
    runtime.notice = name .. '：请求已发送'
    return true
end

local function bob_ready()
    return BOB and IsValid(BOB) and BOB.client ~= nil and BOB:is_valid()
end

local function set_status_value(key, value, color)
    local ui = runtime.status_values and runtime.status_values[key]
    if not ui then
        return
    end
    local text_color = color or COLOR_TEXT
    ui:set_text(tostring(value))
    ui:set_text_color(text_color[1], text_color[2], text_color[3], text_color[4])
end

local function refresh_member_rows(bob, max_count, can_manage)
    local members = bob and bob.team_info and bob.team_info.members or {}
    runtime.member_count_text:set_text(string.format('%d / %d', #members, max_count))
    for index, row in ipairs(runtime.member_rows) do
        local member = members[index]
        row.container:set_visible(member ~= nil)
        if member then
            local aid = tostring(member.aid or 0)
            local is_self = bob and aid == tostring(bob.aid)
            local captain = bob.team_info and member.aid == bob.team_info.captain and ' [队长]' or ''
            row.aid = member.aid
            row.index_text:set_text(tostring(index))
            row.name_text:set_text(tostring(member.name or member.nickname or '未知玩家') .. captain)
            row.aid_text:set_text(aid)
            row.state_text:set_text(tostring(member.state or '未知'))
            row.current_text:set_visible(is_self)
            row.transfer_button:set_visible(not is_self)
            row.kick_button:set_visible(not is_self)
            row.transfer_button:set_button_enable(not is_self and can_manage)
            row.kick_button:set_button_enable(not is_self and can_manage)
        else
            row.aid = nil
        end
    end
end

local function chat_history_text()
    if not BOB or not IsValid(BOB) then
        return 'BOB 尚未创建'
    end
    local history = BOB.message_history or {}
    local lines = {}
    local first = math.max(1, #history - 5)
    for index = first, #history do
        local item = history[index]
        local ok, text = pcall(BOB.format_message, BOB, item)
        lines[#lines + 1] = ok and text or tostring(item.message or '')
    end
    return #lines > 0 and table.concat(lines, '\n') or '暂无聊天消息'
end

local function send_chat_from_input(channel, input)
    local message = input:get_input_field_content()
    if message == '' or not bob_ready() then
        return false, 'BOB 未登录或消息为空'
    end
    local sent, reason
    if channel == '队伍' then
        sent, reason = BOB:send_chat(message)
    else
        sent, reason = BOB:send_world_chat(message)
    end
    if sent then
        input:set_text('')
    end
    return sent, reason
end

local function refresh()
    if not runtime.built then
        return
    end
    local mode = current_mode()
    local bob = BOB and IsValid(BOB) and BOB or nil
    local team_id = bob and bob.team_info and bob.team_info.team_id or 0
    local team_count, max_count = 0, 0
    if bob then
        team_count, max_count = bob:get_player_count()
    end

    local battle_mode = MatchTestIsBattleContext()
    local team_busy = bob and (bob:is_matching() or bob:is_launching()) or false
    local in_team = bob and bob:is_in_team() or false
    local is_captain = in_team and bob:is_captain() or false
    local ready = bob_ready()
    local matching = bob and bob:is_matching() or false
    local launching = bob and bob:is_launching() or false
    local dungeon_token = type(MatchTestGetDungeonToken) == 'function'
        and MatchTestGetDungeonToken() or ''
    runtime.full_panel:set_visible(not battle_mode)
    runtime.status_bg:set_visible(battle_mode)
    runtime.status_text:set_visible(battle_mode)
    runtime.return_button:set_visible(battle_mode)
    runtime.battle_chat_panel:set_visible(battle_mode)
    runtime.status_text:set_text(string.format(
        '模式：%s (%s)    玩家：%s / ID=%s\nBOB：%s    登录：%s    AID=%s\n队伍：%s    人数：%s/%s    匹配：%s    启动：%s\n副本口令：%s',
        mode_label(mode),
        tostring(mode),
        runtime.player:get_name(),
        tostring(runtime.player:get_id()),
        bob and tostring(bob.state) or '未创建',
        ready and '已登录' or '未登录',
        bob and tostring(bob.aid) or '-',
        in_team and tostring(team_id) or '未加入',
        tostring(team_count),
        tostring(max_count),
        matching and '匹配中' or '未匹配',
        launching and '启动中' or '未启动',
        dungeon_token ~= '' and dungeon_token or '-'))

    runtime.leave_button:set_button_enable(in_team and not team_busy)
    runtime.private_button:set_button_enable(
        ready and is_captain and not team_busy and team_count >= EXPECTED_PRIVATE_PLAYERS)
    runtime.dismiss_button:set_button_enable(is_captain and not team_busy)
    runtime.battle_token_text:set_text(dungeon_token ~= '' and dungeon_token or '-')
    runtime.battle_copy_button:set_button_enable(dungeon_token ~= '')
    runtime.battle_team_button:set_button_enable(ready and in_team)
    runtime.battle_world_button:set_button_enable(ready)
    runtime.battle_chat_text:set_text(chat_history_text())
    runtime.battle_notice_text:set_text(runtime.battle_notice or '等待消息')

    local match_text = '开始匹配'
    local match_enabled = false
    if launching then
        match_text = '启动中'
    elseif matching then
        match_text = '取消匹配'
        match_enabled = ready and (not in_team or is_captain)
    elseif bob and ready then
        match_enabled = bob:can_match()
    end
    set_button_text(runtime.match_button, match_text)
    runtime.match_button:set_button_enable(match_enabled)

    if battle_mode then
        return
    end

    set_status_value('mode', string.format('%s (%s)', mode_label(mode), tostring(mode)))
    set_status_value('player', string.format('%s / ID=%s', runtime.player:get_name(), runtime.player:get_id()))
    set_status_value('bob', bob and tostring(bob.state) or '未创建', bob and COLOR_SUCCESS or COLOR_WARNING)
    set_status_value('login', ready and '已登录' or '未登录', ready and COLOR_SUCCESS or COLOR_WARNING)
    set_status_value('aid', bob and tostring(bob.aid) or '-')
    set_status_value('team', in_team and tostring(team_id) or '未加入')
    set_status_value('count', string.format('%s/%s', team_count, max_count))
    set_status_value('match', matching and '匹配中' or '未匹配', matching and COLOR_WARNING or COLOR_TEXT)
    set_status_value('launch', launching and '启动中' or '未启动', launching and COLOR_WARNING or COLOR_TEXT)
    refresh_member_rows(bob, max_count, is_captain and not team_busy)
    runtime.chat_text:set_text(chat_history_text())
    runtime.notice_text:set_text(runtime.notice or '等待操作')
end

local function build(player)
    if runtime.built then
        return
    end
    local root = y3.ui.get_ui(player, 'BobTestUI')
    runtime.player = player

    runtime.status_bg = add_image(root, 20, 914, 700, 150, 109589, { 20, 28, 36, 245 })
    runtime.status_text = add_text(root, 40, 928, 500, 112, '', 18, { 220, 233, 242, 255 }, '左', '上')
    runtime.return_button = add_button(root, 560, 950, 140, 48, '返回初始关卡', function()
        safe_action('返回初始关卡', MatchTestReturnLobby)
    end)

    runtime.battle_chat_panel = root:create_child('空节点')
    runtime.battle_chat_panel:set_anchor(0, 0)
    runtime.battle_chat_panel:set_pos(20, 510)
    runtime.battle_chat_panel:set_ui_size(700, 390)
    runtime.battle_chat_panel:set_z_order(9000)
    add_image(runtime.battle_chat_panel, 0, 0, 700, 390, 109589, { 20, 28, 36, 245 })
    add_text(runtime.battle_chat_panel, 20, 350, 130, 26, '副本口令', 16, COLOR_MUTED)
    runtime.battle_token_text = add_text(
        runtime.battle_chat_panel, 150, 346, 370, 34, '-', 18, COLOR_WARNING, '左', '中')
    runtime.battle_copy_button = add_button(
        runtime.battle_chat_panel, 540, 342, 140, 42, '复制口令', function()
            if MatchTestGetDungeonToken() == '' then
                runtime.battle_notice = '当前没有可复制的副本口令'
                refresh()
                return
            end
            GameAPI.copy_ui_text_to_clipboard(
                runtime.player.handle,
                runtime.battle_token_text.handle)
            runtime.battle_notice = '副本口令已复制到剪贴板'
            refresh()
        end)
    add_text(runtime.battle_chat_panel, 20, 310, 180, 26, '副本聊天', 18, { 255, 205, 96, 255 })
    runtime.battle_chat_text = add_text(
        runtime.battle_chat_panel, 20, 140, 660, 164, '', 15, COLOR_TEXT, '左', '上')
    runtime.battle_chat_input = add_input(runtime.battle_chat_panel, 20, 82, 410, 44)
    runtime.battle_team_button = add_button(
        runtime.battle_chat_panel, 442, 82, 110, 44, '队伍聊天', function()
            local sent, reason = send_chat_from_input('队伍', runtime.battle_chat_input)
            runtime.battle_notice = sent and '队伍消息已发送' or ('队伍聊天：' .. tostring(reason))
            refresh()
        end)
    runtime.battle_world_button = add_button(
        runtime.battle_chat_panel, 564, 82, 116, 44, '世界聊天', function()
            local sent, reason = send_chat_from_input('世界', runtime.battle_chat_input)
            runtime.battle_notice = sent and '世界消息已发送' or ('世界聊天：' .. tostring(reason))
            refresh()
        end)
    runtime.battle_notice_text = add_text(
        runtime.battle_chat_panel, 20, 28, 660, 34, '', 14, COLOR_SUCCESS, '左', '中')

    runtime.exit_button = add_button(root, 0, 0, 150, 48, '退出游戏', function()
        runtime.exit_confirm_overlay:set_visible(true)
    end)
    runtime.exit_button:set_relative_parent_pos('顶部', 24)
    runtime.exit_button:set_relative_parent_pos('右侧', 240)
    runtime.exit_button:set_z_order(10000)

    runtime.exit_confirm_overlay = add_image(root, 0, 0, 1920, 1080, 109589, { 0, 0, 0, 190 })
    runtime.exit_confirm_overlay:set_intercepts_operations(true)
    runtime.exit_confirm_overlay:set_z_order(20000)
    local exit_confirm_panel = add_image(
        runtime.exit_confirm_overlay, 720, 400, 480, 280, 109589, { 20, 28, 36, 255 })
    add_text(exit_confirm_panel, 36, 204, 408, 40, '确认退出游戏？', 26, COLOR_WARNING, '中', '中')
    add_text(exit_confirm_panel, 36, 126, 408, 56,
        '退出后将清理当前匹配和组队状态。', 17, COLOR_TEXT, '中', '中')
    runtime.exit_cancel_button = add_button(exit_confirm_panel, 42, 36, 180, 52, '取消', function()
        runtime.exit_confirm_overlay:set_visible(false)
    end)
    runtime.exit_confirm_button = add_button(exit_confirm_panel, 258, 36, 180, 52, '确认退出', function()
        runtime.exit_confirm_overlay:set_visible(false)
        safe_action('退出游戏', MatchTestExitGame)
    end)
    runtime.exit_confirm_overlay:set_visible(false)

    local panel = root:create_child('空节点')
    panel:set_anchor(0, 0)
    panel:set_pos(480, 170)
    panel:set_ui_size(1440, 900)
    panel:set_z_order(-1000)
    runtime.full_panel = panel

    add_image(panel, 20, 40, 1400, 850, 109589, { 20, 28, 36, 245 })
    add_text(panel, 40, 842, 900, 38, 'BOB 匹配系统测试面板', 25, { 255, 205, 96, 255 }, '左', '中')
    add_text(panel, 1130, 848, 270, 28, '大厅上下文 · 完整测试面板', 14, COLOR_MUTED, '右', '中')

    add_image(panel, 40, 704, 1360, 120, 109589, { 15, 23, 30, 245 })
    add_text(panel, 54, 790, 240, 26, '运行状态', 18, { 255, 205, 96, 255 })
    add_text(panel, 1120, 790, 266, 26, '与当前 Y3 状态字段一一对应', 13, COLOR_MUTED, '右', '中')
    runtime.status_values = {}
    local status_specs = {
        { 'mode', '模式', 40, 160 },
        { 'player', '玩家', 204, 210 },
        { 'bob', 'BOB', 418, 125 },
        { 'login', '登录', 547, 125 },
        { 'aid', 'AID', 676, 150 },
        { 'team', '队伍', 830, 130 },
        { 'count', '人数', 964, 100 },
        { 'match', '匹配', 1068, 160 },
        { 'launch', '启动', 1232, 168 },
    }
    for _, spec in ipairs(status_specs) do
        add_image(panel, spec[3], 714, spec[4], 64, 109589, { 21, 32, 41, 245 })
        add_text(panel, spec[3] + 12, 754, spec[4] - 24, 16, spec[2], 12, COLOR_MUTED, '左', '中')
        runtime.status_values[spec[1]] = add_text(
            panel, spec[3] + 12, 722, spec[4] - 24, 28, '', 15, COLOR_TEXT, '左', '中')
    end

    add_image(panel, 40, 504, 780, 188, 109589, { 15, 23, 30, 245 })
    add_text(panel, 54, 654, 280, 28, '队伍与副本', 18, { 255, 205, 96, 255 })
    add_text(panel, 540, 654, 266, 28, '组队管理和启动测试', 13, COLOR_MUTED, '右', '中')
    add_text(panel, 54, 618, 120, 24, '队伍编号', 15, COLOR_MUTED)
    runtime.team_input = add_input(panel, 54, 570, 300, 42)
    add_button(panel, 366, 570, 140, 42, '加入队伍', function()
        local team_id = math.tointeger(runtime.team_input:get_input_field_content())
        if not team_id then
            runtime.notice = '加入队伍：请输入有效数字编号'
            refresh()
            return
        end
        safe_action('加入队伍', function()
            MatchTestSetJoinTeamId(team_id)
            MatchTestJoinTeam(team_id)
        end)
    end)
    add_button(panel, 514, 570, 140, 42, '创建队伍', function()
        safe_action('创建队伍', MatchTestCreateTeam)
    end)
    runtime.leave_button = add_button(panel, 662, 570, 144, 42, '离开队伍', function()
        safe_action('离开队伍', MatchTestLeaveTeam)
    end)

    add_text(panel, 54, 542, 160, 22, '副本测试', 13, COLOR_MUTED)
    add_text(panel, 236, 542, 160, 22, '副本口令', 13, COLOR_MUTED)
    runtime.match_button = add_button(panel, 54, 506, 174, 42, '开始匹配', function()
        if BOB and IsValid(BOB) and BOB:is_matching() then
            safe_action('取消匹配', MatchTestCancel)
        else
            safe_action('开始匹配', function() return MatchTestStart(1000) end)
        end
        refresh()
    end)
    runtime.dungeon_input = add_input(panel, 236, 506, 164, 42)
    runtime.dungeon_join_button = add_button(panel, 408, 506, 120, 42, '加入副本', function()
        local token = runtime.dungeon_input:get_input_field_content()
        local sent = safe_action('加入副本', function()
            return MatchTestJoinPrivateDungeon(token)
        end)
        if sent then
            runtime.notice = '加入请求已发送；需在开局120秒内且房间未满'
        end
        refresh()
    end)
    add_button(panel, 536, 506, 130, 42, '私人副本', function()
        safe_action('创建私人副本', MatchTestLocalPrivate)
    end)
    runtime.private_button = add_button(panel, 674, 506, 132, 42, 'RPC 多人', function()
        safe_action('RPC 多人副本', MatchTestStartPrivate)
    end)

    add_image(panel, 40, 96, 780, 396, 109589, { 15, 23, 30, 245 })
    add_text(panel, 54, 452, 220, 28, '队员列表', 18, { 255, 205, 96, 255 })
    runtime.member_count_text = add_text(panel, 560, 452, 92, 28, '', 14, COLOR_MUTED, '右', '中')
    runtime.dismiss_button = add_button(panel, 666, 444, 140, 42, '解散队伍', function()
        safe_action('解散队伍', MatchTestDismissTeam)
    end)
    add_text(panel, 54, 416, 40, 22, '序号', 12, COLOR_MUTED)
    add_text(panel, 112, 416, 190, 22, '玩家', 12, COLOR_MUTED)
    add_text(panel, 322, 416, 120, 22, 'AID', 12, COLOR_MUTED)
    add_text(panel, 462, 416, 90, 22, '状态', 12, COLOR_MUTED)
    add_text(panel, 680, 416, 126, 22, '操作', 12, COLOR_MUTED, '右', '中')

    runtime.member_rows = {}
    for index = 1, MAX_MEMBER_ROWS do
        local row = {}
        row.container = panel:create_child('空节点')
        row.container:set_anchor(0, 0)
        row.container:set_pos(40, 350 - (index - 1) * 64)
        row.container:set_ui_size(780, 56)
        add_image(row.container, 0, 0, 780, 56, 109589, { 21, 32, 41, 245 })
        row.index_text = add_text(row.container, 14, 0, 40, 56, '', 14, COLOR_TEXT)
        row.name_text = add_text(row.container, 72, 0, 200, 56, '', 14, COLOR_TEXT)
        row.aid_text = add_text(row.container, 282, 0, 130, 56, '', 13, COLOR_MUTED)
        row.state_text = add_text(row.container, 422, 0, 80, 56, '', 13, COLOR_SUCCESS)
        row.current_text = add_text(row.container, 520, 0, 246, 56, '当前玩家', 12, COLOR_MUTED, '右', '中')
        row.transfer_button = add_button(row.container, 508, 7, 124, 42, '转移队长', function()
            if row.aid then
                safe_action('转移队长', function() return MatchTestChangeCaptain(row.aid) end)
                refresh()
            end
        end)
        row.kick_button = add_button(row.container, 640, 7, 126, 42, '移出队员', function()
            if row.aid then
                safe_action('移出队员', function() return MatchTestKickMember(row.aid) end)
                refresh()
            end
        end)
        runtime.member_rows[index] = row
    end

    add_image(panel, 836, 620, 564, 72, 109589, { 15, 23, 30, 245 })
    add_text(panel, 850, 658, 180, 24, '操作结果', 18, { 255, 205, 96, 255 })
    runtime.notice_text = add_text(panel, 850, 626, 536, 28, '', 15, COLOR_SUCCESS, '左', '中')

    add_image(panel, 836, 292, 564, 316, 109589, { 15, 23, 30, 245 })
    add_text(panel, 850, 570, 180, 26, '最近聊天', 18, { 255, 205, 96, 255 })
    add_text(panel, 1230, 570, 156, 26, '最多保留 5 条', 12, COLOR_MUTED, '右', '中')
    runtime.chat_text = add_text(panel, 850, 390, 536, 170, '', 15, COLOR_TEXT, '左', '上')
    add_text(panel, 850, 350, 120, 26, '发送消息', 15, COLOR_MUTED)
    runtime.chat_input = add_input(panel, 850, 306, 300, 42)
    add_button(panel, 1158, 306, 108, 42, '队伍聊天', function()
        safe_action('队伍聊天', function()
            return send_chat_from_input('队伍', runtime.chat_input)
        end)
        refresh()
    end)
    add_button(panel, 1274, 306, 112, 42, '世界聊天', function()
        safe_action('世界聊天', function()
            return send_chat_from_input('世界', runtime.chat_input)
        end)
        refresh()
    end)

    add_image(panel, 836, 96, 564, 184, 109589, { 15, 23, 30, 245 })
    add_text(panel, 850, 244, 180, 26, '快捷键', 18, { 255, 205, 96, 255 })
    add_text(panel, 850, 116, 536, 116,
        'F2 重登    F3 创建    F4 匹配    F5 取消    F6 私人\n' ..
        'F7 多人    F8 离队    F9 状态    F10 加入',
        14, { 151, 166, 178, 255 }, '左', '上')

    runtime.built = true
    runtime.notice = '测试 UI 已就绪'
    refresh()
    runtime.refresh_timer = y3.ltimer.loop(0.5, refresh)
    log.info('[BobTestUI] runtime panel created')
end

local function schedule_build(player)
    y3.ltimer.wait_frame(5, function()
        local ok, err = xpcall(function() build(player) end, function(message)
            return tostring(message)
        end)
        if not ok then
            log.error('[BobTestUI] create failed: ' .. tostring(err))
        end
    end)
end

y3.game:event('玩家-加入游戏', function(_, data)
    y3.player.with_local(function(local_player)
        if data.player == local_player then
            schedule_build(local_player)
        end
    end)
end)

return M
