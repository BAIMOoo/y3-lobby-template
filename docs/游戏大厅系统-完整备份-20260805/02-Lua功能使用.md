# Lua 功能使用

[返回文档入口](./README.md)

本文只说明当前项目已经提供的 Lua 对外调用接口和调用顺序，不讲解 Lua 语法或 Y3 事件基础。

## 接入前提

完整 `BOB` 路径需要满足：

- 当前地图入口已经执行 `include 'pub.init'`。
- `pub.init` 已加载 `pub.core.bob` 和 `pub.pub`。
- `pub.lua` 中的玩法 ID、环境、地图/关卡 ID、模式和人数已经替换为目标项目值。
- 平台运行时能够提供有效身份；调试模式下 `pub.runtime_token` 能生成与 `BOB.aid` 一致的令牌。

当前项目会在本地玩家加入时自动选择连接入口：大厅模式调用 `CreateBobInLobby()`，模式 `1002` 或 `1003` 调用 `CreateBobInGame()`。如果你的项目已有自己的玩家初始化入口，只保留一处调用，避免重复创建 `BOB`。

## 连接与就绪

### 创建连接

```lua
local mode = y3.game.get_current_game_mode()

if mode == 1002 or mode == 1003 then
    CreateBobInGame()
else
    CreateBobInLobby()
end
```

这两个函数都会替换旧的全局 `BOB` 实例、配置身份和网络环境并开始登录。大厅连接使用 `in_game = false`；副本连接使用 `in_game = true`。

### 等待可用状态

队伍、匹配和聊天依赖连接就绪。项目内的 `MatchTest*` 对外调用接口会把部分动作排队到“准备就绪”后执行；如果直接使用 `BOB` 公共方法，应先判断连接状态或监听事件。

```lua
local function is_lobby_ready()
    return BOB
        and IsValid(BOB)
        and BOB.client ~= nil
        and BOB:is_valid()
end

if is_lobby_ready() then
    log.info('大厅连接可用')
end
```

可以订阅下列用户可感知事件更新自己的 UI：

```lua
BOB:event_on('准备就绪', function()
    log.info('大厅连接已就绪')
end)

BOB:event_on('队伍变化', function(_, team_info)
    log.info('队伍编号：', team_info.team_id)
end)

BOB:event_on('匹配状态变化', function(_, matching)
    log.info('匹配状态：', matching)
end)
```

## 状态查询

Lua 路径可以从当前 `BOB` 实例和副本信息组装只读状态。下例不发送网络请求：

```lua
local function get_lobby_state()
    local ready = BOB
        and IsValid(BOB)
        and BOB.client ~= nil
        and BOB:is_valid()
        or false
    local member_count, member_limit = 0, 0
    if BOB and IsValid(BOB) then
        member_count, member_limit = BOB:get_player_count()
    end
    return {
        ready = ready,
        aid = BOB and BOB.aid or 0,
        team_id = BOB and BOB.team_info and BOB.team_info.team_id or 0,
        member_count = member_count,
        member_limit = member_limit,
        matching = BOB and BOB:is_matching() or false,
        launching = BOB and BOB:is_launching() or false,
        dungeon_token = MatchTestGetDungeonToken(),
    }
end
```

跨图后旧 Lua 状态不会跟随客户端进入新地图。目标地图加载完成后，应重新调用状态函数，而不是保存旧 `BOB` 或旧 `space_id` 对象引用。

## 当前对外调用接口

| 函数 | 用途 | 结果处理 |
| --- | --- | --- |
| `CreateBobInLobby()` | 重建大厅连接 | 监听“准备就绪”或错误事件 |
| `CreateBobInGame()` | 在副本上下文建立连接 | 监听“准备就绪”或错误事件 |
| `SetScore(score)` | 更新匹配分数 | 等待玩家信息刷新日志/回调 |
| `MatchTestCreateTeam()` | 创建最多两人的队伍 | 观察“队伍变化” |
| `MatchTestJoinTeam(team_id)` | 加入指定队伍 | 先刷新玩家信息，再观察队伍状态 |
| `MatchTestLeaveTeam()` | 离开队伍 | 返回是否已受理，并观察“离开队伍” |
| `MatchTestDismissTeam()` | 队长解散队伍 | 失败时返回原因 |
| `MatchTestChangeCaptain(aid)` | 转移队长 | 仅队长可用，目标必须在队伍中 |
| `MatchTestKickMember(aid)` | 移出成员 | 仅队长可用，不能选择自己 |
| `MatchTestStart(score)` | 开始模式 `1002` 匹配 | 观察“匹配状态变化” |
| `MatchTestCancel()` | 取消匹配 | 非队长不能取消组队匹配 |
| `MatchTestLocalPrivate()` | 创建可通过口令加入的私人副本 | 平台受理后跨图 |
| `MatchTestStartPrivate()` | 当前队伍启动多人私人副本 | 队长、人数和连接必须满足 |
| `MatchTestGetDungeonToken()` | 获取当前副本 `space_id` | 同步返回字符串，空串表示无口令 |
| `MatchTestJoinPrivateDungeon(token)` | 通过口令加入私人副本 | 返回 `boolean, reason?` |
| `MatchTestReturnLobby()` | 创建大厅实例并返回 | 平台受理后跨图 |
| `MatchTestExitGame()` | 清理服务状态并退出 | 返回 `boolean, reason?` |
| `MatchTestIsBattleContext()` | 判断当前是否是副本上下文 | 同步返回布尔值 |

这些函数名带有 `MatchTest`，但它们是当前项目已经接好依赖和约束的 Lua 对外调用接口。迁移时可以保留名称，也可以在目标项目外包一层业务命名；不要绕过对外调用接口直接拼装内部网络请求。

## 队伍流程

### 创建队伍

```lua
MatchTestCreateTeam()
```

连接未就绪时动作会排队。已经在队伍中时不会重复创建。

### 加入队伍

```lua
local team_id = 123456
MatchTestJoinTeam(team_id)
```

队伍编号必须是有效整数。匹配或启动过程中不要切换队伍。

### 管理队伍

```lua
local target_aid = 10001

local changed, change_reason = MatchTestChangeCaptain(target_aid)
if changed == false then
    log.warn(change_reason)
end

local kicked, kick_reason = MatchTestKickMember(target_aid)
if kicked == false then
    log.warn(kick_reason)
end
```

转移队长、移出成员和解散队伍只允许当前队长执行。匹配或游戏启动期间，队伍管理会被拒绝。

```lua
local dismissed, reason = MatchTestDismissTeam()
if dismissed == false then
    log.warn(reason)
end
```

普通成员离队使用：

```lua
local left, reason = MatchTestLeaveTeam()
if left == false then
    log.warn(reason)
end
```

## 匹配流程

### 开始匹配

```lua
SetScore(1000)
MatchTestStart(1000)
```

当前对外调用接口固定匹配到模式 `1002`。单人玩家可以直接开始；组队时由队长发起。`BOB:can_match()` 会检查连接、队伍、匹配和启动状态。

不要在匹配成功到跨图完成之间再次开放“开始匹配”按钮。此时第二次请求可能把玩家从第一场对局拉向另一场对局。

### 取消匹配

```lua
local cancelled, reason = MatchTestCancel()
if cancelled == false then
    log.warn(reason)
end
```

未在匹配中会被拒绝；组队匹配只能由队长取消。

## 聊天流程

聊天直接使用 `BOB` 公共方法，并通过回调取得请求结果。

```lua
if BOB and IsValid(BOB) and BOB:is_valid() then
    BOB:send_world_chat('世界频道消息', function(_, error_message)
        if error_message then
            log.warn('世界消息发送失败：', error_message)
        end
    end)
end
```

队伍聊天要求玩家在队伍中：

```lua
if BOB and IsValid(BOB) and BOB:is_in_team() then
    BOB:send_chat('队伍频道消息', function(_, error_message)
        if error_message then
            log.warn('队伍消息发送失败：', error_message)
        end
    end)
end
```

收到和成功发送的消息会进入 `BOB.message_history`。正式 UI 可以监听项目的聊天通知或读取这份最近记录；不要自行连接聊天服务。

## 私人副本流程

### 创建可中途加入的私人副本

```lua
local sent, reason = MatchTestLocalPrivate()
if sent == false then
    log.warn(reason)
end
```

当前项目按模式 `1003`、容量 2 创建私人副本，以便另一名玩家通过口令加入。平台受理创建请求后会跨图；Lua 当前无法在跨图过程中持续追踪请求。

### 获取并分享口令

进入副本后重新读取：

```lua
local token = MatchTestGetDungeonToken()
if token == '' then
    log.warn('当前没有可用副本口令')
else
    log.info('副本口令：', token)
end
```

口令是当前副本信息中的 `space_id`。不要在创建请求发出后立刻读取旧地图中的副本信息。

### 通过口令加入

```lua
local token = '替换为实际口令'
local accepted, reason = MatchTestJoinPrivateDungeon(token)
if not accepted then
    log.warn('加入请求被拒绝：', reason)
end
```

客户端必须仍在大厅上下文。补人时间已结束、房间已满或口令无效时，平台会拒绝；Lua 不会绕过这些限制。

### 启动多人私人副本

```lua
local accepted, reason = MatchTestStartPrivate()
if accepted == false then
    log.warn(reason)
end
```

该流程不同于引擎私人副本：它依赖完整 `BOB`、当前队伍、队长权限、足够人数和玩家信息刷新。每个 `DungeonPlayerField` 都必须包含字符串 `aid` 和 `version`；当前协议版本示例为 `"2.0"`。

## 返回大厅与退出

### 返回大厅

```lua
local accepted, reason = MatchTestReturnLobby()
if accepted == false then
    log.warn(reason)
end
```

返回大厅是创建大厅实例并跨图，不会执行完整退出清理。进入大厅后重新建立连接并查询状态。

### 受控退出

```lua
local accepted, reason = MatchTestExitGame()
if not accepted then
    log.warn(reason)
end
```

完整 `BOB` 路径必须优先使用这个入口。它会依次尝试取消匹配、离队、删除服务端玩家状态、关闭客户端，再退出游戏。不要直接用返回大厅代替退出，也不要期望“玩家-离开游戏”事件能阻塞引擎等待清理。

## 正式 UI 接线

将按钮的可用状态与业务状态绑定：

| 控件 | 启用条件 | 调用 |
| --- | --- | --- |
| 创建/加入队伍 | 连接就绪，未在匹配/启动中 | 队伍对外调用接口 |
| 开始匹配 | 连接就绪，`BOB:can_match()` 为真 | `MatchTestStart` |
| 取消匹配 | `BOB:is_matching()` 为真，组队时是队长 | `MatchTestCancel` |
| 队伍聊天 | 连接就绪且 `BOB:is_in_team()` | `BOB:send_chat` |
| 世界聊天 | 连接就绪 | `BOB:send_world_chat` |
| 多人私人副本 | 在队伍中、是队长、人数足够、未匹配/启动 | `MatchTestStartPrivate` |
| 口令加入 | 在大厅、口令非空 | `MatchTestJoinPrivateDungeon` |
| 返回大厅 | 当前在副本上下文 | `MatchTestReturnLobby` |
| 退出 | 未在执行另一退出流程 | `MatchTestExitGame` |

测试 UI 只是这些接线的现成样例，不是正式 UI 美术方案。

## 常见失败处理

| 现象 | 首先检查 |
| --- | --- |
| 动作一直没有执行 | 是否收到“准备就绪”；身份、玩法 ID 和匹配环境是否正确 |
| 创建/加入队伍失败 | 是否已在队伍；是否处于匹配/启动状态；队伍编号是否有效 |
| 不能管理成员 | 当前玩家是否是队长；目标 AID 是否属于当前队伍 |
| 不能开始匹配 | `BOB:can_match()` 的原因、队伍状态和目标模式配置 |
| 队伍聊天失败 | 当前是否在队伍中，连接是否有效 |
| 多人私人副本失败 | 队长、人数、`version`、地图/关卡 ID 和平台身份 |
| 口令加入失败 | 是否在大厅、口令是否有效、补人时间和容量 |
| 跨图后状态仍是旧值 | 是否在目标地图重新加载入口并重新查询 |

完整验证步骤见 [验证与故障排查](./06-验证与故障排查.md)。
