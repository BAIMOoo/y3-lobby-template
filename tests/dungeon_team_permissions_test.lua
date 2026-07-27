local classes = {}

function Class(name)
    local class = {}
    classes[name] = class
    return class
end

package.preload['pub.runtime_token'] = function()
    return {}
end

log = {
    info = function()
    end,
    debug = function()
    end,
    warn = function()
    end,
    error = function(err)
        error(err)
    end,
}

GameAPI = {}

local switched_level
local requested_lobby
local requested_private_join
local exit_game_count = 0
local event_handlers = {}
local current_level = '81ad7554-7e6b-11f1-8f5c-c78cd393ba6e'
local current_mode = 1001
local local_player = {
    handle = {
        request_create_private_dungeon = function(_, level_id, game_mode, max_player)
            requested_lobby = {
                level_id = level_id,
                game_mode = game_mode,
                max_player = max_player,
            }
        end,
        request_join_private_dungeon = function(_, token)
            requested_private_join = token
        end,
    },
    get_name = function()
        return '测试玩家'
    end,
    exit_game = function()
        exit_game_count = exit_game_count + 1
    end,
}
y3 = {
    game = {
        event = function(_, event_name, ...)
            local args = { ... }
            event_handlers[event_name] = args[#args]
            return {}
        end,
        switch_level = function(level_id)
            switched_level = level_id
        end,
        get_level = function()
            return current_level
        end,
        get_current_game_mode = function()
            return current_mode
        end,
    },
    player = {
        with_local = function(callback)
            callback(local_player)
        end,
    },
}

GameAPI.get_dungeon_info = function()
    return {
        game_mode = current_mode,
        space_id = 'space/token+1=',
    }
end

IsValid = function()
    return true
end

Delete = function()
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function run_case(path)
    local is_captain = false
    local is_matching = false
    local private_request
    local changed_captain
    local kicked_member
    local dismissed = 0
    local cancelled = 0
    local exit_cleanup_count = 0
    local exit_cleanup_done
    event_handlers = {}

    BOB = {
        client = {},
        aid = 1001,
        team_info = {
            team_id = 101659,
            captain = 2002,
            members = {
                { aid = 1001 },
                { aid = 2002 },
            },
        },
        is_valid = function()
            return true
        end,
        is_launching = function()
            return false
        end,
        is_matching = function()
            return is_matching
        end,
        is_in_team = function(self)
            return self.team_info ~= nil
        end,
        is_captain = function()
            return is_captain
        end,
        get_player_count = function()
            return 2, 8
        end,
        refresh_player_info = function(_, callback)
            callback({}, nil)
        end,
        start_privat_dungeon_game = function(_, dungeon_info, players)
            private_request = {
                dungeon_info = dungeon_info,
                players = players,
            }
            return true
        end,
        change_captain = function(_, aid)
            changed_captain = aid
            return true
        end,
        team_kick = function(_, aid)
            kicked_member = aid
            return true
        end,
        dismiss_team = function()
            dismissed = dismissed + 1
            return true
        end,
        cancel_match = function()
            cancelled = cancelled + 1
            return true
        end,
        cleanup_before_exit = function(_, done)
            exit_cleanup_count = exit_cleanup_count + 1
            exit_cleanup_done = done
            return true
        end,
        map_id = 'test-map',
        level_id = 'test-level',
    }

    dofile(path)

    current_level = '81ad7554-7e6b-11f1-8f5c-c78cd393ba6e'
    current_mode = 1001
    assert_equal(MatchTestIsBattleContext(), false, path .. ' lobby context')

    current_level = '25e6448f-7e73-11f1-88ae-03dc5a85955c'
    current_mode = 0
    assert_equal(MatchTestIsBattleContext(), false, path .. ' platform default lobby context')

    current_mode = 1001
    assert_equal(MatchTestIsBattleContext(), false, path .. ' explicit lobby mode context')
    assert_equal(MatchTestGetDungeonToken(), 'space/token+1=', path .. ' current dungeon token')

    requested_lobby = nil
    local created_private = MatchTestLocalPrivate()
    assert_equal(created_private, true, path .. ' joinable private dungeon request')
    assert(requested_lobby, path .. ' joinable private dungeon must send request')
    assert_equal(
        requested_lobby.level_id,
        '25e6448f-7e73-11f1-88ae-03dc5a85955c',
        path .. ' joinable private dungeon level')
    assert_equal(requested_lobby.game_mode, 1003, path .. ' joinable private dungeon mode')
    assert_equal(requested_lobby.max_player, 2, path .. ' joinable private dungeon capacity')

    requested_private_join = nil
    local empty_joined, empty_reason = MatchTestJoinPrivateDungeon('   ')
    assert_equal(empty_joined, false, path .. ' empty private token rejected')
    assert_equal(empty_reason, '请输入副本口令', path .. ' empty private token reason')
    local joined_private = MatchTestJoinPrivateDungeon('  space/token+1=  ')
    assert_equal(joined_private, true, path .. ' private dungeon join request')
    assert_equal(requested_private_join, 'space/token+1=', path .. ' private token normalized')

    requested_private_join = nil
    event_handlers['玩家-发送消息'](nil, {
        player = local_player,
        str1 = '.joinprivate chat/token+2=',
    })
    assert_equal(requested_private_join, 'chat/token+2=', path .. ' private join chat command')

    current_mode = 9999
    assert_equal(MatchTestIsBattleContext(), true, path .. ' dungeon level fallback')

    current_level = '81ad7554-7e6b-11f1-8f5c-c78cd393ba6e'
    current_mode = 1003
    assert_equal(MatchTestIsBattleContext(), true, path .. ' private mode context')
    requested_private_join = nil
    local battle_joined, battle_reason = MatchTestJoinPrivateDungeon('space/token+1=')
    assert_equal(battle_joined, false, path .. ' private join blocked in battle')
    assert_equal(battle_reason, '当前已在副本中', path .. ' private join battle reason')
    assert_equal(requested_private_join, nil, path .. ' battle join sends no request')
    current_mode = 1001

    MatchTestStartPrivate()
    assert_equal(private_request, nil, path .. ' non-captain private request')

    is_captain = true
    BOB.team_info.captain = BOB.aid
    MatchTestStartPrivate()
    assert(private_request, path .. ' captain must send private request')

    MatchTestChangeCaptain(2002)
    assert_equal(changed_captain, 2002, path .. ' change captain target')

    MatchTestKickMember(2002)
    assert_equal(kicked_member, 2002, path .. ' kick member target')

    MatchTestDismissTeam()
    assert_equal(dismissed, 1, path .. ' dismiss team request')

    is_captain = false
    BOB.team_info.captain = 2002
    changed_captain = nil
    kicked_member = nil
    MatchTestChangeCaptain(2002)
    MatchTestKickMember(2002)
    MatchTestDismissTeam()
    assert_equal(changed_captain, nil, path .. ' non-captain change request')
    assert_equal(kicked_member, nil, path .. ' non-captain kick request')
    assert_equal(dismissed, 1, path .. ' non-captain dismiss request')

    MatchTestCancel()
    assert_equal(cancelled, 0, path .. ' idle member cancel request')

    is_matching = true
    MatchTestCancel()
    assert_equal(cancelled, 0, path .. ' matching member cancel request')

    is_captain = true
    BOB.team_info.captain = BOB.aid
    MatchTestCancel()
    assert_equal(cancelled, 1, path .. ' matching captain cancel request')

    is_matching = false
    MatchTestCancel()
    assert_equal(cancelled, 1, path .. ' idle captain cancel request')

    switched_level = nil
    requested_lobby = nil
    exit_game_count = 0
    MatchTestReturnLobby()
    assert_equal(switched_level, nil, path .. ' must not switch level inside dungeon instance')
    assert(requested_lobby, path .. ' must request a new lobby instance')
    assert_equal(requested_lobby.level_id, '81ad7554-7e6b-11f1-8f5c-c78cd393ba6e', path .. ' lobby level')
    assert_equal(requested_lobby.game_mode, 1001, path .. ' lobby mode')
    assert_equal(requested_lobby.max_player, 1, path .. ' lobby max player')
    assert_equal(exit_cleanup_count, 0, path .. ' returning lobby must not clean exit state')
    event_handlers['玩家-离开游戏'](nil, { player = local_player })
    assert_equal(exit_cleanup_count, 0, path .. ' map leave event must not clean exit state')

    local exit_started = MatchTestExitGame()
    assert_equal(exit_started, true, path .. ' controlled exit starts')
    assert_equal(exit_cleanup_count, 1, path .. ' controlled exit starts one cleanup')
    assert_equal(exit_game_count, 0, path .. ' game exit waits for cleanup')

    local repeated_exit, repeated_reason = MatchTestExitGame()
    assert_equal(repeated_exit, false, path .. ' repeated controlled exit is rejected')
    assert_equal(repeated_reason, '正在退出游戏', path .. ' repeated controlled exit reason')
    assert_equal(exit_cleanup_count, 1, path .. ' repeated exit sends no cleanup')

    exit_cleanup_done(true, nil)
    assert_equal(exit_game_count, 1, path .. ' game exits after cleanup completion')
    assert_equal(BOB, nil, path .. ' controlled exit releases BOB')
end

run_case('maps/EntryMap/script/pub/pub.lua')
run_case('maps/MapName001/script/pub/pub.lua')

print('dungeon_team_permissions_test: PASS')
