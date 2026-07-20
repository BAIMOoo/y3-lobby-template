local LEVEL_ID = '50377054694119407947881484918402159964'
local LOCAL_PRIVATE_LEVEL_ID = '25e6448f-7e73-11f1-88ae-03dc5a85955c'
-- 上传平台后必须填写真实的玩法固定ID；不能使用Bob内核兜底的10000。
local GAME_PLAY_ID_OVERRIDE = 190356
-- pre环境测试时先强制走pre匹配服；验证完成后可改成 nil 恢复自动识别。
local MATCH_ENV_OVERRIDE = 'pre'
local DEFAULT_GAME_MODE = 1002
local EXPECTED_MATCH_PLAYERS = 2
local DEFAULT_MAX_PLAYER = EXPECTED_MATCH_PLAYERS
local join_team_id
local pending_ready_actions = {}
local flush_ready_actions
local runtime_token = require 'pub.runtime_token'

local function get_dungeon_info()
    if GameAPI.get_dungeon_info then
        return GameAPI.get_dungeon_info()
    end
end

local function safe_inspect(value)
    local ok, text = pcall(y3.inspect, value)
    if ok then
        return text
    end
    return tostring(value)
end

local function match_log(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[i] = tostring(select(i, ...))
    end
    local line = table.concat(parts, '\t')
    log.info(line)
end

local function get_current_mode_id()
    local mode = nil
    if y3.game.get_current_game_mode then
        mode = y3.game.get_current_game_mode()
    end
    if (not mode or tostring(mode) == '0') and y3.game.get_current_game_mode_new then
        mode = y3.game.get_current_game_mode_new()
    end
    local info = get_dungeon_info()
    if (not mode or tostring(mode) == '0') and info then
        mode = info.game_mode
    end
    return math.tointeger(mode) or mode or 0
end

local function get_mode_label(mode)
    mode = math.tointeger(mode) or mode
    if mode == 1001 then
        return 'LOBBY MODE / 大厅模式'
    end
    if mode == 1002 then
        return 'BATTLE MODE / 对局模式'
    end
    return 'UNKNOWN MODE / 未知模式'
end

local function show_mode_banner(local_player, reason)
    local mode = get_current_mode_id()
    local label = get_mode_label(mode)
    local text = string.format('[MatchTest] >>> %s <<< mode=%s reason=%s', label, tostring(mode), tostring(reason or ''))
    match_log(text)
    pcall(function()
        local_player:display_message(text, false)
    end)
    y3.ctimer.loop_count(1, 5, function(timer, count)
        local current_mode = get_current_mode_id()
        match_log('[MatchTest] mode banner', count, get_mode_label(current_mode), 'mode=', current_mode)
    end)
end

local function log_match_boot_info()
    local info = get_dungeon_info()
    log.debug('[MatchTest] dungeon_info:', safe_inspect(info))
    log.debug('[MatchTest] override game_play_id:', GAME_PLAY_ID_OVERRIDE or 'nil')
    log.debug('[MatchTest] configured level_id:', LEVEL_ID)
    log.debug('[MatchTest] expected match players:', EXPECTED_MATCH_PLAYERS)
    log.debug('[MatchTest] current game mode:', y3.game.get_current_game_mode_new and y3.game.get_current_game_mode_new() or 'nil')

    y3.player.with_local(function(local_player)
        local ok, store_params = pcall(function()
            return local_player.handle:api_get_role_store_params()
        end)
        if not ok then
            log.warn('[MatchTest] api_get_role_store_params failed:', store_params)
            return
        end
        log.debug('[MatchTest] store_params length:', store_params and #store_params or 0)
        if store_params and store_params ~= '' then
            local decode_ok, decoded = pcall(y3.json.decode, store_params)
            if decode_ok and decoded then
                local sign = decoded.sign
                decoded.sign = sign and (string.sub(sign, 1, 12) .. '... len=' .. tostring(#sign)) or sign
                log.debug('[MatchTest] store_params decoded:', safe_inspect(decoded))
            else
                log.warn('[MatchTest] store_params decode failed:', decoded)
            end
        else
            log.warn('[MatchTest] store_params empty')
        end
    end)

    if not y3.game.is_debug_mode(true) and (not info or not info.game_play_id) then
        log.warn('[MatchTest] platform dungeon_info.game_play_id is nil; using override only. If login_auth returns invalid login token, check platform game_play_id/token authorization.')
    end
end

local function get_env()
    if MATCH_ENV_OVERRIDE then
        return MATCH_ENV_OVERRIDE
    end
    local info = get_dungeon_info()
    return tostring(info and info.env or 'qa')
end

local function get_map_id()
    local info = get_dungeon_info()
    return tostring(info and info.map_id or '')
end

local function get_game_play_id()
    local info = get_dungeon_info()
    local id = GAME_PLAY_ID_OVERRIDE or (info and info.game_play_id)
    return tostring(id or '')
end

local function configure_network(bob)
    local env = get_env()
    bob.port = 8092
    if y3.game.is_debug_mode(true) then
        bob.ip = '42.186.215.253'
    elseif env == 'pre' then
        bob.ip = '42.186.213.132'
    elseif env == 'prod' then
        bob.ip = '223.252.200.35'
    else
        bob.ip = '42.186.215.253'
    end
    log.debug('[MatchTest] match server:', env, bob.ip, bob.port)
end

local function configure_debug_identity(bob)
    local local_player = y3.player.get_local()
    local p_id = local_player:get_id()
    bob.name = local_player:get_name()
    bob.aid = math.tointeger(tostring(y3.hash(bob.name)) .. tostring(p_id))

    local token, expires_at_or_error = runtime_token.generate(bob.aid, os.time())
    if not token then
        log.error('[MatchTest] runtime token generation failed:', expires_at_or_error)
        return false
    end

    bob.token = token
    match_log('[MatchTest] runtime token generated:',
        'aid=', bob.aid,
        'expires_at=', expires_at_or_error,
        'token_length=', #token)
    return true
end

local function create_bob(in_game)
    if BOB then
        Delete(BOB)
    end

    BOB = New 'Bob' ()
    local bob = BOB
    bob.score = bob.score > 0 and bob.score or 1000
    bob.level_id = LEVEL_ID
    bob.map_id = get_map_id()
    bob.game_play_id = get_game_play_id()
    local game_play_id_num = tonumber(bob.game_play_id)
    if not y3.game.is_debug_mode(true) and not game_play_id_num then
        log.error('[MatchTest] missing game_play_id. Set GAME_PLAY_ID_OVERRIDE in pub.lua before using platform match service.')
        return bob
    end
    bob.game_play_id_num = game_play_id_num or bob.game_play_id_num

    if y3.game.is_debug_mode(true) and not configure_debug_identity(bob) then
        return bob
    end

    configure_network(bob)
    bob:set_in_game(in_game)

    local function is_active()
        return bob == BOB and IsValid(bob)
    end

    bob:set_error_handler(function(msg, errid)
        if not is_active() then return end
        log.warn('[MatchTest] request failed:', errid, msg)
    end)

    bob:event_on('准备就绪', function()
        if not is_active() then return end
        match_log('[MatchTest] BOB ready. aid=', bob.aid, 'team=', bob.team_info and bob.team_info.team_id or 0)
        flush_ready_actions()
    end)
    bob:event_on('在线状态变化', function(_, state)
        if not is_active() then return end
        match_log('[MatchTest] online state:', state)
    end)
    bob:event_on('匹配状态变化', function(_, state)
        if not is_active() then return end
        match_log('[MatchTest] matching:', state)
    end)
    bob:event_on('启动状态变化', function(_, state)
        if not is_active() then return end
        match_log('[MatchTest] launching:', state)
    end)
    bob:event_on('队伍变化', function(_, team_info)
        if not is_active() then return end
        match_log('[MatchTest] team:', team_info.team_id, team_info.team_state, #team_info.members)
    end)
    bob:event_on('加入队伍', function()
        if not is_active() then return end
        match_log('[MatchTest] joined team:', bob.team_info and bob.team_info.team_id or 0)
    end)
    bob:event_on('离开队伍', function(_, reason)
        if not is_active() then return end
        match_log('[MatchTest] left team:', reason)
    end)

    bob:start()
    return bob
end

local function ensure_bob(in_game)
    if not BOB or not IsValid(BOB) then
        return create_bob(in_game)
    end
    return BOB
end

local function is_bob_ready(bob)
    return bob and IsValid(bob) and bob.client ~= nil and bob:is_valid()
end

local function run_when_ready(name, action)
    local bob = ensure_bob(false)
    if is_bob_ready(bob) then
        action(bob)
        return
    end

    match_log('[MatchTest]', name, 'waiting for BOB ready...')
    pending_ready_actions[#pending_ready_actions + 1] = {
        name = name,
        action = action,
    }
end

flush_ready_actions = function()
    if #pending_ready_actions == 0 then
        return
    end

    local actions = pending_ready_actions
    pending_ready_actions = {}
    for _, item in ipairs(actions) do
        match_log('[MatchTest] run pending action:', item.name)
        xpcall(function()
            item.action(BOB)
        end, log.error)
    end
end

function CreateBobInLobby()
    log_match_boot_info()
    return create_bob(false)
end

function CreateBobInGame()
    log_match_boot_info()
    return create_bob(true)
end

function SetScore(score)
    run_when_ready('set score', function(bob)
        bob:set_score(math.tointeger(score) or 1000)
    end)
end

function MatchTestCreateTeam()
    run_when_ready('create team', function(bob)
        if bob:is_in_team() then
            match_log('[MatchTest] already in team:', bob.team_info.team_id)
            return
        end
        bob:create_team(nil, DEFAULT_MAX_PLAYER)
    end)
end

function MatchTestJoinTeam(team_id)
    run_when_ready('join team', function(bob)
        local numeric_team_id = math.tointeger(team_id)
        match_log('[MatchTest] refresh before join team:', numeric_team_id)
        bob:refresh_player_info(function(_, err)
            match_log('[MatchTest] refresh before join team ret:',
                'team=', numeric_team_id,
                'err=', err or 'nil')
            if err then
                return
            end
            bob:join_team(numeric_team_id)
        end)
    end)
end

function MatchTestSetJoinTeamId(team_id)
    join_team_id = math.tointeger(team_id)
    match_log('[MatchTest] join team id set:', join_team_id or 0)
end

local function parse_team_command(message)
    message = tostring(message or '')
    local command, team_id = message:match('^%.(%S+)%s+(%d+)%s*$')
    if not command or not team_id then
        return
    end
    command = string.lower(command)
    if command ~= 'team' and command ~= 'join' and command ~= 'joinnow' then
        return
    end
    return command, math.tointeger(team_id)
end

local function parse_action_command(message)
    message = tostring(message or '')
    local command = message:match('^%.(%S+)%s*$')
    if not command then
        return
    end
    command = string.lower(command)
    if command == 'f6' or command == 'localprivate' or command == 'solo' then
        return 'f6'
    end
    if command == 'f7' or command == 'private' or command == 'rpcprivate' then
        return 'f7'
    end
    if command == 'mode' then
        return command
    end
end

function MatchTestLeaveTeam()
    run_when_ready('leave team', function(bob)
        bob:leave_team()
    end)
end

function MatchTestStart(score)
    run_when_ready('start match', function(bob)
        bob:start_match(DEFAULT_GAME_MODE, math.tointeger(score))
    end)
end

function MatchTestCancel()
    run_when_ready('cancel match', function(bob)
        bob:cancel_match()
    end)
end

function MatchTestStartPrivate()
    run_when_ready('rpc private dungeon', function(bob)
        if bob:is_launching() then
            match_log('[MatchTest] F7 skipped: launching')
            return
        end
        if bob:is_matching() then
            match_log('[MatchTest] F7 skipped: matching')
            return
        end

        local team_count, max_count = bob:get_player_count()
        if team_count < EXPECTED_MATCH_PLAYERS then
            match_log('[MatchTest] F7 skipped: not enough players for private dungeon:',
                'team=', bob.team_info and bob.team_info.team_id or 0,
                'count=', tostring(team_count) .. '/' .. tostring(max_count),
                'need=', EXPECTED_MATCH_PLAYERS,
                'mode=', DEFAULT_GAME_MODE)
            return
        end

        match_log('[MatchTest] F7 update player info before private dungeon')
        bob:refresh_player_info(function(_, err)
            match_log('[MatchTest] F7 update player info ret:', 'err=', err or 'nil')
            if err then
                match_log('[MatchTest] F7 skipped: update player info failed', err)
                return
            end

            local refreshed_team_count, refreshed_max_count = bob:get_player_count()
            if refreshed_team_count < EXPECTED_MATCH_PLAYERS then
                match_log('[MatchTest] F7 skipped after update: not enough players for private dungeon:',
                    'team=', bob.team_info and bob.team_info.team_id or 0,
                    'count=', tostring(refreshed_team_count) .. '/' .. tostring(refreshed_max_count),
                    'need=', EXPECTED_MATCH_PLAYERS,
                    'mode=', DEFAULT_GAME_MODE)
                return
            end

            local players = {}
            for _, player_info in pairs(bob.team_info.members) do
                players[#players + 1] = { aid = tostring(player_info.aid) }
            end

            local dungeon_info = {
                game_map_id = bob.map_id,
                level_id = bob.level_id,
                game_mode = DEFAULT_GAME_MODE,
            }
            match_log('[MatchTest] F7 request rpc private dungeon:',
                'team=', bob.team_info and bob.team_info.team_id or 0,
                'players=', tostring(#players) .. '/' .. tostring(refreshed_max_count),
                'need=', EXPECTED_MATCH_PLAYERS,
                'map=', dungeon_info.game_map_id,
                'level=', dungeon_info.level_id,
                'mode=', dungeon_info.game_mode)
            bob:start_privat_dungeon_game(dungeon_info, players)
        end)
    end)
end

function MatchTestLocalPrivate()
    y3.player.with_local(function(local_player)
        match_log('[MatchTest] F6 request local private dungeon:',
            'player=', local_player:get_name(),
            'level=', LOCAL_PRIVATE_LEVEL_ID,
            'mode=', DEFAULT_GAME_MODE,
            'max_player=', 1)
        ---@diagnostic disable-next-line: param-type-mismatch
        local_player.handle:request_create_private_dungeon(LOCAL_PRIVATE_LEVEL_ID, DEFAULT_GAME_MODE, 1)
    end)
end

local function print_status()
    local bob = ensure_bob(false)
    local team_id = bob.team_info and bob.team_info.team_id or 0
    local team_count, max_count = bob:get_player_count()
    local text = string.format(
        '[MatchTest] state=%s ready=%s aid=%s team=%s count=%s/%s matching=%s launching=%s join_team_id=%s',
        tostring(bob.state),
        tostring(is_bob_ready(bob)),
        tostring(bob.aid),
        tostring(team_id),
        tostring(team_count),
        tostring(max_count),
        tostring(bob:is_matching()),
        tostring(bob:is_launching()),
        tostring(join_team_id or 0)
    )
    match_log('[MatchTest] status',
        'state=', bob.state,
        'ready=', is_bob_ready(bob),
        'aid=', bob.aid,
        'team=', team_id,
        'count=', tostring(team_count) .. '/' .. tostring(max_count),
        'matching=', bob:is_matching(),
        'launching=', bob:is_launching(),
        'join_team_id=', join_team_id or 0)
    match_log(text)
end

local function bind_test_hotkeys()
    local last_local_private_at = 0

    local function trigger_local_private(source)
        local now = os.clock()
        if now - last_local_private_at < 0.5 then
            match_log('[MatchTest]', source, 'local private skipped: duplicate trigger')
            return
        end
        last_local_private_at = now
        match_log('[MatchTest]', source, 'local private dungeon')
        MatchTestLocalPrivate()
    end

    local function trigger_rpc_private(source)
        match_log('[MatchTest]', source, 'rpc private dungeon')
        MatchTestStartPrivate()
    end

    y3.game:event('键盘-按下', 'F2', function()
        match_log('[MatchTest] F2 reload lobby client')
        CreateBobInLobby()
    end)

    y3.game:event('键盘-按下', 'F3', function()
        match_log('[MatchTest] F3 create team')
        MatchTestCreateTeam()
    end)

    y3.game:event('键盘-按下', 'F4', function()
        match_log('[MatchTest] F4 start match')
        MatchTestStart(1000)
    end)

    y3.game:event('键盘-按下', 'F5', function()
        match_log('[MatchTest] F5 cancel match')
        MatchTestCancel()
    end)

    y3.game:event('本地-键盘-按下', 'F6', function()
        trigger_local_private('local F6')
    end)

    y3.game:event('键盘-按下', 'F7', function()
        trigger_rpc_private('F7')
    end)

    y3.game:event('本地-键盘-按下', 'F7', function()
        trigger_rpc_private('local F7')
    end)

    y3.game:event('键盘-按下', 'F8', function()
        match_log('[MatchTest] F8 leave team')
        MatchTestLeaveTeam()
    end)

    y3.game:event('键盘-按下', 'F9', function()
        print_status()
    end)

    y3.game:event('键盘-按下', 'F10', function()
        if join_team_id then
            match_log('[MatchTest] F10 join team:', join_team_id)
            MatchTestJoinTeam(join_team_id)
        else
            match_log('[MatchTest] F10 join skipped: call MatchTestSetJoinTeamId(team_id) first')
        end
    end)

    match_log('[MatchTest] hotkeys: F2 reload F3 create-team F4 match F5 cancel F6 local-private F7 rpc-private F8 leave F9 status F10 join-preset-team')
    match_log('[MatchTest] chat command: .team 123456 sets F10 team id; .joinnow 123456 joins immediately; .f6 runs local 1-player private; .f7 runs 2-player rpc private; .mode shows current mode')
end

function ConnectVSCode()
    y3.develop.helper.init(59846)
    y3.config.code.enable_local = true
    y3.config.code.enable_remote = true
end

y3.game:event('玩家-加入游戏', function(_, data)
    y3.player.with_local(function(local_player)
        if data.player == local_player then
            show_mode_banner(local_player, 'player-join')
            if get_current_mode_id() == 1002 then
                CreateBobInGame()
            else
                CreateBobInLobby()
            end
        end
    end)
end)

y3.game:event('玩家-发送消息', function(_, data)
    y3.player.with_local(function(local_player)
        if data.player ~= local_player then
            return
        end
        local command, team_id = parse_team_command(data.str1)
        if command then
            MatchTestSetJoinTeamId(team_id)
            if command == 'joinnow' then
                MatchTestJoinTeam(team_id)
            end
            return
        end
        local action = parse_action_command(data.str1)
        if action then
            match_log('[MatchTest] chat command:', data.str1)
            if action == 'mode' then
                show_mode_banner(local_player, 'chat-command')
            elseif action == 'f6' then
                MatchTestLocalPrivate()
            else
                MatchTestStartPrivate()
            end
        end
    end)
end)

bind_test_hotkeys()
