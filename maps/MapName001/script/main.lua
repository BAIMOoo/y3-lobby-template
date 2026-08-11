-- 游戏启动后会自动运行此文件
-- 请到vscode插件商城下载"Y3开发助手"插件，内置详细lua开发教程及lua开发套件
-- github地址：https://github.com/y3-editor/y3-lualib.git

local GAME_PLAY_ID = 190356

local function diagnostic_value(getter)
    local ok, value = pcall(getter)
    if ok then
        return tostring(value)
    end
    return '<error:' .. tostring(value) .. '>'
end

local function player_value(player, method_name)
    if not player or type(player[method_name]) ~= 'function' then
        return '<unavailable>'
    end
    return diagnostic_value(function()
        return player[method_name](player)
    end)
end

local function player_controller_diagnostics(player)
    if not player or type(player.get_controller) ~= 'function' then
        return '<unavailable>', '<unavailable>'
    end

    local ok, controller = pcall(player.get_controller, player)
    if not ok then
        return '<error:' .. tostring(controller) .. '>', '<unavailable>'
    end

    local role_type = y3.const and y3.const.RoleType
    if not role_type or role_type.COMPUTER == nil then
        return tostring(controller), '<unavailable>'
    end
    return tostring(controller), tostring(controller == role_type.COMPUTER)
end

local function dungeon_value(field)
    if not GameAPI or type(GameAPI.get_dungeon_info) ~= 'function' then
        return '<unavailable>'
    end
    return diagnostic_value(function()
        local info = GameAPI.get_dungeon_info()
        return info and info[field]
    end)
end

local function current_mode()
    if not y3.game.get_current_game_mode then
        return '<unavailable>'
    end
    return diagnostic_value(y3.game.get_current_game_mode)
end

local function lobby_connection_status()
    if not y3.lobby or type(y3.lobby.get_connection_status) ~= 'function' then
        return '<unavailable>'
    end
    return diagnostic_value(function()
        local result = y3.lobby.get_connection_status()
        return result.result_data and result.result_data.status or result.code
    end)
end

local function log_all_players(reason)
    if not y3.player_group or type(y3.player_group.get_all_players) ~= 'function' then
        log.info(string.format(
            '[MapName001][PlayerRosterDiag] snapshot unavailable: reason=%s error=player_group_api_unavailable',
            tostring(reason)))
        return
    end

    local ok_group, group = pcall(y3.player_group.get_all_players)
    if not ok_group or not group then
        log.info(string.format(
            '[MapName001][PlayerRosterDiag] snapshot unavailable: reason=%s error=%s',
            tostring(reason),
            tostring(group)))
        return
    end

    local ok_players, players = pcall(function()
        return group:pick()
    end)
    if not ok_players or type(players) ~= 'table' then
        log.info(string.format(
            '[MapName001][PlayerRosterDiag] snapshot unavailable: reason=%s group_count=%s error=%s',
            tostring(reason),
            diagnostic_value(function()
                return group:count()
            end),
            tostring(players)))
        return
    end

    log.info(string.format(
        '[MapName001][PlayerRosterDiag] snapshot begin: reason=%s group_count=%s picked_count=%s',
        tostring(reason),
        diagnostic_value(function()
            return group:count()
        end),
        tostring(#players)))

    local computer_count = 0
    for index, player in ipairs(players) do
        local player_controller, is_computer = player_controller_diagnostics(player)
        if is_computer == 'true' then
            computer_count = computer_count + 1
        end
        log.info(string.format(
            '[MapName001][PlayerRosterDiag] player: reason=%s index=%s player=%s player_id=%s player_name=%s player_state=%s player_controller=%s is_computer=%s player_camp=%s is_alive=%s need_sync=%s',
            tostring(reason),
            tostring(index),
            tostring(player),
            player_value(player, 'get_id'),
            player_value(player, 'get_name'),
            player_value(player, 'get_state'),
            player_controller,
            is_computer,
            player_value(player, 'get_camp'),
            player_value(player, 'is_alive'),
            player_value(player, 'need_sync')))
    end

    log.info(string.format(
        '[MapName001][PlayerRosterDiag] snapshot end: reason=%s picked_count=%s computer_count=%s',
        tostring(reason),
        tostring(#players),
        tostring(computer_count)))
end

local lifecycle = rawget(_G, '__MAPNAME001_LIFECYCLE_DIAGNOSTICS')
if not lifecycle then
    lifecycle = {
        main_load_count = 0,
        next_listener_id = 0,
        game_init_count = 0,
        player_join_count = 0,
    }
    rawset(_G, '__MAPNAME001_LIFECYCLE_DIAGNOSTICS', lifecycle)
end

lifecycle.main_load_count = lifecycle.main_load_count + 1
local main_load_id = lifecycle.main_load_count

-- MapName001 是匹配、单人副本和多人副本的目标关卡，需要独立加载测试逻辑。
log.info(string.format(
    '[MapName001][EventDiag] main loaded: main_load=%s mode=%s level_id=%s game_mode=%s space_id=%s start_game_time=%s lobby_status=%s',
    tostring(main_load_id),
    current_mode(),
    dungeon_value('level_id'),
    dungeon_value('game_mode'),
    dungeon_value('space_id'),
    dungeon_value('start_game_time'),
    lobby_connection_status()))

lifecycle.next_listener_id = lifecycle.next_listener_id + 1
local game_init_listener_id = lifecycle.next_listener_id
local game_init_trigger
game_init_trigger = y3.game:event('游戏-初始化', function(trg, data)
    lifecycle.game_init_count = lifecycle.game_init_count + 1
    log.info(string.format(
        '[MapName001][EventDiag] event received: event=游戏-初始化 main_load=%s listener=%s event_seq=%s registered_trigger=%s callback_trigger=%s data=%s mode=%s level_id=%s game_mode=%s space_id=%s',
        tostring(main_load_id),
        tostring(game_init_listener_id),
        tostring(lifecycle.game_init_count),
        tostring(game_init_trigger),
        tostring(trg),
        tostring(data),
        current_mode(),
        dungeon_value('level_id'),
        dungeon_value('game_mode'),
        dungeon_value('space_id')))
    log_all_players('game-init')
end)
log.info(string.format(
    '[MapName001][EventDiag] listener registered: event=游戏-初始化 main_load=%s listener=%s trigger=%s',
    tostring(main_load_id),
    tostring(game_init_listener_id),
    tostring(game_init_trigger)))

lifecycle.next_listener_id = lifecycle.next_listener_id + 1
local player_join_listener_id = lifecycle.next_listener_id
local player_join_trigger
player_join_trigger = y3.game:event('玩家-加入游戏', function(trg, data)
    lifecycle.player_join_count = lifecycle.player_join_count + 1
    local player = data and data.player
    local player_controller, is_computer = player_controller_diagnostics(player)
    log.info(string.format(
        '[MapName001][EventDiag] event received: event=玩家-加入游戏 main_load=%s listener=%s event_seq=%s registered_trigger=%s callback_trigger=%s data=%s player=%s player_id=%s player_name=%s player_state=%s player_controller=%s is_computer=%s is_middle_join=%s mode=%s level_id=%s game_mode=%s space_id=%s',
        tostring(main_load_id),
        tostring(player_join_listener_id),
        tostring(lifecycle.player_join_count),
        tostring(player_join_trigger),
        tostring(trg),
        tostring(data),
        tostring(player),
        player_value(player, 'get_id'),
        player_value(player, 'get_name'),
        player_value(player, 'get_state'),
        player_controller,
        is_computer,
        tostring(data and data.is_middle_join),
        current_mode(),
        dungeon_value('level_id'),
        dungeon_value('game_mode'),
        dungeon_value('space_id')))
    log_all_players('player-join-' .. tostring(lifecycle.player_join_count))
    y3.player.with_local(function(local_player)
        if player ~= local_player then
            return
        end
        local result = y3.lobby.connect(GAME_PLAY_ID, true, 'pre')
        if not result.accepted then
            log.error('[MapName001] 大厅服务连接请求未发出：' .. tostring(result.reason))
        end
    end)
end)
log.info(string.format(
    '[MapName001][EventDiag] listener registered: event=玩家-加入游戏 main_load=%s listener=%s trigger=%s',
    tostring(main_load_id),
    tostring(player_join_listener_id),
    tostring(player_join_trigger)))

include 'dungeon_unit_spawn'
log.info('[MapName001] dungeon_unit_spawn loaded')
-- 目标关卡复用主关卡的 BobTestUI 根画板，按钮直接调用 y3.lobby。
include 'test_ui'
