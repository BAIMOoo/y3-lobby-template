-- 游戏启动后会自动运行此文件

--在开发模式下，将日志打印到游戏中
y3.config.log.toGame = true
y3.config.log.level  = 'debug'

local GAME_PLAY_ID = 10190356

y3.game:event('游戏-初始化', function (trg, data)
    print('Hello, Y3!')
end)

y3.game:event('玩家-加入游戏', function ()
    local result = y3.lobby.connect(GAME_PLAY_ID)
    if not result.accepted then
        print('大厅服务连接请求未发出：' .. tostring(result.reason))
    end
end)
