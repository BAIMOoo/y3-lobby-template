---@class BobTestUI
local M = {}

local PLATFORM_LOBBY_GAME_MODE = 0
local LOBBY_GAME_MODE = 1001
local MATCH_GAME_MODE = 1002
local PRIVATE_GAME_MODE = 1003
local MATCH_LEVEL_ID = '50377054694119407947881484918402159964'
local SAME_ROOM_LEVEL_ID = '25e6448f-7e73-11f1-88ae-03dc5a85955c'
local LOBBY_LEVEL_ID = '81ad7554-7e6b-11f1-8f5c-c78cd393ba6e'
local EXPECTED_PRIVATE_PLAYERS = 2
local MAX_MEMBER_ROWS = 4
local MAX_CHAT_LINES = 5
local UI_LAYOUT_VERSION = 18

local COLOR_TEXT = { 244, 234, 213, 255 }
local COLOR_MUTED = { 197, 185, 159, 255 }
local COLOR_SUCCESS = { 117, 170, 156, 255 }
local COLOR_WARNING = { 214, 168, 78, 255 }
local COLOR_DANGER = { 217, 119, 99, 255 }
local COLOR_BORDER = { 224, 196, 132, 82 }
local COLOR_PANEL = { 30, 25, 18, 236 }
local COLOR_PANEL_SOFT = { 35, 29, 21, 226 }
local COLOR_PANEL_DEEP = { 21, 18, 14, 244 }
local COLOR_BACKDROP = { 255, 255, 255, 255 }
local BACKDROP_IMAGE = 134217745

local runtime = rawget(_G, '__LOBBY_TEST_UI_RUNTIME') or {}
_G.__LOBBY_TEST_UI_RUNTIME = runtime

for _, resource_key in ipairs({ 'refresh_timer', 'complete_listener', 'event_listener' }) do
    local resource = runtime[resource_key]
    if resource then
        pcall(function() resource:remove() end)
        runtime[resource_key] = nil
    end
end

if runtime.layout_version ~= UI_LAYOUT_VERSION then
    for _, ui in ipairs({
        runtime.backdrop,
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

local PANEL_IMAGES = {
    panel = 134217729,
    soft = 134217730,
    deep = 134217731,
    input = 134217732,
}

local BUTTON_IMAGES = {
    normal = {
        normal = 134217733,
        hover = 134217734,
        pressed = 134217735,
        disabled = 134217736,
    },
    primary = {
        normal = 134217737,
        hover = 134217738,
        pressed = 134217739,
        disabled = 134217740,
    },
    danger = {
        normal = 134217741,
        hover = 134217742,
        pressed = 134217743,
        disabled = 134217744,
    },
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
        return '目标关卡'
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

local function enable_nine_slice(ui, inset)
    ui:set_ui_9_enable(true)
    ui:set_ui_9(inset, inset, inset, inset)
    return ui
end

local function panel_image(color)
    if color == COLOR_PANEL_SOFT then
        return PANEL_IMAGES.soft
    end
    if color == COLOR_PANEL_DEEP then
        return PANEL_IMAGES.deep
    end
    return PANEL_IMAGES.panel
end

local function add_panel(parent, x, y, width, height, color, accent)
    local surface = enable_nine_slice(
        add_image(parent, x, y, width, height, panel_image(color or COLOR_PANEL)), 8)
    if accent then
        add_image(parent, x + 3, y + height - 3, width - 6, 2, 109589, COLOR_WARNING)
    end
    return surface
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

local function add_button(parent, x, y, width, height, text, callback, variant)
    local ui = parent:create_child('按钮')
    local images = BUTTON_IMAGES[variant or 'normal'] or BUTTON_IMAGES.normal
    ui:set_anchor(0, 0)
    ui:set_pos(x, y)
    ui:set_ui_size(width, height)
    ui:set_font_size(14)
    ui:set_text_color(247, 239, 221, 255)
    set_button_text(ui, text)
    ui:set_btn_status_image(y3.const.UIButtonStatus['常态'], images.normal)
    ui:set_btn_status_image(y3.const.UIButtonStatus['悬浮'], images.hover)
    ui:set_btn_status_image(y3.const.UIButtonStatus['按下'], images.pressed)
    ui:set_btn_status_image(y3.const.UIButtonStatus['禁用'], images.disabled)
    for _, status in ipairs(BUTTON_STATUSES) do
        GameAPI.set_ui_btn_status_cap_insets(
            runtime.player.handle, ui.handle, y3.const.UIButtonStatus[status], 8, 8, 8, 8)
    end
    ui:add_local_event('左键-点击', callback)
    return ui
end

local function add_input(parent, x, y, width, height)
    enable_nine_slice(add_image(parent, x, y, width, height, PANEL_IMAGES.input), 8)
    local ui = parent:create_child('输入框')
    ui:set_anchor(0, 0)
    ui:set_pos(x + 8, y + 2)
    ui:set_ui_size(width - 16, height - 4)
    ui:set_font_size(17)
    ui:set_text_color(238, 230, 212, 255)
    ui:set_text('')
    return ui
end

local function log_field(value)
    if value == nil or value == '' then
        return '-'
    end
    return tostring(value)
end

local function write_log(level, message)
    local writer = log and (log[level] or log.info)
    if writer then
        pcall(writer, message)
    end
end

local SENSITIVE_REASON_ACTIONS = {
    ['加入口令'] = true,
    ['队伍聊天'] = true,
    ['世界聊天'] = true,
    ['发送队伍聊天'] = true,
    ['发送世界聊天'] = true,
    ['建立连接'] = true,
    connection_changed = true,
}

local SAFE_REASON_CODES = {
    empty_message = true,
    invalid_input = true,
    ok = true,
}

local function log_reason(action, data)
    local reason = data.reason
    if reason == nil or reason == '' then
        return '-'
    end
    local code = tostring(data.code or '')
    if SENSITIVE_REASON_ACTIONS[tostring(action or data.action or '')]
        and not SAFE_REASON_CODES[code]
    then
        return '敏感详情已省略'
    end
    return tostring(reason)
end

local function log_operation(level, phase, action, data)
    data = type(data) == 'table' and data or {}
    write_log(level, string.format(
        '[LobbyTestUI] %s | action=%s | accepted=%s | success=%s | sync=%s'
            .. ' | request_id=%s | code=%s | reason=%s | sequence=%s',
        tostring(phase),
        log_field(action or data.action),
        log_field(data.accepted),
        log_field(data.success),
        log_field(data.sync),
        log_field(data.request_id),
        log_field(data.code),
        log_reason(action, data),
        log_field(data.sequence)))
end

local function safe_action(name, action)
    log_operation('info', '操作发起', name)
    local ok, action_result, action_err = xpcall(action, function(message)
        return tostring(message)
    end)
    if not ok then
        runtime.notice = name .. '：' .. tostring(action_result)
        log_operation('error', '操作异常', name, {
            accepted = false,
            sync = true,
            code = 'lua_exception',
            reason = action_result,
        })
        return false
    end

    if type(action_result) == 'table' and action_result.accepted ~= nil then
        if not action_result.accepted then
            runtime.notice = name .. '：' .. tostring(action_result.reason or action_result.code or '操作失败')
            log_operation('warn', '操作拒绝', name, action_result)
            return false
        end
        runtime.notice = name .. '：' .. tostring(action_result.sync
            and (action_result.reason or '操作完成')
            or '请求已受理')
        log_operation('info', action_result.sync and '同步完成' or '请求已受理', name, action_result)
        return true
    end

    if action_result == false then
        runtime.notice = name .. '：' .. tostring(action_err or '操作失败')
        log_operation('warn', '操作拒绝', name, {
            accepted = false,
            sync = true,
            code = 'request_failed',
            reason = action_err or '操作失败',
        })
        return false
    end
    runtime.notice = name .. '：请求已发送'
    log_operation('info', '请求已发送', name, {
        accepted = true,
        sync = false,
        code = 'ok',
        reason = '请求已发送',
    })
    return true
end

local function lobby_state()
    local state_result = y3.lobby.get_state()
    if state_result and state_result.accepted and type(state_result.result_data) == 'table' then
        return state_result.result_data
    end
    return {
        status = state_result and state_result.code or 'unavailable',
        connected = false,
        members = {},
        member_count = 0,
        member_limit = 0,
        token = '',
    }
end

local function current_token()
    local token_result = y3.lobby.get_token()
    if token_result and token_result.accepted and type(token_result.result_data) == 'table' then
        return tostring(token_result.result_data.token or '')
    end
    return ''
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

local function refresh_member_rows(snapshot, max_count, can_manage)
    local members = snapshot.members or {}
    runtime.member_count_text:set_text(string.format('%d / %d', #members, max_count))
    for index, row in ipairs(runtime.member_rows) do
        local member = members[index]
        row.container:set_visible(member ~= nil)
        if member then
            local aid = tostring(member.aid or 0)
            local is_self = aid == tostring(snapshot.aid)
            local captain = is_self and snapshot.is_captain and ' [队长]' or ''
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
    local history_result = y3.lobby.get_chat_history(nil)
    if not history_result or not history_result.accepted then
        return '大厅服务尚未连接'
    end
    local history = history_result.result_data and history_result.result_data.messages or {}
    local lines = {}
    local first = math.max(1, #history - MAX_CHAT_LINES + 1)
    for index = first, #history do
        local item = history[index]
        local sender = item.sender and (item.sender.name or item.sender.aid) or ''
        local message = tostring(item.message or '')
        lines[#lines + 1] = sender ~= '' and (tostring(sender) .. '：' .. message) or message
    end
    return #lines > 0 and table.concat(lines, '\n') or '暂无聊天消息'
end

local function send_chat_from_input(channel, input)
    local message = input:get_input_field_content()
    if message == '' then
        return false, '消息为空', {
            accepted = false,
            sync = true,
            code = 'empty_message',
            reason = '消息为空',
        }
    end
    local send_result
    if channel == '队伍' then
        send_result = y3.lobby.send_team_chat(message)
    else
        send_result = y3.lobby.send_world_chat(message)
    end
    if send_result and send_result.accepted then
        input:set_text('')
        return true, nil, send_result
    end
    return false,
        send_result and (send_result.reason or send_result.code) or '请求未发出',
        send_result
end

local function safe_send_chat(channel, input)
    local action = channel .. '聊天'
    log_operation('info', '操作发起', action)
    local ok, sent, reason, send_result = xpcall(function()
        return send_chat_from_input(channel, input)
    end, function(message)
        return tostring(message)
    end)
    if not ok then
        log_operation('error', '操作异常', action, {
            accepted = false,
            sync = true,
            code = 'lua_exception',
            reason = sent,
        })
        return false, sent
    end
    if sent then
        log_operation('info', send_result and send_result.sync and '同步完成' or '请求已受理', action,
            send_result or {
                accepted = true,
                sync = false,
                code = 'ok',
                reason = '请求已受理',
            })
    else
        log_operation('warn', '操作拒绝', action, send_result or {
            accepted = false,
            sync = true,
            code = 'request_failed',
            reason = reason or '请求未发出',
        })
    end
    return sent, reason
end

local function cross_room_unavailable_reason(ready, in_team, is_captain, matching, launching, team_count)
    if not ready then
        return '大厅服务未连接'
    end
    if not in_team then
        return '当前未加入队伍'
    end
    if not is_captain then
        return '当前玩家不是队长'
    end
    if matching then
        return '队伍正在匹配'
    end
    if launching then
        return '队伍正在启动关卡'
    end
    if team_count < EXPECTED_PRIVATE_PLAYERS then
        return string.format('队伍人数不足（%d/%d）', team_count, EXPECTED_PRIVATE_PLAYERS)
    end
    return nil
end

local function refresh()
    if not runtime.built then
        return
    end
    local mode = current_mode()
    local snapshot = lobby_state()
    local team_id = snapshot.team_id or 0
    local team_count = snapshot.member_count or #(snapshot.members or {})
    local max_count = snapshot.member_limit or 0

    local battle_mode = not is_lobby_mode(mode)
    if runtime.game_hud then
        runtime.game_hud:set_visible(not battle_mode)
    end
    local matching = snapshot.matching == true
    local launching = snapshot.launching == true
    local team_busy = matching or launching
    local in_team = snapshot.has_team == true
    local is_captain = in_team and snapshot.is_captain == true
    local ready = snapshot.connected == true
    local dungeon_token = current_token()
    runtime.full_panel:set_visible(not battle_mode)
    runtime.status_bg:set_visible(battle_mode)
    runtime.status_text:set_visible(battle_mode)
    runtime.return_button:set_visible(battle_mode)
    runtime.battle_chat_panel:set_visible(battle_mode)
    runtime.status_text:set_text(string.format(
        '模式：%s (%s)    玩家：%s / ID=%s\n大厅服务：%s    连接：%s    AID=%s\n队伍：%s    人数：%s/%s    匹配：%s    启动：%s\n关卡口令：%s',
        mode_label(mode),
        tostring(mode),
        runtime.player:get_name(),
        tostring(runtime.player:get_id()),
        tostring(snapshot.status or '未知'),
        ready and '已连接' or '未连接',
        tostring(snapshot.aid or '-'),
        in_team and tostring(team_id) or '未加入',
        tostring(team_count),
        tostring(max_count),
        matching and '匹配中' or '未匹配',
        launching and '启动中' or '未启动',
        dungeon_token ~= '' and dungeon_token or '-'))

    runtime.leave_button:set_button_enable(in_team and not team_busy)
    local cross_room_reason = cross_room_unavailable_reason(
        ready, in_team, is_captain, matching, launching, team_count)
    local cross_room_enabled = cross_room_reason == nil
    runtime.private_button:set_button_enable(cross_room_enabled)
    local cross_room_log_state = cross_room_enabled and 'available' or cross_room_reason
    if runtime.cross_room_log_state ~= cross_room_log_state then
        runtime.cross_room_log_state = cross_room_log_state
        log_operation('info', cross_room_enabled and '按钮可用' or '按钮不可用', '跨房合流', {
            code = cross_room_enabled and 'enabled' or 'disabled',
            reason = cross_room_enabled and '条件已满足' or cross_room_reason,
        })
    end
    runtime.dismiss_button:set_button_enable(is_captain and not team_busy)
    runtime.battle_token_text:set_text(dungeon_token ~= '' and dungeon_token or '-')
    runtime.battle_copy_button:set_button_enable(dungeon_token ~= '')
    runtime.battle_team_button:set_button_enable(ready and in_team)
    runtime.battle_world_button:set_button_enable(ready)
    runtime.battle_chat_text:set_text(chat_history_text())
    runtime.battle_notice_text:set_text(runtime.battle_notice or '等待消息')
    if runtime.expedition_phase_text then
        runtime.expedition_phase_text:set_text(
            launching and '启动中' or (matching and '匹配中' or '准备阶段'))
    end
    if runtime.action_team_text then
        runtime.action_team_text:set_text(string.format(
            '队伍就绪  %s/%s    当前身份  %s',
            tostring(team_count),
            tostring(max_count),
            is_captain and '队长' or (in_team and '队员' or '单人')))
    end

    local match_text = '开始匹配'
    local match_enabled = false
    if launching then
        match_text = '启动中'
    elseif matching then
        match_text = '取消匹配'
        match_enabled = ready and (not in_team or is_captain)
    elseif ready then
        match_enabled = not in_team or is_captain
    end
    set_button_text(runtime.match_button, match_text)
    runtime.match_button:set_button_enable(match_enabled)

    if battle_mode then
        return
    end

    set_status_value('mode', string.format('%s (%s)', mode_label(mode), tostring(mode)))
    set_status_value('player', string.format('%s / ID=%s', runtime.player:get_name(), runtime.player:get_id()))
    set_status_value('bob', tostring(snapshot.status or '未知'), ready and COLOR_SUCCESS or COLOR_WARNING)
    set_status_value('login', ready and '已连接' or '未连接', ready and COLOR_SUCCESS or COLOR_WARNING)
    set_status_value('aid', tostring(snapshot.aid or '-'))
    set_status_value('team', in_team and tostring(team_id) or '未加入')
    set_status_value('count', string.format('%s/%s', team_count, max_count))
    set_status_value('match', matching and '匹配中' or '未匹配', matching and COLOR_WARNING or COLOR_TEXT)
    set_status_value('launch', launching and '启动中' or '未启动', launching and COLOR_WARNING or COLOR_TEXT)
    refresh_member_rows(snapshot, max_count, is_captain and not team_busy)
    runtime.chat_text:set_text(chat_history_text())
    runtime.notice_text:set_text(runtime.notice or '等待操作')
end

runtime.complete_listener = y3.lobby.on_complete(function(payload)
    payload = type(payload) == 'table' and payload or {}
    local message = tostring(payload.action or '大厅服务') .. '：'
        .. tostring(payload.success and (payload.reason ~= '' and payload.reason or '操作完成')
            or payload.reason or payload.code or '操作失败')
    runtime.notice = message
    runtime.battle_notice = message
    log_operation(payload.success and 'info' or 'error',
        payload.success and '异步完成' or '异步失败',
        payload.action or '大厅服务',
        payload)
    refresh()
end)

runtime.event_listener = y3.lobby.on_event(function(payload)
    payload = type(payload) == 'table' and payload or {}
    log_operation('info', '状态事件', payload.event or '大厅状态', payload)
    refresh()
end)

local function build_chat_panel(parent, x, y, options)
    local width, height = 700, 390
    local panel = parent:create_child('空节点')
    panel:set_anchor(0, 0)
    panel:set_pos(x, y)
    panel:set_ui_size(width, height)
    panel:set_z_order(options.z_order or 0)

    add_panel(panel, 0, 0, width, height, COLOR_PANEL, true)
    add_image(panel, 3, 330, width - 6, 57, 109589, COLOR_PANEL_SOFT)
    add_image(panel, 1, 329, width - 2, 1, 109589, COLOR_BORDER)
    add_text(panel, 18, 354, 112, 22, options.context_label, 13, COLOR_MUTED)

    local token_text
    local copy_button
    if options.with_token then
        token_text = add_text(panel, 132, 346, 390, 34, '-', 17, COLOR_WARNING, '左', '中')
        copy_button = add_button(panel, 542, 340, 140, 42, '复制口令', function()
            if current_token() == '' then
                runtime.battle_notice = '当前没有可复制的关卡口令'
                refresh()
                return
            end
            GameAPI.copy_ui_text_to_clipboard(runtime.player.handle, token_text.handle)
            runtime.battle_notice = '关卡口令已复制到剪贴板'
            refresh()
        end)
    else
        add_text(panel, 132, 346, 390, 34, options.context_value, 17, COLOR_WARNING, '左', '中')
        add_text(panel, 542, 346, 140, 34, '队伍 / 世界', 12, COLOR_MUTED, '右', '中')
    end

    add_text(panel, 18, 300, 180, 24, '最近聊天', 17, COLOR_WARNING)
    add_text(panel, 520, 300, 162, 24, '最多保留 5 条', 12, COLOR_MUTED, '右', '中')
    local chat_text = add_text(panel, 18, 132, 664, 158, '', 15, COLOR_TEXT, '左', '上')
    add_text(panel, 18, 104, 120, 22, '发送消息', 13, COLOR_MUTED)
    local input = add_input(panel, 18, 56, 414, 42)
    local notice_key = options.notice_key
    local function submit(channel)
        local sent, reason = safe_send_chat(channel, input)
        runtime[notice_key] = sent
            and (channel .. '消息已发送')
            or (channel .. '聊天：' .. tostring(reason))
        refresh()
    end
    local team_button = add_button(panel, 444, 56, 112, 42, '队伍聊天', function()
        submit('队伍')
    end)
    local world_button = add_button(panel, 568, 56, 114, 42, '世界聊天', function()
        submit('世界')
    end)
    add_image(panel, 1, 48, width - 2, 1, 109589, COLOR_BORDER)
    add_text(panel, 18, 14, 86, 28, '操作结果', 12, COLOR_MUTED)
    local notice_text = add_text(panel, 108, 14, 574, 28, '', 14, COLOR_SUCCESS, '左', '中')

    return {
        panel = panel,
        chat_text = chat_text,
        input = input,
        team_button = team_button,
        world_button = world_button,
        notice_text = notice_text,
        token_text = token_text,
        copy_button = copy_button,
    }
end

local function build(player)
    if runtime.built then
        return
    end
    local root = y3.ui.get_ui(player, 'BobTestUI')
    if not root then
        error('BobTestUI 根画板不存在')
    end
    runtime.game_hud = y3.ui.get_ui(player, 'GameHUD')
    runtime.player = player

    runtime.backdrop = add_image(root, 0, 0, 1920, 1080, BACKDROP_IMAGE, COLOR_BACKDROP)
    runtime.backdrop:set_intercepts_operations(false)
    runtime.backdrop:set_z_order(-3000)

    runtime.status_bg = root:create_child('空节点')
    runtime.status_bg:set_anchor(0, 0)
    runtime.status_bg:set_pos(24, 856)
    runtime.status_bg:set_ui_size(860, 200)
    runtime.status_bg:set_z_order(9000)
    add_panel(runtime.status_bg, 0, 0, 860, 200, COLOR_PANEL, true)
    add_text(runtime.status_bg, 18, 170, 360, 18, '大厅服务测试 · 关卡上下文', 11, COLOR_MUTED)
    add_text(runtime.status_bg, 18, 136, 420, 30, '大厅服务测试状态', 20, COLOR_TEXT)
    runtime.status_text = add_text(
        runtime.status_bg, 18, 14, 640, 110, '', 15, COLOR_TEXT, '左', '上')
    runtime.return_button = add_button(runtime.status_bg, 680, 136, 160, 48, '返回初始关卡', function()
        safe_action('返回初始关卡', function()
            return y3.lobby.return_lobby({
                level_id = LOBBY_LEVEL_ID,
                game_mode = LOBBY_GAME_MODE,
                max_player = 1,
            })
        end)
        runtime.battle_notice = runtime.notice
        refresh()
    end)

    local battle_chat = build_chat_panel(root, 24, 24, {
        context_label = '关卡口令',
        notice_key = 'battle_notice',
        with_token = true,
        z_order = 9000,
    })
    runtime.battle_chat_panel = battle_chat.panel
    runtime.battle_token_text = battle_chat.token_text
    runtime.battle_copy_button = battle_chat.copy_button
    runtime.battle_chat_text = battle_chat.chat_text
    runtime.battle_chat_input = battle_chat.input
    runtime.battle_team_button = battle_chat.team_button
    runtime.battle_world_button = battle_chat.world_button
    runtime.battle_notice_text = battle_chat.notice_text

    runtime.exit_button = add_button(root, 0, 0, 150, 48, '退出游戏', function()
        runtime.exit_confirm_overlay:set_visible(true)
    end, 'danger')
    runtime.exit_button:set_relative_parent_pos('顶部', 24)
    runtime.exit_button:set_relative_parent_pos('右侧', 24)
    runtime.exit_button:set_z_order(10000)

    runtime.exit_confirm_overlay = add_image(root, 0, 0, 1920, 1080, 109589, { 0, 0, 0, 190 })
    runtime.exit_confirm_overlay:set_intercepts_operations(true)
    runtime.exit_confirm_overlay:set_z_order(20000)
    local exit_confirm_panel = add_panel(
        runtime.exit_confirm_overlay, 720, 400, 480, 280, COLOR_PANEL_DEEP, true)
    runtime.exit_confirm_panel = exit_confirm_panel
    add_text(exit_confirm_panel, 36, 204, 406, 40, '确认退出游戏？', 26, COLOR_DANGER, '中', '中')
    add_text(exit_confirm_panel, 36, 126, 406, 56,
        '退出后将清理当前匹配和组队状态。', 17, COLOR_TEXT, '中', '中')
    runtime.exit_cancel_button = add_button(exit_confirm_panel, 42, 36, 180, 52, '取消', function()
        runtime.exit_confirm_overlay:set_visible(false)
    end)
    runtime.exit_confirm_button = add_button(exit_confirm_panel, 258, 36, 180, 52, '确认退出', function()
        runtime.exit_confirm_overlay:set_visible(false)
        safe_action('退出游戏', y3.lobby.exit_game)
    end, 'danger')
    runtime.exit_confirm_overlay:set_visible(false)

    local panel = root:create_child('空节点')
    panel:set_anchor(0, 0)
    panel:set_pos(0, 0)
    panel:set_ui_size(1920, 1080)
    panel:set_z_order(-1000)
    runtime.full_panel = panel

    add_panel(panel, 24, 936, 430, 120, COLOR_PANEL, true)
    add_text(panel, 42, 1022, 280, 18, '方案 B · 沉浸远征', 12, COLOR_WARNING)
    add_text(panel, 42, 978, 320, 38, '大厅服务测试系统', 24, COLOR_TEXT)
    add_text(panel, 42, 952, 320, 22, '组队、匹配与关卡切换', 13, COLOR_MUTED)

    add_panel(panel, 470, 936, 1004, 120, COLOR_PANEL, true)
    runtime.status_values = {}
    local status_specs = {
        { 'mode', '模式', 488, 994, 150 },
        { 'player', '玩家', 646, 994, 210 },
        { 'bob', '服务', 864, 994, 105 },
        { 'login', '连接', 977, 994, 105 },
        { 'aid', 'AID', 1090, 994, 366 },
        { 'team', '队伍', 488, 946, 210 },
        { 'count', '人数', 706, 946, 100 },
        { 'match', '匹配', 814, 946, 150 },
        { 'launch', '启动', 972, 946, 150 },
    }
    for _, spec in ipairs(status_specs) do
        enable_nine_slice(add_image(panel, spec[3], spec[4], spec[5], 42, PANEL_IMAGES.soft), 8)
        add_text(panel, spec[3] + 10, spec[4] + 23, spec[5] - 20, 15, spec[2], 11, COLOR_MUTED, '左', '中')
        runtime.status_values[spec[1]] = add_text(
            panel, spec[3] + 10, spec[4] + 3, spec[5] - 20, 20, '', 14, COLOR_TEXT, '左', '中')
    end

    runtime.team_panel = add_panel(panel, 24, 426, 520, 494, COLOR_PANEL, true)
    add_image(panel, 27, 856, 514, 61, 109589, COLOR_PANEL_SOFT)
    add_text(panel, 42, 878, 210, 26, '远征小队', 19, COLOR_WARNING)
    add_text(panel, 334, 878, 190, 26, '队伍管理与成员状态', 12, COLOR_MUTED, '右', '中')
    add_text(panel, 42, 838, 120, 22, '队伍编号', 13, COLOR_MUTED)
    runtime.team_input = add_input(panel, 42, 792, 184, 42)
    add_button(panel, 236, 792, 92, 42, '加入', function()
        local team_id = math.tointeger(runtime.team_input:get_input_field_content())
        if not team_id then
            runtime.notice = '加入队伍：请输入有效数字编号'
            log_operation('warn', '操作拒绝', '加入队伍', {
                accepted = false,
                sync = true,
                code = 'invalid_input',
                reason = '请输入有效数字编号',
            })
            refresh()
            return
        end
        safe_action('加入队伍', function()
            return y3.lobby.join_team(team_id)
        end)
    end)
    add_button(panel, 338, 792, 96, 42, '创建队伍', function()
        safe_action('创建队伍', function()
            return y3.lobby.create_team(EXPECTED_PRIVATE_PLAYERS)
        end)
    end)
    runtime.leave_button = add_button(panel, 444, 792, 82, 42, '离队', function()
        safe_action('离开队伍', y3.lobby.leave_team)
    end)

    add_text(panel, 42, 752, 180, 24, '队员列表', 16, COLOR_TEXT)
    runtime.member_count_text = add_text(panel, 326, 752, 70, 24, '', 14, COLOR_MUTED, '右', '中')
    runtime.dismiss_button = add_button(panel, 408, 744, 118, 42, '解散队伍', function()
        safe_action('解散队伍', y3.lobby.dismiss_team)
    end, 'danger')
    add_text(panel, 54, 720, 38, 20, '序号', 11, COLOR_MUTED)
    add_text(panel, 96, 720, 132, 20, '玩家', 11, COLOR_MUTED)
    add_text(panel, 236, 720, 92, 20, 'AID', 11, COLOR_MUTED)
    add_text(panel, 336, 720, 70, 20, '状态', 11, COLOR_MUTED)
    add_text(panel, 424, 720, 102, 20, '操作', 11, COLOR_MUTED, '右', '中')

    runtime.member_rows = {}
    for index = 1, MAX_MEMBER_ROWS do
        local row = {}
        row.container = panel:create_child('空节点')
        row.container:set_anchor(0, 0)
        row.container:set_pos(40, 650 - (index - 1) * 64)
        row.container:set_ui_size(488, 56)
        add_panel(row.container, 0, 0, 488, 56, COLOR_PANEL_SOFT)
        row.index_text = add_text(row.container, 12, 0, 30, 56, '', 14, COLOR_TEXT)
        row.name_text = add_text(row.container, 50, 0, 130, 56, '', 14, COLOR_TEXT)
        row.aid_text = add_text(row.container, 188, 0, 100, 56, '', 13, COLOR_MUTED)
        row.state_text = add_text(row.container, 296, 0, 66, 56, '', 13, COLOR_SUCCESS)
        row.current_text = add_text(row.container, 368, 0, 106, 56, '当前玩家', 12, COLOR_MUTED, '右', '中')
        row.transfer_button = add_button(row.container, 358, 7, 60, 42, '转让', function()
            if row.aid then
                safe_action('转移队长', function() return y3.lobby.change_captain(row.aid) end)
                refresh()
            end
        end)
        row.kick_button = add_button(row.container, 426, 7, 50, 42, '移出', function()
            if row.aid then
                safe_action('移出队员', function() return y3.lobby.kick_member(row.aid) end)
                refresh()
            end
        end, 'danger')
        runtime.member_rows[index] = row
    end

    runtime.expedition_panel = add_panel(panel, 650, 438, 620, 358, COLOR_PANEL, true)
    add_text(panel, 676, 750, 180, 20, '当前远征', 12, COLOR_WARNING)
    runtime.expedition_phase_text = add_text(
        panel, 1050, 744, 194, 28, '准备阶段', 13, COLOR_SUCCESS, '右', '中')
    add_panel(panel, 670, 472, 580, 250, COLOR_PANEL_SOFT)
    add_text(panel, 696, 670, 180, 18, '本轮远征', 11, COLOR_WARNING)
    add_text(panel, 696, 622, 360, 42, '暮潮遗迹', 28, COLOR_TEXT)
    add_text(panel, 696, 580, 520, 36, '匹配、口令与分流合流状态验证', 13, COLOR_MUTED)
    add_text(panel, 696, 526, 120, 18, '预计席位', 11, COLOR_MUTED)
    add_text(panel, 696, 494, 120, 26, tostring(EXPECTED_PRIVATE_PLAYERS), 17, COLOR_TEXT)
    add_text(panel, 854, 526, 120, 18, '队伍上限', 11, COLOR_MUTED)
    add_text(panel, 854, 494, 120, 26, tostring(MAX_MEMBER_ROWS), 17, COLOR_TEXT)
    add_text(panel, 1012, 526, 160, 18, '启动方式', 11, COLOR_MUTED)
    add_text(panel, 1012, 494, 190, 26, '匹配 / 口令', 17, COLOR_TEXT)

    runtime.action_panel = add_panel(panel, 1340, 24, 556, 390, COLOR_PANEL, true)
    add_image(panel, 1343, 350, 550, 61, 109589, COLOR_PANEL_SOFT)
    add_text(panel, 1358, 372, 260, 26, '匹配与副本', 19, COLOR_WARNING)
    add_text(panel, 1690, 372, 186, 26, '队长权限', 12, COLOR_MUTED, '右', '中')
    runtime.match_button = add_button(panel, 1358, 294, 174, 42, '开始匹配', function()
        if lobby_state().matching then
            safe_action('取消匹配', y3.lobby.cancel_match)
        else
            safe_action('开始匹配', function()
                return y3.lobby.start_match({
                    level_id = MATCH_LEVEL_ID,
                    game_mode = MATCH_GAME_MODE,
                    score = 1000,
                })
            end)
        end
        refresh()
    end)
    runtime.same_room_button = add_button(panel, 1544, 294, 160, 42, '同房分流', function()
        safe_action('同房分流', function()
            return y3.lobby.same_room_split({
                level_id = SAME_ROOM_LEVEL_ID,
                game_mode = PRIVATE_GAME_MODE,
                max_player = EXPECTED_PRIVATE_PLAYERS,
            })
        end)
    end)
    runtime.cross_room_button = add_button(panel, 1716, 294, 160, 42, '跨房合流', function()
        safe_action('跨房合流', function()
            local snapshot = lobby_state()
            local players = {}
            for _, member in ipairs(snapshot.members or {}) do
                players[#players + 1] = { aid = member.aid }
            end
            return y3.lobby.cross_room_merge({
                game_map_id = snapshot.game_map_id,
                level_id = MATCH_LEVEL_ID,
                game_mode = PRIVATE_GAME_MODE,
                players = players,
            })
        end)
    end, 'primary')
    runtime.private_button = runtime.cross_room_button
    add_text(panel, 1358, 256, 160, 22, '关卡口令', 13, COLOR_MUTED)
    runtime.dungeon_input = add_input(panel, 1358, 206, 340, 42)
    runtime.dungeon_join_button = add_button(panel, 1710, 206, 166, 42, '加入副本', function()
        local token = runtime.dungeon_input:get_input_field_content()
        if token == '' or token:match('^%s*$') then
            runtime.notice = '加入口令：请输入关卡口令'
            log_operation('warn', '操作拒绝', '加入口令', {
                accepted = false,
                sync = true,
                code = 'invalid_input',
                reason = '请输入关卡口令',
            })
            refresh()
            return
        end
        local sent = safe_action('加入口令', function()
            return y3.lobby.join_by_token(token)
        end)
        if sent then
            runtime.notice = '加入口令请求已受理；目标房间需允许中途加入'
        end
        refresh()
    end)
    runtime.action_team_text = add_text(panel, 1358, 150, 518, 30, '', 14, COLOR_TEXT)
    add_text(panel, 1358, 104, 518, 34,
        '目标模式 1002 / 1003', 12, COLOR_MUTED)

    local lobby_chat = build_chat_panel(panel, 24, 24, {
        context_label = '聊天上下文',
        context_value = '组队大厅',
        notice_key = 'notice',
    })
    runtime.chat_panel = lobby_chat.panel
    runtime.chat_text = lobby_chat.chat_text
    runtime.chat_input = lobby_chat.input
    runtime.chat_team_button = lobby_chat.team_button
    runtime.chat_world_button = lobby_chat.world_button
    runtime.notice_text = lobby_chat.notice_text

    runtime.built = true
    runtime.notice = '测试 UI 已就绪'
    refresh()
    runtime.refresh_timer = y3.ltimer.loop(0.5, refresh)
    log.info('[LobbyTestUI] runtime panel created')
end

local function schedule_build(player)
    y3.ltimer.wait_frame(5, function()
        local ok, err = xpcall(function()
            if runtime.built then
                runtime.player = player
                refresh()
                if not runtime.refresh_timer then
                    runtime.refresh_timer = y3.ltimer.loop(0.5, refresh)
                end
                return
            end
            build(player)
        end, function(message)
            return tostring(message)
        end)
        if not ok then
            log.error('[LobbyTestUI] create failed: ' .. tostring(err))
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
