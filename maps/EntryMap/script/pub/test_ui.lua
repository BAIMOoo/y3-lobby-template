---@class BobTestUI
local M = {}

local runtime = rawget(_G, '__BOB_TEST_UI_RUNTIME') or {}
_G.__BOB_TEST_UI_RUNTIME = runtime

local BUTTON_IMAGES = {
    normal = 107525,
    hover = 107526,
    pressed = 107527,
    disabled = 107528,
}

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
    ui:set_btn_status_string(y3.const.UIButtonStatus['常态'], text)
    ui:set_btn_status_string(y3.const.UIButtonStatus['悬浮'], text)
    ui:set_btn_status_string(y3.const.UIButtonStatus['按下'], text)
    ui:set_btn_status_string(y3.const.UIButtonStatus['禁用'], text)
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
    local ok, err = xpcall(action, function(message)
        return tostring(message)
    end)
    if ok then
        runtime.notice = name .. '：请求已发送'
    else
        runtime.notice = name .. '：' .. tostring(err)
        log.error('[BobTestUI] ' .. runtime.notice)
    end
end

local function bob_ready()
    return BOB and IsValid(BOB) and BOB.client ~= nil and BOB:is_valid()
end

local function team_members_text()
    if not BOB or not IsValid(BOB) or not BOB.team_info then
        return '当前没有队伍'
    end
    local lines = {}
    for index, member in ipairs(BOB.team_info.members or {}) do
        local captain = member.aid == BOB.team_info.captain and ' [队长]' or ''
        lines[#lines + 1] = string.format('%d. %s%s  AID=%s  状态=%s',
            index,
            tostring(member.name or member.nickname or '未知玩家'),
            captain,
            tostring(member.aid or 0),
            tostring(member.state or '未知'))
    end
    return #lines > 0 and table.concat(lines, '\n') or '队伍成员列表为空'
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

    runtime.full_panel:set_visible(mode ~= 1002)
    runtime.status_bg:set_ui_size(mode == 1002 and 700 or 760, mode == 1002 and 150 or 118)
    runtime.status_text:set_ui_size(mode == 1002 and 660 or 720, mode == 1002 and 112 or 80)
    runtime.status_text:set_text(string.format(
        '模式：%s (%s)    玩家：%s / ID=%s\nBOB：%s    登录：%s    AID=%s\n队伍：%s    人数：%s/%s    匹配：%s    启动：%s',
        mode == 1001 and '大厅' or mode == 1002 and '对局' or '未知',
        tostring(mode),
        runtime.player:get_name(),
        tostring(runtime.player:get_id()),
        bob and tostring(bob.state) or '未创建',
        tostring(bob_ready()),
        bob and tostring(bob.aid) or '-',
        tostring(team_id),
        tostring(team_count),
        tostring(max_count),
        tostring(bob and bob:is_matching() or false),
        tostring(bob and bob:is_launching() or false)))

    if mode == 1002 then
        return
    end
    runtime.members_text:set_text(team_members_text())
    runtime.chat_text:set_text(chat_history_text())
    runtime.notice_text:set_text(runtime.notice or '等待操作')
end

local function build(player)
    if runtime.built then
        return
    end
    local root = y3.ui.get_ui(player, 'BobTestUI')
    runtime.player = player

    runtime.status_bg = add_image(root, 20, 914, 760, 118, 109589, { 20, 28, 36, 245 })
    runtime.status_text = add_text(root, 40, 928, 720, 80, '', 18, { 220, 233, 242, 255 }, '左', '上')

    local panel = root:create_child('空节点')
    panel:set_anchor(0, 0)
    panel:set_pos(0, 0)
    panel:set_ui_size(800, 900)
    runtime.full_panel = panel

    add_image(panel, 20, 94, 760, 802, 109589, { 20, 28, 36, 245 })
    add_text(panel, 40, 846, 720, 38, 'BOB 匹配系统测试面板', 25, { 255, 205, 96, 255 }, '左', '中')

    add_text(panel, 40, 792, 120, 30, '队伍编号', 16, { 162, 180, 193, 255 })
    runtime.team_input = add_input(panel, 40, 748, 260, 42)
    add_button(panel, 312, 748, 130, 42, '加入队伍', function()
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
    add_button(panel, 454, 748, 145, 42, '创建队伍', function()
        safe_action('创建队伍', MatchTestCreateTeam)
    end)
    add_button(panel, 611, 748, 145, 42, '离开队伍', function()
        safe_action('离开队伍', MatchTestLeaveTeam)
    end)

    add_button(panel, 40, 692, 160, 42, '开始匹配', function()
        safe_action('开始匹配', function() MatchTestStart(1000) end)
    end)
    add_button(panel, 212, 692, 160, 42, '取消匹配', function()
        safe_action('取消匹配', MatchTestCancel)
    end)
    add_button(panel, 384, 692, 180, 42, '本地单人副本', function()
        safe_action('本地单人副本', MatchTestLocalPrivate)
    end)
    add_button(panel, 576, 692, 180, 42, 'RPC 多人副本', function()
        safe_action('RPC 多人副本', MatchTestStartPrivate)
    end)

    add_text(panel, 40, 645, 720, 28, '队员列表', 18, { 255, 205, 96, 255 })
    runtime.members_text = add_text(panel, 40, 532, 716, 108, '', 16, nil, '左', '上')

    add_text(panel, 40, 492, 720, 28, '聊天记录', 18, { 255, 205, 96, 255 })
    runtime.chat_text = add_text(panel, 40, 332, 716, 156, '', 15, nil, '左', '上')

    add_text(panel, 40, 294, 120, 26, '发送消息', 16, { 162, 180, 193, 255 })
    runtime.chat_input = add_input(panel, 40, 246, 420, 42)
    add_button(panel, 472, 246, 135, 42, '队伍聊天', function()
        local message = runtime.chat_input:get_input_field_content()
        if message == '' or not bob_ready() then
            runtime.notice = '队伍聊天：BOB 未登录或消息为空'
            refresh()
            return
        end
        safe_action('队伍聊天', function()
            BOB:send_chat(message)
            runtime.chat_input:set_text('')
        end)
    end)
    add_button(panel, 619, 246, 137, 42, '世界聊天', function()
        local message = runtime.chat_input:get_input_field_content()
        if message == '' or not bob_ready() then
            runtime.notice = '世界聊天：BOB 未登录或消息为空'
            refresh()
            return
        end
        safe_action('世界聊天', function()
            BOB:send_world_chat(message)
            runtime.chat_input:set_text('')
        end)
    end)

    runtime.notice_text = add_text(panel, 40, 194, 716, 36, '', 16, { 111, 207, 151, 255 }, '左', '中')
    add_text(panel, 40, 116, 716, 62,
        '快捷键仍可用：F2 重登  F3 创建  F4 匹配  F5 取消  F6 单人  F7 多人  F8 离队  F9 状态  F10 加入',
        14, { 151, 166, 178, 255 }, '左', '中')

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
