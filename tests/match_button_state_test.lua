local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
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
    function ui:set_btn_status_image() end
    function ui:set_image() end
    function ui:set_image_color() end
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

local function run_case(path)
    local join_callback
    local refresh_callback
    local start_count = 0
    local cancel_count = 0
    local exit_count = 0
    local return_count = 0
    local dungeon_join_count = 0
    local dungeon_join_token
    local copied_role
    local copied_ui_handle
    local team_chat_message
    local world_chat_message
    local throw_team_chat = false
    local current_mode = 1001
    local dungeon_token = ''
    local root = new_ui('根节点')
    local game_hud = new_ui('根节点')
    local player = {
        handle = 'player-handle',
        get_name = function() return '测试玩家' end,
        get_id = function() return 1 end,
    }

    log = {
        info = function() end,
        error = function(message) error(message) end,
    }
    GameAPI = {
        api_get_current_game_mode = function() return current_mode end,
        copy_ui_text_to_clipboard = function(role, ui_handle)
            copied_role = role
            copied_ui_handle = ui_handle
        end,
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
                refresh_callback = callback
                return { remove = function() end }
            end,
        },
    }
    IsValid = function() return true end
    MatchTestIsBattleContext = function() return current_mode ~= 1001 end
    MatchTestReturnLobby = function()
        return_count = return_count + 1
        return true
    end
    MatchTestExitGame = function()
        exit_count = exit_count + 1
        return true
    end
    MatchTestSetJoinTeamId = function() return true end
    MatchTestJoinTeam = function() return true end
    MatchTestCreateTeam = function() return true end
    MatchTestLeaveTeam = function() return true end
    MatchTestStart = function()
        start_count = start_count + 1
        return true
    end
    MatchTestCancel = function()
        cancel_count = cancel_count + 1
        return true
    end
    MatchTestLocalPrivate = function() return true end
    MatchTestStartPrivate = function() return true end
    MatchTestGetDungeonToken = function() return dungeon_token end
    MatchTestJoinPrivateDungeon = function(token)
        dungeon_join_count = dungeon_join_count + 1
        dungeon_join_token = token
        return true
    end
    MatchTestDismissTeam = function() return true end
    MatchTestChangeCaptain = function() return true end
    MatchTestKickMember = function() return true end

    local state = {
        ready = true,
        matching = false,
        launching = false,
    }
    BOB = {
        aid = 1001,
        client = {},
        state = 'connected',
        team_info = nil,
        message_history = {},
        is_valid = function() return state.ready end,
        is_matching = function() return state.matching end,
        is_launching = function() return state.launching end,
        is_in_team = function(self) return self.team_info ~= nil end,
        is_captain = function(self)
            return self.team_info ~= nil and self.team_info.captain == self.aid
        end,
        can_match = function(self)
            if self.team_info and not self:is_captain() then return false, '不是队长' end
            if state.matching then return false, '正在匹配' end
            if state.launching then return false, '正在启动' end
            if not state.ready then return false, '失去连接' end
            return true
        end,
        get_player_count = function(self)
            return self.team_info and #self.team_info.members or 1, 4
        end,
        format_message = function(_, item) return item.message end,
        send_chat = function(_, message)
            if throw_team_chat then
                error('模拟聊天发送异常')
            end
            team_chat_message = message
            return true
        end,
        send_world_chat = function(_, message)
            world_chat_message = message
            return true
        end,
    }

    _G.__BOB_TEST_UI_RUNTIME = nil
    dofile(path)
    assert(join_callback, path .. ' must bind player join event')
    join_callback(nil, { player = player })
    assert(refresh_callback, path .. ' must create refresh timer')

    local exit_button = assert(_G.__BOB_TEST_UI_RUNTIME.exit_button, path .. ' must create exit button')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.full_panel.z_order,
        -1000,
        path .. ' lobby control panel stays below platform dialogs')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.full_panel.width, 1920, path .. ' lobby uses full design width')
    assert_equal(_G.__BOB_TEST_UI_RUNTIME.full_panel.height, 1080, path .. ' lobby uses full design height')
    assert_equal(game_hud.visible, true, path .. ' default HUD remains visible in lobby')
    assert_equal(exit_button.width, 150, path .. ' exit button width')
    assert_equal(exit_button.height, 48, path .. ' exit button height')
    assert_equal(exit_button.relative_parent_pos['顶部'], 24, path .. ' exit button top safe margin')
    assert_equal(exit_button.relative_parent_pos['右侧'], 240, path .. ' exit button avoids debug overlay')
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
        '加入请求已发送；需在开局120秒内且房间未满',
        path .. ' dungeon join request feedback')

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
    assert_equal(lobby_chat_panel.x, 1196, path .. ' lobby chat stays on the right edge')
    assert_equal(battle_panel.x, 24, path .. ' battle chat stays on the left edge')
    assert_equal(battle_panel.y, 24, path .. ' battle chat keeps bottom safe margin')

    current_mode = 1003
    dungeon_token = 'space/token+1='
    BOB.team_info = {
        captain = BOB.aid,
        members = { { aid = BOB.aid, name = '测试玩家', state = '游戏中' } },
    }
    refresh_callback()
    assert_equal(battle_panel.visible, true, path .. ' battle chat visible in dungeon')
    assert_equal(game_hud.visible, false, path .. ' default HUD hidden in dungeon')
    assert_equal(battle_token_text.text, dungeon_token, path .. ' battle token text')
    battle_copy_button:click()
    assert_equal(copied_role, player.handle, path .. ' clipboard role handle')
    assert_equal(copied_ui_handle, battle_token_text.handle, path .. ' clipboard text handle')
    _G.__BOB_TEST_UI_RUNTIME.return_button:click()
    assert_equal(return_count, 1, path .. ' return button request count')
    assert_equal(
        _G.__BOB_TEST_UI_RUNTIME.battle_notice_text.text,
        '返回初始关卡：请求已发送',
        path .. ' return button feedback stays visible in battle')

    local battle_chat_input = assert(
        _G.__BOB_TEST_UI_RUNTIME.battle_chat_input,
        path .. ' must create battle chat input')
    battle_chat_input:set_text('队伍消息')
    _G.__BOB_TEST_UI_RUNTIME.battle_team_button:click()
    assert_equal(team_chat_message, '队伍消息', path .. ' battle team chat message')
    assert_equal(battle_chat_input:get_input_field_content(), '', path .. ' battle team input clears')
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
    throw_team_chat = false

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
    assert_equal(button.text, '开始匹配', path .. ' solo idle label')
    assert_equal(button.enabled, true, path .. ' solo idle enabled')
    button:click()
    assert_equal(start_count, 1, path .. ' solo click starts matching')

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
    button:click()
    assert_equal(start_count, 1, path .. ' disabled member click is ignored')

    BOB.team_info.captain = BOB.aid
    refresh_callback()
    assert_equal(button.enabled, true, path .. ' captain can start matching')

    state.matching = true
    refresh_callback()
    assert_equal(button.text, '取消匹配', path .. ' matching label')
    assert_equal(button.enabled, true, path .. ' captain can cancel matching')
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

run_case('maps/EntryMap/script/pub/test_ui.lua')
run_case('maps/MapName001/script/pub/test_ui.lua')

print('match_button_state_test: PASS')
