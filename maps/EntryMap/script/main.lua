-- 游戏启动后会自动运行此文件

-- 测试界面会显示操作结果；详细日志保留在日志文件中，避免遮挡控件。
y3.config.log.toGame = false
y3.config.log.level  = 'debug'

local GAME_PLAY_ID = 190356

y3.game:event('游戏-初始化', function (trg, data)
    print('Hello, Y3!')
end)

y3.game:event('玩家-加入游戏', function (_, data)
    y3.player.with_local(function(local_player)
        if not data or data.player ~= local_player then
            return
        end
        local result = y3.lobby.connect(GAME_PLAY_ID, false, 'prod')
        if not result.accepted then
            print('大厅服务连接请求未发出：' .. tostring(result.reason))
        end
    end)
end)

-- 测试界面只复用旧 UI 布局，所有操作直接调用 y3.lobby。
include 'test_ui'
