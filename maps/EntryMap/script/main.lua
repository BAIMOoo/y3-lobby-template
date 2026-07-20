-- 游戏启动后会自动运行此文件

--在开发模式下，将日志打印到游戏中
y3.config.log.toGame = true
y3.config.log.level  = 'debug'

y3.game:event('游戏-初始化', function (trg, data)
    print('Hello, Y3!')
end)


include 'pub.init'
