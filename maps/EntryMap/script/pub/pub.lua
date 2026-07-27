local LEVEL_ID = '50377054694119407947881484918402159964'
local LOCAL_PRIVATE_LEVEL_ID = '25e6448f-7e73-11f1-88ae-03dc5a85955c'
local LOBBY_LEVEL_ID = '81ad7554-7e6b-11f1-8f5c-c78cd393ba6e'
-- 上传平台后必须填写真实的玩法固定ID；不能使用Bob内核兜底的10000。
local GAME_PLAY_ID_OVERRIDE = 190356
-- pre环境测试时先强制走pre匹配服；验证完成后可改成 nil 恢复自动识别。
local MATCH_ENV_OVERRIDE = 'pre'
local PLATFORM_LOBBY_GAME_MODE = 0
local LOBBY_GAME_MODE = 1001
local MATCH_GAME_MODE = 1002
local PRIVATE_GAME_MODE = 1003
local EXPECTED_MATCH_PLAYERS = 2
local DEFAULT_MAX_PLAYER = EXPECTED_MATCH_PLAYERS
-- DungeonPlayerField.version 是多人副本 RPC 的必填字段，当前协议版本固定为 2.0。
local DUNGEON_PLAYER_VERSION = '2.0'
local join_team_id
local pending_ready_actions = {}
local flush_ready_actions
local exit_in_progress = false
local runtime_token = require 'pub.runtime_token'

local function get_dungeon_info()
    if GameAPI.get_dungeon_info then
        return GameAPI.get_dungeon_info()
    end
end

local function normalize_dungeon_token(token)
    return tostring(token or ''):match('^%s*(.-)%s*$')
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

local function is_lobby_mode(mode)
    mode = math.tointeger(mode) or mode
    return mode == PLATFORM_LOBBY_GAME_MODE or mode == LOBBY_GAME_MODE
end

local function get_mode_label(mode)
    if is_lobby_mode(mode) then
        return 'LOBBY MODE / 大厅模式'
    end
    if mode == MATCH_GAME_MODE then
        return 'MATCH BATTLE / 匹配对局'
    end
    if mode == PRIVATE_GAME_MODE then
        return 'PRIVATE DUNGEON / 私人副本'
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
        return action(bob)
    end

    match_log('[MatchTest]', name, 'waiting for BOB ready...')
    pending_ready_actions[#pending_ready_actions + 1] = {
        name = name,
        action = action,
    }
    return true
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

---获取当前副本口令。私人副本的 space_id 可传给大厅玩家用于中途加入。
---@return string
function MatchTestGetDungeonToken()
    local info = get_dungeon_info()
    return info and normalize_dungeon_token(info.space_id) or ''
end

---通过副本口令加入一个仍在补人时间窗内的私人副本。
---@param token string
---@return boolean, string?
function MatchTestJoinPrivateDungeon(token)
    token = normalize_dungeon_token(token)
    if token == '' then
        return false, '请输入副本口令'
    end
    if MatchTestIsBattleContext() then
        return false, '当前已在副本中'
    end

    local requested = false
    y3.player.with_local(function(local_player)
        requested = true
        match_log('[MatchTest] request join private dungeon:',
            'player=', local_player:get_name(),
            'token=', token)
        local_player.handle:request_join_private_dungeon(token)
    end)
    if not requested then
        return false, '未找到本地玩家'
    end
    return true
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
    return run_when_ready('leave team', function(bob)
        return bob:leave_team()
    end)
end

local function parse_dungeon_join_command(message)
    message = tostring(message or '')
    local command, token = message:match('^%.(%S+)%s+(%S+)%s*$')
    if not command or not token then
        return
    end
    command = string.lower(command)
    if command ~= 'joinprivate' and command ~= 'joindungeon' then
        return
    end
    return normalize_dungeon_token(token)
end

---真正退出游戏；切图和返回大厅不得调用此入口。
function MatchTestExitGame()
    if exit_in_progress then
        return false, '正在退出游戏'
    end

    local has_local_player = false
    y3.player.with_local(function(local_player)
        has_local_player = true
        exit_in_progress = true
        local bob = BOB
        if not bob or not IsValid(bob) then
            match_log('[MatchTest] exit game: BOB unavailable, exit directly')
            local_player:exit_game()
            return
        end

        match_log('[MatchTest] exit game: cleanup started')
        bob:cleanup_before_exit(function(ok, reason)
            match_log('[MatchTest] exit game: cleanup finished:',
                'ok=', tostring(ok),
                'reason=', reason or 'nil')
            if bob == BOB and IsValid(bob) then
                Delete(bob)
                BOB = nil
            end
            local_player:exit_game()
        end)
    end)

    if not has_local_player then
        return false, '未找到本地玩家'
    end
    return true
end

local function find_team_member(bob, target_aid)
    target_aid = math.tointeger(target_aid)
    if not target_aid or not bob.team_info then
        return nil
    end
    for _, member in ipairs(bob.team_info.members or {}) do
        if math.tointeger(member.aid) == target_aid then
            return member
        end
    end
end

local function validate_team_management(bob, target_aid)
    if not bob:is_in_team() then
        return false, '当前不在队伍中'
    end
    if not bob:is_captain() then
        return false, '只有队长可以执行该操作'
    end
    if bob:is_matching() or bob:is_launching() then
        return false, '匹配或启动中不能管理队伍'
    end
    if target_aid == nil then
        return true
    end
    target_aid = math.tointeger(target_aid)
    if not target_aid then
        return false, '请输入有效的成员 AID'
    end
    if target_aid == math.tointeger(bob.aid) then
        return false, '不能对自己执行该操作'
    end
    if not find_team_member(bob, target_aid) then
        return false, '目标玩家不在当前队伍中'
    end
    return true, nil, target_aid
end

function MatchTestDismissTeam()
    return run_when_ready('dismiss team', function(bob)
        local ok, reason = validate_team_management(bob)
        if not ok then
            match_log('[MatchTest] dismiss team skipped:', reason)
            return false, reason
        end
        return bob:dismiss_team()
    end)
end

function MatchTestChangeCaptain(target_aid)
    return run_when_ready('change captain', function(bob)
        local ok, reason, numeric_aid = validate_team_management(bob, target_aid)
        if not ok then
            match_log('[MatchTest] change captain skipped:', reason)
            return false, reason
        end
        return bob:change_captain(numeric_aid)
    end)
end

function MatchTestKickMember(target_aid)
    return run_when_ready('kick member', function(bob)
        local ok, reason, numeric_aid = validate_team_management(bob, target_aid)
        if not ok then
            match_log('[MatchTest] kick member skipped:', reason)
            return false, reason
        end
        return bob:team_kick(numeric_aid)
    end)
end

function MatchTestStart(score)
    run_when_ready('start match', function(bob)
        bob:start_match(MATCH_GAME_MODE, math.tointeger(score))
    end)
end

function MatchTestCancel()
    return run_when_ready('cancel match', function(bob)
        if not bob:is_matching() then
            local reason = '当前未在匹配中'
            match_log('[MatchTest] cancel match skipped:', reason)
            return false, reason
        end
        if bob:is_in_team() and not bob:is_captain() then
            local reason = '只有队长可以取消匹配'
            match_log('[MatchTest] cancel match skipped:', reason)
            return false, reason
        end
        return bob:cancel_match()
    end)
end

function MatchTestStartPrivate()
    return run_when_ready('rpc private dungeon', function(bob)
        if not bob:is_in_team() then
            match_log('[MatchTest] F7 skipped: not in team')
            return false, '请先创建或加入队伍'
        end
        if not bob:is_captain() then
            match_log('[MatchTest] F7 skipped: only captain can start private dungeon:',
                'team=', bob.team_info and bob.team_info.team_id or 0,
                'captain=', bob.team_info and bob.team_info.captain or 0,
                'requester=', bob.aid)
            return false, '只有队长可以进入多人副本'
        end
        if bob:is_launching() then
            match_log('[MatchTest] F7 skipped: launching')
            return false, '游戏正在启动'
        end
        if bob:is_matching() then
            match_log('[MatchTest] F7 skipped: matching')
            return false, '队伍正在匹配'
        end

        local team_count, max_count = bob:get_player_count()
        if team_count < EXPECTED_MATCH_PLAYERS then
            match_log('[MatchTest] F7 skipped: not enough players for private dungeon:',
                'team=', bob.team_info and bob.team_info.team_id or 0,
                'count=', tostring(team_count) .. '/' .. tostring(max_count),
                'need=', EXPECTED_MATCH_PLAYERS,
                'mode=', PRIVATE_GAME_MODE)
            return false, '队伍人数不足'
        end

        match_log('[MatchTest] F7 update player info before private dungeon')
        bob:refresh_player_info(function(_, err)
            match_log('[MatchTest] F7 update player info ret:', 'err=', err or 'nil')
            if err then
                match_log('[MatchTest] F7 skipped: update player info failed', err)
                return
            end

            if not bob:is_in_team() or not bob:is_captain() then
                match_log('[MatchTest] F7 skipped after update: requester is no longer captain')
                return
            end

            local refreshed_team_count, refreshed_max_count = bob:get_player_count()
            if refreshed_team_count < EXPECTED_MATCH_PLAYERS then
                match_log('[MatchTest] F7 skipped after update: not enough players for private dungeon:',
                    'team=', bob.team_info and bob.team_info.team_id or 0,
                    'count=', tostring(refreshed_team_count) .. '/' .. tostring(refreshed_max_count),
                    'need=', EXPECTED_MATCH_PLAYERS,
                    'mode=', PRIVATE_GAME_MODE)
                return
            end

            local players = {}
            for _, player_info in pairs(bob.team_info.members) do
                players[#players + 1] = {
                    aid = tostring(player_info.aid),
                    version = DUNGEON_PLAYER_VERSION,
                }
            end

            local dungeon_info = {
                game_map_id = bob.map_id,
                level_id = bob.level_id,
                game_mode = PRIVATE_GAME_MODE,
            }
            match_log('[MatchTest] F7 request rpc private dungeon:',
                'team=', bob.team_info and bob.team_info.team_id or 0,
                'players=', tostring(#players) .. '/' .. tostring(refreshed_max_count),
                'need=', EXPECTED_MATCH_PLAYERS,
                'version=', DUNGEON_PLAYER_VERSION,
                'map=', dungeon_info.game_map_id,
                'level=', dungeon_info.level_id,
                'mode=', dungeon_info.game_mode)
            local sent, reason = bob:start_privat_dungeon_game(dungeon_info, players)
            if sent == false then
                match_log('[MatchTest] F7 request rejected:', reason or 'unknown')
            end
        end)
        return true
    end)
end

function MatchTestIsBattleContext()
    local mode = get_current_mode_id()
    if is_lobby_mode(mode) then
        return false
    end
    if mode == MATCH_GAME_MODE or mode == PRIVATE_GAME_MODE then
        return true
    end
    if y3.game.get_level then
        return tostring(y3.game.get_level()) ~= LOBBY_LEVEL_ID
    end
    return false
end

function MatchTestReturnLobby()
    local requested = false
    y3.player.with_local(function(local_player)
        requested = true
        match_log('[MatchTest] request lobby instance:',
            'level=', LOBBY_LEVEL_ID,
            'mode=', LOBBY_GAME_MODE,
            'max_player=', 1)
        ---@diagnostic disable-next-line: param-type-mismatch
        local_player.handle:request_create_private_dungeon(LOBBY_LEVEL_ID, LOBBY_GAME_MODE, 1)
    end)
    if not requested then
        return false, '未找到本地玩家'
    end
    return true
end

---创建一个允许另一名玩家通过口令中途加入的私人副本。
---@return boolean, string?
function MatchTestLocalPrivate()
    local requested = false
    y3.player.with_local(function(local_player)
        requested = true
        match_log('[MatchTest] F6 request joinable private dungeon:',
            'player=', local_player:get_name(),
            'level=', LOCAL_PRIVATE_LEVEL_ID,
            'mode=', PRIVATE_GAME_MODE,
            'max_player=', DEFAULT_MAX_PLAYER)
        ---@diagnostic disable-next-line: param-type-mismatch
        local_player.handle:request_create_private_dungeon(
            LOCAL_PRIVATE_LEVEL_ID,
            PRIVATE_GAME_MODE,
            DEFAULT_MAX_PLAYER)
    end)
    if not requested then
        return false, '未找到本地玩家'
    end
    return true
end

local function print_status()
    local bob = ensure_bob(false)
    local team_id = bob.team_info and bob.team_info.team_id or 0
    local team_count, max_count = bob:get_player_count()
    local text = string.format(
        '[MatchTest] state=%s ready=%s aid=%s team=%s count=%s/%s matching=%s launching=%s join_team_id=%s dungeon_token=%s',
        tostring(bob.state),
        tostring(is_bob_ready(bob)),
        tostring(bob.aid),
        tostring(team_id),
        tostring(team_count),
        tostring(max_count),
        tostring(bob:is_matching()),
        tostring(bob:is_launching()),
        tostring(join_team_id or 0),
        MatchTestGetDungeonToken()
    )
    match_log('[MatchTest] status',
        'state=', bob.state,
        'ready=', is_bob_ready(bob),
        'aid=', bob.aid,
        'team=', team_id,
        'count=', tostring(team_count) .. '/' .. tostring(max_count),
        'matching=', bob:is_matching(),
        'launching=', bob:is_launching(),
        'join_team_id=', join_team_id or 0,
        'dungeon_token=', MatchTestGetDungeonToken())
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
    match_log('[MatchTest] chat command: .team 123456 sets F10 team id; .joinnow 123456 joins team; .joinprivate TOKEN joins a running private dungeon; .f6/.f7 starts a dungeon; .mode shows current mode')
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
            local mode = get_current_mode_id()
            if mode == MATCH_GAME_MODE or mode == PRIVATE_GAME_MODE then
                CreateBobInGame()
            else
                CreateBobInLobby()
            end
        end
    end)
end)

-- 系统退出无法阻塞引擎，只做尽力清理；受控退出请使用 MatchTestExitGame。
y3.game:event('玩家-离开游戏', function(_, data)
    y3.player.with_local(function(local_player)
        if data.player ~= local_player then
            return
        end
        if not exit_in_progress then
            match_log('[MatchTest] player exit event ignored: not a controlled exit')
            return
        end
        local bob = BOB
        if bob and IsValid(bob) then
            match_log('[MatchTest] player exit event: best-effort cleanup')
            bob:cleanup_before_exit(function(ok, reason)
                match_log('[MatchTest] player exit cleanup finished:',
                    'ok=', tostring(ok),
                    'reason=', reason or 'nil')
            end, 1)
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
        local dungeon_token = parse_dungeon_join_command(data.str1)
        if dungeon_token then
            local ok, reason = MatchTestJoinPrivateDungeon(dungeon_token)
            if not ok then
                match_log('[MatchTest] join private dungeon rejected:', reason)
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
