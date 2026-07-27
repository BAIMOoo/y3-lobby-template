local UNIT_KEY = 134273733
local PLAYER_SPACING = 200

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

local runtime = rawget(_G, '__MAPNAME001_DUNGEON_UNIT_SPAWN_DIAGNOSTICS')
if not runtime then
    runtime = {
        module_load_count = 0,
        next_listener_id = 0,
        callback_count = 0,
        player_callback_counts = {},
        spawned_player_units = {},
    }
    rawset(_G, '__MAPNAME001_DUNGEON_UNIT_SPAWN_DIAGNOSTICS', runtime)
end
runtime.spawned_player_units = runtime.spawned_player_units or {}

runtime.module_load_count = runtime.module_load_count + 1
runtime.next_listener_id = runtime.next_listener_id + 1
local module_load_id = runtime.module_load_count
local listener_id = runtime.next_listener_id
local join_trigger

log.info(string.format(
    '[MapName001][DungeonUnitSpawnDiag] module loaded: module_load=%s listener=%s callback_total=%s',
    tostring(module_load_id),
    tostring(listener_id),
    tostring(runtime.callback_count)))

join_trigger = y3.game:event('玩家-加入游戏', function(trg, data)
    local player = data.player
    local player_id = player:get_id()
    local player_key = tostring(player_id)
    local player_controller, is_computer = player_controller_diagnostics(player)
    runtime.callback_count = runtime.callback_count + 1
    runtime.player_callback_counts[player_key] = (runtime.player_callback_counts[player_key] or 0) + 1

    log.info(string.format(
        '[MapName001][DungeonUnitSpawnDiag] callback received: module_load=%s listener=%s callback_seq=%s player_callback_seq=%s registered_trigger=%s callback_trigger=%s data=%s player=%s player_id=%s player_name=%s player_state=%s player_controller=%s is_computer=%s is_middle_join=%s level_id=%s game_mode=%s space_id=%s start_game_time=%s',
        tostring(module_load_id),
        tostring(listener_id),
        tostring(runtime.callback_count),
        tostring(runtime.player_callback_counts[player_key]),
        tostring(join_trigger),
        tostring(trg),
        tostring(data),
        tostring(player),
        tostring(player_id),
        player_value(player, 'get_name'),
        player_value(player, 'get_state'),
        player_controller,
        is_computer,
        tostring(data.is_middle_join),
        dungeon_value('level_id'),
        dungeon_value('game_mode'),
        dungeon_value('space_id'),
        dungeon_value('start_game_time')))

    local existing_unit = runtime.spawned_player_units[player_key]
    if existing_unit then
        log.info(string.format(
            '[MapName001][DungeonUnitSpawn] skipped duplicate join event: module_load=%s listener=%s callback_seq=%s player_callback_seq=%s player=%s player_controller=%s is_computer=%s is_middle_join=%s existing_unit=%s',
            tostring(module_load_id),
            tostring(listener_id),
            tostring(runtime.callback_count),
            tostring(runtime.player_callback_counts[player_key]),
            tostring(player_id),
            player_controller,
            is_computer,
            tostring(data.is_middle_join),
            tostring(existing_unit)))
        return
    end

    local spawn_x = (player_id - 1) * PLAYER_SPACING
    local spawn_point = y3.point.create(spawn_x, 0)
    local unit = player:create_unit(UNIT_KEY, spawn_point, 0)
    if unit then
        runtime.spawned_player_units[player_key] = unit
    end

    log.info(string.format(
        '[MapName001][DungeonUnitSpawn] created unit: module_load=%s listener=%s callback_seq=%s player_callback_seq=%s player=%s player_controller=%s is_computer=%s unit_key=%s position=(%s, 0) unit=%s',
        tostring(module_load_id),
        tostring(listener_id),
        tostring(runtime.callback_count),
        tostring(runtime.player_callback_counts[player_key]),
        tostring(player_id),
        player_controller,
        is_computer,
        tostring(UNIT_KEY),
        tostring(spawn_x),
        tostring(unit)))
end)

log.info(string.format(
    '[MapName001][DungeonUnitSpawnDiag] listener registered: module_load=%s listener=%s trigger=%s',
    tostring(module_load_id),
    tostring(listener_id),
    tostring(join_trigger)))
