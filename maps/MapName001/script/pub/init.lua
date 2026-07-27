log.info('[MapName001][pub.init] loading pub.core.bob')
include 'pub.core.bob'
log.info('[MapName001][pub.init] loading pub.pub')
include 'pub.pub'
log.info('[MapName001][pub.init] loading pub.test_ui')
include 'pub.test_ui'
log.info('[MapName001][pub.init] all modules loaded')

if y3.game.is_debug_mode() then
    ConnectVSCode()
end
