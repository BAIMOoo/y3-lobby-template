local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function assert_log_contains(entries, level, fragments, message)
    for _, entry in ipairs(entries) do
        if entry.level == level then
            local matched = true
            for _, fragment in ipairs(fragments) do
                if not string.find(entry.message, fragment, 1, true) then
                    matched = false
                    break
                end
            end
            if matched then
                return
            end
        end
    end
    error(message .. ': expected ' .. level .. ' log containing ' .. table.concat(fragments, ', '))
end

local function assert_log_excludes(entries, fragment, message)
    for _, entry in ipairs(entries) do
        if string.find(entry.message, fragment, 1, true) then
            error(message .. ': unexpected log content ' .. fragment)
        end
    end
end

local next_ui_handle = 0

local function new_ui(kind)
    next_ui_handle = next_ui_handle + 1
    local ui = {
        kind = kind,
        handle = 'ui-' .. tostring(next_ui_handle),
        children = {},
        enabled = true,
        visible = true,
        relative_parent_pos = {},
        status_images = {},
    }

    function ui:create_child(child_kind)
        local child = new_ui(child_kind)
        self.children[#self.children + 1] = child
        return child
    end

    function ui:set_anchor() end
    function ui:set_pos(x, y)
        self.x = x
        self.y = y
    end
    function ui:set_ui_size(width, height)
        self.width = width
        self.height = height
    end
    function ui:set_font_size() end
    function ui:set_text_color() end
    function ui:set_btn_status_image(status, image) self.status_images[status] = image end
    function ui:set_image(image) self.image = image end
    function ui:set_image_color(red, green, blue, alpha)
        self.image_color = { red, green, blue, alpha }
    end
    function ui:set_ui_9_enable(enabled) self.nine_slice_enabled = enabled end
    function ui:set_ui_9(left, right, top, bottom)
        self.nine_slice = { left, right, top, bottom }
    end
    function ui:set_text_alignment() end
    function ui:set_relative_parent_pos(direction, offset)
        self.relative_parent_pos[direction] = offset
    end
    function ui:set_z_order(depth) self.z_order = depth end
    function ui:set_intercepts_operations(intercepts) self.intercepts_operations = intercepts end
    function ui:set_visible(visible) self.visible = visible end
    function ui:set_button_enable(enabled) self.enabled = enabled end
    function ui:set_text(text) self.text = text end
    function ui:set_btn_status_string(_, text) self.text = text end
    function ui:add_local_event(_, callback) self.click_callback = callback end
    function ui:get_input_field_content() return self.text or '' end

    function ui:click()
        if self.enabled and self.click_callback then
            self.click_callback()
        end
    end

    return ui
end

local function collect_match_buttons(ui, result)
    result = result or {}
    if ui.kind == '按钮' and (ui.text == '开始匹配' or ui.text == '取消匹配' or ui.text == '启动中') then
        result[#result + 1] = ui
    end
    for _, child in ipairs(ui.children) do
        collect_match_buttons(child, result)
    end
    return result
end

local function collect_buttons_by_text(ui, text, result)
    result = result or {}
    if ui.kind == '按钮' and ui.text == text then
        result[#result + 1] = ui
    end
    for _, child in ipairs(ui.children) do
        collect_buttons_by_text(child, text, result)
    end
    return result
end

local function run_case(path)
    local join_callback
    local refresh_callback
    local complete_callback
    local event_callback
    local refresh_loop_count = 0
    local start_count = 0
    local cancel_count = 0
    local exit_count = 0
    local return_count = 0
    local dungeon_join_count = 0
    local dungeon_join_token
    local join_by_token_error = false
    local copied_role
    local copied_ui_handle
    local team_chat_message
    local world_chat_message
    local throw_team_chat = false
    local private_dungeon_count = 0
    local private_dungeon_params
    local private_dungeon_result
    local private_dungeon_error
    local start_match_params
    local return_lobby_params
    local current_mode = 1001
    local dungeon_token = ''
    local root = new_ui('根节点')
    local game_hud = new_ui('根节点')
    local log_entries = {}
    local player = {
        handle = 'player-handle',
        get_name = function() return '测试玩家' end,
        get_id = function() return 1 end,
    }

    local state = {
        ready = true,
        matching = false,
        launching = false,
    }
    BOB = {
        aid = 1001,
        state = 'connected',
        team_info = nil,
        message_history = {},
    }

    local function accepted(action, result_data, sync)
        return {
            accepted = true,
            action = action,
            request_id = sync and '' or 'test-request',
            reason = sync and '结果已返回' or '请求已受理',
            code = 'ok',
            sync = sync == true,
            result_data = result_data or {},
        }
    end

    local function cross_map_accepted(action, extra)
        local result_data = {
            cross_map_tracking = 'degraded',
            platform_requested = true,
            entered_target = 'unknown',
        }
        for key, value in pairs(extra or {}) do
            result_data[key] = value
        end
        return {
            accepted = true,
            action = action,
            request_id = '',
            reason = '请求已发送，等待切图',
            code = 'ok',
            sync = false,
            result_data = result_data,
        }
    end

    local function capture_log(level, ...)
        local values = table.pack(...)
        for index = 1, values.n do
            values[index] = tostring(values[index])
        end
        log_entries[#log_entries + 1] = {
            level = level,
            message = table.concat(values, '\t', 1, values.n),
        }
    end
    log = {
        info = function(...) capture_log('info', ...) end,
        warn = function(...) capture_log('warn', ...) end,
        error = function(...) capture_log('error', ...) end,
    }
    GameAPI = {
        api_get_current_game_mode = function() return current_mode end,
        get_dungeon_info = function() return {} end,
        copy_ui_text_to_clipboard = function(role, ui_handle)
            copied_role = role
            copied_ui_handle = ui_handle
        end,
        set_ui_btn_status_cap_insets = function() end,
    }
    y3 = {
        const = {
            UIButtonStatus = {
                ['常态'] = '常态',
                ['悬浮'] = '悬浮',
                ['按下'] = '按下',
                ['禁用'] = '禁用',
            },
        },
        game = {
            event = function(_, event_name, callback)
                if event_name == '玩家-加入游戏' then
                    join_callback = callback
                end
                return {}
            end,
            get_current_game_mode = function() return current_mode end,
        },
        player = {
            with_local = function(callback) callback(player) end,
        },
        ui = {
            get_ui = function(_, ui_name)
                local roots = {
                    BobTestUI = root,
                    GameHUD = game_hud,
                }
                return roots[ui_name]
            end,
        },
        ltimer = {
            wait_frame = function(_, callback) callback() end,
            loop = function(_, callback)
                refresh_loop_count = refresh_loop_count + 1
                refresh_callback = callback
                return { remove = function() end }
            end,
        },
        lobby = {
            on_complete = function(callback)
                complete_callback = callback
                return {
                    remove = function()
                        if complete_callback == callback then
                            complete_callback = nil
                        end
                    end,
                }
            end,
            on_event = function(callback)
                event_callback = callback
                return {
                    remove = function()
                        if event_callback == callback then
                            event_callback = nil
                        end
                    end,
                }
            end,
            get_state = function()
                local team_info = BOB.team_info
                local members = team_info and team_info.members or {}
                return accepted('获取状态快照', {
                    status = state.ready and 'connected' or 'idle',
                    connected = state.ready,
                    aid = BOB.aid,
                    has_team = team_info ~= nil,
                    team_id = team_info and team_info.team_id or nil,
                    members = members,
                    member_count = #members,
                    member_limit = 4,
                    is_captain = team_info ~= nil and team_info.captain == BOB.aid,
                    matching = state.matching,
                    launching = state.launching,
                    token = dungeon_token,
                    game_map_id = 'test-game-map-id',
                }, true)
            end,
            get_token = function()
                return accepted('获取口令', { token = dungeon_token }, true)
            end,
            get_chat_history = function()
                if not state.ready then
                    return { accepted = false, reason = '尚未连接', code = 'not_connected' }
                end
                return accepted('获取聊天记录', { messages = BOB.message_history }, true)
            end,
            send_team_chat = function(message)
                if throw_team_chat then
                    error('模拟聊天发送异常：' .. message)
                end
                team_chat_message = message
                return accepted('发送队伍聊天')
            end,
            send_world_chat = function(message)
                world_chat_message = message
                return accepted('发送世界聊天')
            end,
            create_team = function() return accepted('创建队伍') end,
            join_team = function() return accepted('加入队伍') end,
            leave_team = function() return accepted('离开队伍') end,
            dismiss_team = function() return accepted('解散队伍') end,
            change_captain = function() return accepted('转移队长') end,
            kick_member = function() return accepted('移出队员') end,
            start_match = function(params)
                start_count = start_count + 1
                start_match_params = params
                return accepted('开始匹配')
            end,
            cancel_match = function()
                cancel_count = cancel_count + 1
                return accepted('取消匹配')
            end,
            private_dungeon = function(params)
                private_dungeon_count = private_dungeon_count + 1
                private_dungeon_params = params
                if private_dungeon_error then
                    error(private_dungeon_error)
                end
                if private_dungeon_result then
                    return private_dungeon_result
                end
                if BOB.team_info then
                    return accepted('局内私人副本', {
                        route = 'team_bob',
                        selected_players = { { aid = BOB.aid } },
                        skipped_in_game_players = {},
                        unknown_status_players = {},
                    })
                end
                return cross_map_accepted('局内私人副本', {
                    route = 'solo_engine',
                    selected_players = {},
                    skipped_in_game_players = {},
                    unknown_status_players = {},
                })
            end,
            join_by_token = function(token)
                if join_by_token_error then
                    error('模拟口令异常：' .. token)
                end
                dungeon_join_count = dungeon_join_count + 1
                dungeon_join_token = token
                return cross_map_accepted('加入口令')
            end,
            return_lobby = function(params)
                return_count = return_count + 1
                return_lobby_params = params
                return cross_map_accepted('返回大厅')
            end,
            exit_game = function()
                exit_count = exit_count + 1
                return accepted('退出游戏')
            end,
        },
    }

    _G.__LOBBY_TEST_UI_RUNTIME = nil
    _G.__BOB_TEST_UI_RUNTIME = nil
    dofile(path)
    _G.__BOB_TEST_UI_RUNTIME = _G.__LOBBY_TEST_UI_RUNTIME
    assert(join_callback, path .. ' must bind player join event')
    join_callback(nil, { player = player })
    assert(refresh_callback, path .. ' must create refresh timer')
    assert(complete_callback, path .. ' must listen for async completion')
    assert(event_callback, path .. ' must listen for lobby state events')
    assert_equal(refresh_loop_count, 1, path .. ' creates one refresh timer')
    join_callback(nil, { player = player })
    assert_equal(refresh_loop_count, 1, path .. ' reuses the existing refresh timer')
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 按钮可用',
        'action=局内私人副本',
        'code=enabled',
        'reason=条件已满足',
    }, path .. ' logs that solo private dungeon is initially available')

    event_callback({
        event = 'team_changed',
        status = 'connected',
        code = 'ok',
        reason = '队伍信息已更新',
        sequence = 7,
    })
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 状态事件',
        'action=team_changed',
        'code=ok',
        'reason=队伍信息已更新',
        'sequence=7',
    }, path .. ' logs lobby state events')
    event_callback({
        event = 'connection_changed',
        status = 'failed',
        code = 'connect_failed',
        reason = 'token=event-connection-secret',
        sequence = 8,
    })
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 状态事件',
        'action=connection_changed',
        'code=connect_failed',
        'reason=敏感详情已省略',
        'sequence=8',
    }, path .. ' redacts connection state event details')
    assert_log_excludes(log_entries, 'event-connection-secret',
        path .. ' does not log connection state tokens')

    complete_callback({
        request_id = 'request-success',
        action = '开始匹配',
        success = true,
        code = 'ok',
        reason = '匹配已完成',
    })
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 异步完成',
        'action=开始匹配',
        'success=true',
        'request_id=request-success',
        'reason=匹配已完成',
    }, path .. ' logs async success')
    complete_callback({
        request_id = 'request-failure',
        action = '局内私人副本',
        success = false,
        code = 'room_missing',
        reason = '目标房间不存在',
    })
    assert_log_contains(log_entries, 'error', {
        '[LobbyTestUI] 异步失败',
        'action=局内私人副本',
        'success=false',
        'request_id=request-failure',
        'code=room_missing',
        'reason=目标房间不存在',
    }, path .. ' logs async failure')
    complete_callback({
        request_id = 'request-connect-failure',
        action = '建立连接',
        success = false,
        code = 'connect_failed',
        reason = 'token=connection-secret',
    })
    assert_log_contains(log_entries, 'error', {
        '[LobbyTestUI] 异步失败',
        'action=建立连接',
        'code=connect_failed',
        'reason=敏感详情已省略',
    }, path .. ' redacts connection failure details')
    assert_log_excludes(log_entries, 'connection-secret', path .. ' does not log connection tokens')

    local exit_button = assert(_G.__BOB_TEST_UI_RUNTIME.exit_button, path .. ' must create exit button')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.full_panel.z_order,
        -1000,
        path .. ' lobby control panel stays below platform dialogs')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.full_panel.width, 1920, path .. ' lobby uses full design width')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.full_panel.height, 1080, path .. ' lobby uses full design height')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.backdrop.width, 1920, path .. ' backdrop uses full design width')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.backdrop.height, 1080, path .. ' backdrop uses full design height')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.backdrop.image, 134230328, path .. ' backdrop uses generated expedition art')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.backdrop.image_color[1], 255, path .. ' backdrop keeps original red channel')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.backdrop.image_color[2], 255, path .. ' backdrop keeps original green channel')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.backdrop.image_color[3], 255, path .. ' backdrop keeps original blue channel')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.backdrop.image_color[4], 255, path .. ' backdrop remains fully opaque')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.backdrop.z_order, -3000, path .. ' backdrop stays behind product UI')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.backdrop.intercepts_operations,
        false,
        path .. ' backdrop never blocks test controls')
    assert_equal(game_hud.visible, true, path .. ' default HUD remains visible in lobby')
    assert_equal(exit_button.width, 150, path .. ' exit button width')
    assert_equal(exit_button.height, 48, path .. ' exit button height')
    assert_equal(exit_button.relative_parent_pos['顶部'], 24, path .. ' exit button top safe margin')
    assert_equal(exit_button.relative_parent_pos['右侧'], 24, path .. ' exit button stays in the top-right corner')
    assert_equal(exit_button.z_order, 10000, path .. ' exit button stays above test panel')
    local exit_overlay = assert(
        _G.__BOB_TEST_UI_RUNTIME.exit_confirm_overlay,
        path .. ' must create exit confirmation overlay')
    local exit_cancel_button = assert(
        _G.__BOB_TEST_UI_RUNTIME.exit_cancel_button,
        path .. ' must create exit cancel button')
    local exit_confirm_button = assert(
        _G.__BOB_TEST_UI_RUNTIME.exit_confirm_button,
        path .. ' must create exit confirm button')
    assert_equal(exit_overlay.visible, false, path .. ' exit confirmation starts hidden')
    assert_equal(exit_overlay.intercepts_operations, true, path .. ' exit confirmation blocks background input')
    assert_equal(exit_overlay.z_order, 20000, path .. ' exit confirmation stays above all panels')

    local dungeon_input = assert(_G.__BOB_TEST_UI_RUNTIME.dungeon_input, path .. ' must create dungeon token input')
    local dungeon_join_button = assert(
        _G.__BOB_TEST_UI_RUNTIME.dungeon_join_button,
        path .. ' must create dungeon join button')
    assert_equal(dungeon_input:get_input_field_content(), '', path .. ' dungeon input starts empty')
    dungeon_join_button:click()
    assert_equal(dungeon_join_count, 0, path .. ' empty dungeon token does not send a request')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.notice_text.text,
        '加入口令：请输入关卡口令',
        path .. ' empty dungeon token shows actionable feedback')
    assert_log_contains(log_entries, 'warn', {
        '[LobbyTestUI] 操作拒绝',
        'action=加入口令',
        'code=invalid_input',
        'reason=请输入关卡口令',
    }, path .. ' logs empty dungeon token rejection')
    dungeon_input:set_text('space/token+1=')
    dungeon_join_button:click()
    assert_equal(dungeon_join_count, 1, path .. ' dungeon join button request count')
    assert_equal(dungeon_join_token, 'space/token+1=', path .. ' dungeon join button token')
    assert_equal(
        dungeon_input:get_input_field_content(),
        'space/token+1=',
        path .. ' dungeon input remains available after request')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.notice_text.text,
        '加入口令请求已发送，等待切图；目标房间需允许中途加入',
        path .. ' dungeon join request feedback')
    join_by_token_error = true
    dungeon_join_button:click()
    assert_log_contains(log_entries, 'error', {
        '[LobbyTestUI] 操作异常',
        'action=加入口令',
        'code=lua_exception',
        'reason=敏感详情已省略',
    }, path .. ' redacts dungeon token exceptions')
    join_by_token_error = false

    local private_button = assert(
        _G.__BOB_TEST_UI_RUNTIME.private_button,
        path .. ' must create one private dungeon button')
    assert_equal(#collect_buttons_by_text(root, '局内私人副本'), 1, path .. ' must create exactly one private dungeon button')
    assert_equal(#collect_buttons_by_text(root, '同房分流'), 0, path .. ' must not create old same-room split button')
    assert_equal(#collect_buttons_by_text(root, '跨房合流'), 0, path .. ' must not create old cross-room merge button')
    private_button:click()
    assert_equal(private_dungeon_count, 1, path .. ' solo private dungeon sends one request')
    assert(private_dungeon_params, path .. ' private dungeon button sends parameters')
    assert_equal(
        private_dungeon_params.game_map_id,
        'test-game-map-id',
        path .. ' private dungeon current map version id')
    assert_equal(
        private_dungeon_params.level_id,
        '50377054694119407947881484918402159964',
        path .. ' private dungeon target level')
    assert_equal(
        private_dungeon_params.engine_level_id,
        '25e6448f-7e73-11f1-88ae-03dc5a85955c',
        path .. ' private dungeon engine target level')
    assert_equal(private_dungeon_params.game_mode, 1003, path .. ' private dungeon target mode')
    assert_equal(private_dungeon_params.max_player, 2, path .. ' private dungeon player limit')
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 操作发起',
        'action=局内私人副本',
    }, path .. ' logs private dungeon action start')
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 请求已发送',
        'action=局内私人副本',
        'accepted=true',
        'request_id=',
        'route=solo_engine',
    }, path .. ' logs solo private dungeon submission')

    private_dungeon_result = {
        accepted = false,
        action = '局内私人副本',
        request_id = '',
        reason = '大厅服务未连接',
        code = 'not_connected',
        sync = true,
        result_data = {
            route = 'rejected',
            selected_players = {},
            skipped_in_game_players = {},
            unknown_status_players = {},
        },
    }
    private_button:click()
    assert_log_contains(log_entries, 'warn', {
        '[LobbyTestUI] 操作拒绝',
        'action=局内私人副本',
        'accepted=false',
        'code=not_connected',
        'reason=大厅服务未连接',
        'route=rejected',
    }, path .. ' logs private dungeon synchronous rejection')

    private_dungeon_result = nil
    private_dungeon_error = '模拟局内私人副本异常'
    private_button:click()
    assert_log_contains(log_entries, 'error', {
        '[LobbyTestUI] 操作异常',
        'action=局内私人副本',
        'code=lua_exception',
        '模拟局内私人副本异常',
    }, path .. ' logs private dungeon exceptions')
    private_dungeon_error = nil

    local battle_panel = assert(_G.__BOB_TEST_UI_RUNTIME.battle_chat_panel, path .. ' must create battle chat panel')
    local lobby_chat_panel = assert(
        _G.__BOB_TEST_UI_RUNTIME.chat_panel,
        path .. ' must create lobby chat panel')
    local battle_token_text = assert(
        _G.__BOB_TEST_UI_RUNTIME.battle_token_text,
        path .. ' must create battle token text')
    local battle_copy_button = assert(
        _G.__BOB_TEST_UI_RUNTIME.battle_copy_button,
        path .. ' must create battle token copy button')
    assert_equal(battle_panel.visible, false, path .. ' battle chat hidden in lobby')
    assert_equal(battle_panel.z_order, 9000, path .. ' battle chat z order')
    assert_equal(lobby_chat_panel.width, battle_panel.width, path .. ' chat panels share width')
    assert_equal(lobby_chat_panel.height, battle_panel.height, path .. ' chat panels share height')
    assert_equal(lobby_chat_panel.x, 24, path .. ' lobby chat stays on the lower-left edge')
    assert_equal(lobby_chat_panel.y, 24, path .. ' lobby chat keeps bottom safe margin')
    assert_equal(battle_panel.x, 24, path .. ' battle chat stays on the left edge')
    assert_equal(battle_panel.y, 24, path .. ' battle chat keeps bottom safe margin')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.team_panel.x, 24, path .. ' team panel stays on the left edge')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.team_panel.y, 426, path .. ' team panel clears lobby chat')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.expedition_panel,
        nil,
        path .. ' omits the expedition summary')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.action_panel.x, 1340, path .. ' action panel stays on the right edge')

    current_mode = 1003
    dungeon_token = 'space/token+1='
    BOB.team_info = {
        captain = BOB.aid,
        members = { { aid = BOB.aid, name = '测试玩家', state = '游戏中' } },
    }
    refresh_callback()
    assert_equal(private_button.enabled, true, path .. ' captain may start a private dungeon with one member')
    assert_equal(battle_panel.visible, true, path .. ' battle chat visible in dungeon')
    assert_equal(game_hud.visible, false, path .. ' default HUD hidden in dungeon')
    assert_equal(battle_token_text.text, dungeon_token, path .. ' battle token text')
    battle_copy_button:click()
    assert_equal(copied_role, player.handle, path .. ' clipboard role handle')
    assert_equal(copied_ui_handle, battle_token_text.handle, path .. ' clipboard text handle')
    _G.__BOB_TEST_UI_RUNTIME.return_button:click()
    assert_equal(return_count, 1, path .. ' return button request count')
    assert_equal(
        return_lobby_params.level_id,
        '81ad7554-7e6b-11f1-8f5c-c78cd393ba6e',
        path .. ' return lobby target level')
    assert_equal(return_lobby_params.game_mode, 1001, path .. ' return lobby target mode')
    assert_equal(return_lobby_params.max_player, 1, path .. ' return lobby player limit')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.battle_notice_text.text,
        '返回初始关卡：请求已发送，等待切图',
        path .. ' return button feedback stays visible in battle')

    local battle_chat_input = assert(
        _G.__BOB_TEST_UI_RUNTIME.battle_chat_input,
        path .. ' must create battle chat input')
    assert_equal(battle_chat_input:get_input_field_content(), '', path .. ' battle chat input starts empty')
    _G.__BOB_TEST_UI_RUNTIME.battle_team_button:click()
    _G.__BOB_TEST_UI_RUNTIME.battle_world_button:click()
    assert_equal(team_chat_message, nil, path .. ' empty team chat does not send')
    assert_equal(world_chat_message, nil, path .. ' empty world chat does not send')
    assert_log_contains(log_entries, 'warn', {
        '[LobbyTestUI] 操作拒绝',
        'action=队伍聊天',
        'code=empty_message',
        'reason=消息为空',
    }, path .. ' logs empty chat rejection')
    battle_chat_input:set_text('队伍消息')
    _G.__BOB_TEST_UI_RUNTIME.battle_team_button:click()
    assert_equal(team_chat_message, '队伍消息', path .. ' battle team chat message')
    assert_equal(battle_chat_input:get_input_field_content(), '', path .. ' battle team input clears')
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 请求已受理',
        'action=队伍聊天',
        'accepted=true',
    }, path .. ' logs chat acceptance')
    battle_chat_input:set_text('世界消息')
    _G.__BOB_TEST_UI_RUNTIME.battle_world_button:click()
    assert_equal(world_chat_message, '世界消息', path .. ' battle world chat message')
    assert_equal(battle_chat_input:get_input_field_content(), '', path .. ' battle world input clears')
    throw_team_chat = true
    battle_chat_input:set_text('异常消息')
    _G.__BOB_TEST_UI_RUNTIME.battle_team_button:click()
    assert_equal(
        battle_chat_input:get_input_field_content(),
        '异常消息',
        path .. ' failed battle chat keeps input for retry')
    assert(
        string.find(_G.__BOB_TEST_UI_RUNTIME.battle_notice_text.text, '模拟聊天发送异常', 1, true),
        path .. ' failed battle chat reports the exception')
    assert_log_contains(log_entries, 'error', {
        '[LobbyTestUI] 操作异常',
        'action=队伍聊天',
        'code=lua_exception',
        'reason=敏感详情已省略',
    }, path .. ' logs chat exceptions')
    throw_team_chat = false
    assert_log_excludes(log_entries, '队伍消息', path .. ' does not log chat content')
    assert_log_excludes(log_entries, '世界消息', path .. ' does not log chat content')
    assert_log_excludes(log_entries, '异常消息', path .. ' does not log failed chat content')
    assert_log_excludes(log_entries, 'space/token+1=', path .. ' does not log dungeon tokens')

    current_mode = 1001
    dungeon_token = ''
    BOB.team_info = nil
    BOB.message_history = {
        { message = '消息1' },
        { message = '消息2' },
        { message = '消息3' },
        { message = '消息4' },
        { message = '消息5' },
        { message = '消息6' },
        { message = '消息7' },
    }
    refresh_callback()
    assert_equal(game_hud.visible, true, path .. ' default HUD restored in lobby')
    local expected_history = '消息3\n消息4\n消息5\n消息6\n消息7'
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.chat_text.text,
        expected_history,
        path .. ' lobby chat keeps exactly five latest messages')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.battle_chat_text.text,
        expected_history,
        path .. ' battle chat keeps exactly five latest messages')

    exit_button:click()
    assert_equal(exit_overlay.visible, true, path .. ' exit button opens confirmation')
    assert_equal(exit_count, 0, path .. ' opening confirmation must not exit')
    exit_cancel_button:click()
    assert_equal(exit_overlay.visible, false, path .. ' cancel closes exit confirmation')
    assert_equal(exit_count, 0, path .. ' cancel must not exit')

    exit_button:click()
    exit_confirm_button:click()
    assert_equal(exit_overlay.visible, false, path .. ' confirm closes exit confirmation')
    assert_equal(exit_count, 1, path .. ' exit button invokes controlled exit')

    local buttons = collect_match_buttons(root)
    assert_equal(#buttons, 1, path .. ' must create exactly one match button')
    local button = buttons[1]

    assert_equal(button.width, 174, path .. ' match button uses normal width')
    assert_equal(button.status_images['常态'], 134217733, path .. ' uses Scheme B normal button texture')
    assert_equal(button.status_images['悬浮'], 134217734, path .. ' uses Scheme B hover button texture')
    assert_equal(button.status_images['按下'], 134217735, path .. ' uses Scheme B pressed button texture')
    assert_equal(button.status_images['禁用'], 134217736, path .. ' uses Scheme B disabled button texture')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.private_button.status_images['常态'], 134217737,
        path .. ' uses Scheme B primary button texture')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.exit_button.status_images['常态'], 134217741,
        path .. ' uses Scheme B danger button texture')
    assert_equal(button.text, '开始匹配', path .. ' solo idle label')
    assert_equal(button.enabled, true, path .. ' solo idle enabled')
    button:click()
    assert_equal(start_count, 1, path .. ' solo click starts matching')
    assert_equal(
        start_match_params.level_id,
        '50377054694119407947881484918402159964',
        path .. ' match target level')
    assert_equal(start_match_params.game_mode, 1002, path .. ' match target mode')
    assert_equal(start_match_params.score, 1000, path .. ' match score')

    BOB.team_info = {
        captain = 2002,
        members = {
            { aid = 1001, name = '队员', state = '空闲' },
            { aid = 2002, name = '队长', state = '空闲' },
        },
    }
    refresh_callback()
    assert_equal(button.text, '开始匹配', path .. ' member idle label')
    assert_equal(button.enabled, false, path .. ' member cannot start matching')
    assert_equal(private_button.enabled, false, path .. ' member cannot start a team private dungeon')
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 按钮不可用',
        'action=局内私人副本',
        'reason=只有队长可以发起局内私人副本',
    }, path .. ' logs non-captain private dungeon restriction')
    button:click()
    assert_equal(start_count, 1, path .. ' disabled member click is ignored')

    BOB.team_info.captain = BOB.aid
    refresh_callback()
    assert_equal(button.enabled, true, path .. ' captain can start matching')
    assert_equal(private_button.enabled, true, path .. ' captain can start a team private dungeon')
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 按钮可用',
        'action=局内私人副本',
        'code=enabled',
        'reason=条件已满足',
    }, path .. ' logs team private dungeon availability')
    private_button:click()
    assert_equal(private_dungeon_count, 4, path .. ' captain private dungeon sends a request')
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 请求已受理',
        'action=局内私人副本',
        'route=team_bob',
        'selected=1',
    }, path .. ' logs team private dungeon acceptance')

    state.matching = true
    refresh_callback()
    assert_equal(button.text, '取消匹配', path .. ' matching label')
    assert_equal(button.enabled, true, path .. ' captain can cancel matching')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.expedition_phase_text,
        nil,
        path .. ' omits the expedition phase text')
    assert_log_contains(log_entries, 'info', {
        '[LobbyTestUI] 按钮不可用',
        'action=局内私人副本',
        'reason=队伍正在匹配，不能发起局内私人副本',
    }, path .. ' logs matching private dungeon restriction')
    button:click()
    assert_equal(cancel_count, 1, path .. ' matching click cancels matching')

    BOB.team_info.captain = 2002
    refresh_callback()
    assert_equal(button.enabled, false, path .. ' member cannot cancel team matching')

    state.matching = false
    state.launching = true
    BOB.team_info.captain = BOB.aid
    refresh_callback()
    assert_equal(button.text, '启动中', path .. ' launching label')
    assert_equal(button.enabled, false, path .. ' launching button disabled')

    state.launching = false
    state.ready = false
    BOB.team_info = nil
    refresh_callback()
    assert_equal(button.text, '开始匹配', path .. ' disconnected label')
    assert_equal(button.enabled, false, path .. ' disconnected button disabled')
end

run_case('maps/EntryMap/script/test_ui.lua')
run_case('maps/MapName001/script/test_ui.lua')

print('match_button_state_test: PASS')
