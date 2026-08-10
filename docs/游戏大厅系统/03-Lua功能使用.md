# Lua 功能使用

[返回文档首页](./README.md)

本文只说明 Lua 作者如何使用 `y3.lobby` 对外调用接口。迁移步骤见 [迁移](./02-迁移.md)。

## 连接

地图加载 `y3` 后，`y3.lobby` 会存在，但不会自动连接 BOB。需要主动调用：

```lua
local y3 = require 'y3'

local result = y3.lobby.connect(190356)
if not result.accepted then
    print('大厅服务连接请求未发出：' .. tostring(result.reason))
end
```

`connect(玩法ID, 是否在游戏关卡, 服务环境)` 的第一个参数是正整数玩法 ID，必填。当前示例项目使用 `190356`；迁移到自己的项目时，填写目标项目对应的玩法 ID。这个值不是调试参数，也不是 UUID 格式的 `map_id`，框架不会自动从运行环境读取。

第二个参数可选，默认为 `false`。如果当前关卡已经是目标玩法关卡，并且仍需要连接大厅服务，可传 `true`：

```lua
y3.lobby.connect(190356, true)
```

第三个参数可选，用于让特定项目覆盖上传平台后的服务环境，只接受 `'qa'`、`'pre'` 或 `'prod'`。本地调试始终优先连接 `qa`；省略第三个参数时仍按平台提供的环境自动选择，因此普通作者原有调用无需修改。例如仅让某个测试项目在平台连接 `pre`：

```lua
y3.lobby.connect(190356, false, 'pre')
```

重复调用时，框架会返回当前连接请求或当前连接状态，不会创建多个客户端。

组队、匹配、聊天、跨房合流和高级查询接口必须在连接成功后调用。未连接时会立即返回失败，常见 `code` 为 `not_connected` 或 `connection_pending`。同房分流、加入口令和获取口令不要求预先连接。

`return_lobby(params)` 和 `exit_game()` 不要求预先连接。目标玩法关卡如果只需要返回大厅或退出游戏，不需要为此调用 `connect()`；已有连接时，框架会先尽力清理大厅状态。

## 完成回调

异步接口会先返回立即结果。真正完成时，Lua 侧通过 `on_complete` 订阅：

```lua
local listener = y3.lobby.on_complete(function(payload)
    print(payload.action)
    print(payload.request_id)
    print(payload.success)
end)
```

同一个请求只会完成一次。同步失败不会再触发完成回调。

如果建立连接或其他对外调用接口的请求尚未完成，此时又调用 `return_lobby()` 或 `exit_game()`，旧请求会被取消，并且只会收到一次 `success = false`、`code = cancelled_by_terminal` 的完成结果。旧请求即使之后返回，也不会再改变结果。

返回大厅的完成结果可通过 `result_data.cleanup` 查看是否执行了清理以及失败原因。需要取消订阅时调用：

```lua
listener:remove()
```

## 状态事件

如果界面需要实时刷新，可通过 `on_event` 订阅状态变化：

```lua
local listener = y3.lobby.on_event('team_changed', function(payload)
    print(payload.event)
    print(payload.status)
end)

listener:remove()
```

也可以不传事件名，监听全部大厅状态事件：

```lua
local listener = y3.lobby.on_event(function(payload)
    print(payload.event)
end)
```

稳定事件名如下：

| 事件名 | 含义 |
| --- | --- |
| `connection_changed` | 连接状态变化 |
| `team_changed` | 队伍整体信息变化 |
| `team_joined` | 当前玩家加入队伍 |
| `team_left` | 当前玩家离开队伍 |
| `member_joined` | 队员加入 |
| `member_left` | 队员离开 |
| `matching_changed` | 匹配状态变化 |
| `launching_changed` | 进入目标关卡状态变化 |
| `message_received` | 收到聊天消息 |
| `client_update_required` | 客户端信息需要刷新 |

事件载荷包含 `event`、`source`、`status`、`code`、`reason`、`data`、`snapshot`、`sequence`。不要依赖 BOB 原始事件名或原始结构。

`data` 只包含稳定公共字段：连接事件使用 `code`、`reason`；队伍事件使用 `team`；离队事件使用 `reason`、`team`；成员事件使用 `member`；匹配和启动事件分别使用 `matching`、`launching`；聊天事件使用 `message`；更新事件使用 `required`。其中队伍、成员和消息都是框架复制后的数据，不是 BOB 内部表。

## 返回字段

立即结果字段：

| 字段 | 含义 |
| --- | --- |
| `accepted` | 请求是否已发出 |
| `action` | 操作名称 |
| `request_id` | 请求编号，用于对应后续完成结果 |
| `reason` | 失败原因或补充说明 |
| `code` | 便于程序判断的结果码 |
| `sync` | 是否为同步结果 |
| `result_data` | 同步结果数据 |

完成结果字段：

| 字段 | 含义 |
| --- | --- |
| `request_id` | 与立即结果对应 |
| `action` | 操作名称 |
| `success` | 最终是否成功 |
| `reason` | 最终失败原因或补充说明 |
| `code` | 最终结果码 |
| `result_data` | 最终结果数据 |

## 对外调用接口

| 能力 | Lua 对外调用接口 | 说明 |
| --- | --- | --- |
| 建立连接 | `y3.lobby.connect(game_play_id, in_game, endpoint_env)` | `game_play_id` 为正整数玩法 ID，必填；`in_game`、`endpoint_env` 可选，后者仅接受 `qa`、`pre`、`prod` |
| 获取连接状态 | `y3.lobby.get_connection_status()` | 同步查询当前连接状态 |
| 设置匹配分数 | `y3.lobby.set_score(score)` | `score` 为整数 |
| 创建队伍 | `y3.lobby.create_team(member_limit)` | `member_limit` 为队伍人数上限，必填 |
| 加入队伍 | `y3.lobby.join_team(team_id)` | `team_id` 为队伍编号 |
| 离开队伍 | `y3.lobby.leave_team()` | 当前在队伍中 |
| 解散队伍 | `y3.lobby.dismiss_team()` | 队长调用 |
| 转移队长 | `y3.lobby.change_captain(target_aid)` | `target_aid` 为目标玩家 AID |
| 移出队员 | `y3.lobby.kick_member(target_aid)` | 队长调用 |
| 获取队伍成员 | `y3.lobby.get_members()` | 同步返回成员数据 |
| 获取队伍成员项 | `y3.lobby.get_member(index)` | 同步按序号返回单个成员，便于 ECA/UI 逐项读取 |
| 开始匹配 | `y3.lobby.start_match(params)` | `params.level_id`、`params.game_mode` 必填；`params.score` 可选 |
| 取消匹配 | `y3.lobby.cancel_match()` | 正在匹配时调用 |
| 发送队伍聊天 | `y3.lobby.send_team_chat(message)` | 当前在队伍中 |
| 发送世界聊天 | `y3.lobby.send_world_chat(message)` | 连接成功后调用 |
| 获取聊天记录 | `y3.lobby.get_chat_history(channel)` | `channel` 可传 `nil` |
| 获取聊天消息 | `y3.lobby.get_chat_message(index, channel)` | 同步按序号和可选频道返回单条消息 |
| 同房分流 | `y3.lobby.same_room_split(params)` | `level_id`、`game_mode`、`max_player` 必填；`players` 可选 |
| 跨房合流 | `y3.lobby.cross_room_merge(params)` | `game_map_id`、`level_id`、`game_mode`、`players` 必填 |
| 加入口令 | `y3.lobby.join_by_token(token)` | 使用口令进入目标关卡 |
| 获取口令 | `y3.lobby.get_token()` | 获取当前目标关卡口令 |
| 返回大厅 | `y3.lobby.return_lobby(params)` | `level_id`、`game_mode`、`max_player` 必填；无需预先连接；已有连接时先清理 |
| 退出游戏 | `y3.lobby.exit_game()` | 无需预先连接；已有连接时先清理 |
| 获取状态快照 | `y3.lobby.request_state()` / `y3.lobby.get_state()` | 同步获取状态 |
| 获取队伍信息 | `y3.lobby.get_team_info(aid)` | 异步查询指定 AID 的队伍信息；`aid` 可选，省略时查询自己 |
| 获取玩家信息 | `y3.lobby.get_player_info(aid)` | `aid` 可选；缓存命中时同步返回，未命中时异步查询 |
| 刷新玩家信息 | `y3.lobby.refresh_player_info()` | 异步把当前玩家状态同步到大厅服务 |

## 常用流程

### 队伍与匹配

```lua
local create_result = y3.lobby.create_team(4)
if not create_result.accepted then
    print(create_result.reason)
end

y3.lobby.start_match({
    level_id = 'MATCH_LEVEL_ID',
    game_mode = 'MATCH_MODE_ID',
    score = 1000,
})
```

队伍人数上限是本次创建队伍的动态参数。最大人数、最少人数、分数分段等规则仍应放在项目 JSON 中。

### 聊天

```lua
y3.lobby.send_world_chat('世界频道消息')
y3.lobby.send_team_chat('队伍频道消息')

local history = y3.lobby.get_chat_history(nil)
if history.accepted then
    print(history.result_data)
end
```

### 同房分流

```lua
y3.lobby.same_room_split({
    level_id = 'TARGET_LEVEL_ID',
    game_mode = 'TARGET_MODE_ID',
    max_player = 4,
    players = {
        { aid = 10001 },
        { aid = 10002 },
    },
})
```

`level_id`、`game_mode`、`max_player` 是本次发给平台的动态参数。目标关卡是否允许进入、人数上限和中途加入规则仍由 `dungeon.json` 决定。同房分流不要求预先连接 BOB。

`players` 是可选目标玩家列表，每项格式为 `{ aid = 玩家AID }`；提供时仅列表内玩家切换，省略时当前房间内调用到该接口的玩家都会执行。

### 跨房合流

```lua
y3.lobby.cross_room_merge({
    game_map_id = 'TARGET_MAP_ID',
    level_id = 'TARGET_LEVEL_ID',
    game_mode = 'TARGET_MODE_ID',
    players = {
        { aid = 10001 },
        { aid = 10002 },
    },
})
```

`players` 每项只需要传 `aid`。玩家协议里的 `version` 字段由框架内部写入固定字符串 `"2.0"`，不要作为业务参数传入。

跨房合流请求完成时，`result_data` 会包含：

| 字段 | 含义 |
| --- | --- |
| `platform_requested` | 平台切换请求是否已发出 |
| `entered_target` | 是否已确认进入目标关卡；无法确认时为 `unknown` |
| `confirm_by` | 固定为 `launching_state`，表示由启动状态确认请求进度 |

### 加入口令与获取口令

```lua
local token_result = y3.lobby.get_token()
if token_result.accepted then
    y3.lobby.join_by_token(token_result.result_data.token)
end
```

`get_token()` 和 `join_by_token(token)` 不要求预先连接 BOB。`get_token()` 从当前关卡运行信息中读取口令。

### 列表单项读取

```lua
local member = y3.lobby.get_member(1)
local message = y3.lobby.get_chat_message(1, nil)
```

这两个接口用于不方便一次处理整张表的场景。序号从 `1` 开始；序号不是正整数时返回 `accepted = false`、`code = invalid_argument`，合法序号越界时返回 `accepted = true`、`result_data.exists = false`。

### 高级查询

```lua
y3.lobby.get_team_info()
y3.lobby.get_player_info()
y3.lobby.refresh_player_info()
```

这三个接口需要已连接 BOB，但返回时机不同：

- `get_team_info(aid)` 始终异步查询大厅服务；省略 `aid` 时查询当前玩家。完成结果会把队伍信息放在 `result_data.team`，并用 `result_data.has_team` 明确表示是否有队伍。
- `get_player_info(aid)` 缓存命中时同步返回；缓存未命中时才发起异步查询。完成结果会把服务端返回的玩家信息放在 `result_data.player`。
- `refresh_player_info()` 异步把当前玩家信息同步到大厅服务，并更新框架缓存；它不是从服务端拉取其他玩家信息。

异步受理结果包含 `request_id`，最终结果通过 `on_complete` 返回；同步缓存命中不会再产生完成回调。

### 返回大厅与退出

```lua
y3.lobby.return_lobby({
    level_id = 'LOBBY_LEVEL_ID',
    game_mode = 'LOBBY_MODE_ID',
    max_player = 8,
})

y3.lobby.exit_game()
```

`return_lobby(params)` 和 `exit_game()` 都可以在未连接时直接调用。已连接时，框架会先清理队伍、匹配等大厅状态，再执行返回或退出。返回大厅成功时，完成结果包含 `platform_requested = true`、`entered_target = 'unknown'`、`confirm_by = 'platform_request_sent'`。

返回或退出正在处理时：

- 新的 `connect()` 会立即失败，`code = connection_closing`。
- 新的队伍、匹配、聊天、同房分流、跨房合流、口令等操作会立即失败，`code = terminal_in_progress`。
- 第二个返回或退出请求会立即失败，`code = terminal_locked`。

`return_lobby()` 请求结束后，状态会恢复为 `idle`。`exit_game()` 会先发出请求完成结果，再退出游戏。

## 状态快照与失败处理

```lua
local state_result = y3.lobby.get_state()
if state_result.accepted then
    print(state_result.result_data.status)
    print(state_result.result_data.failed_events)
end
```

| 现象 | 先检查 |
| --- | --- |
| `code = invalid_game_play_id` | 建立连接时是否传入正整数玩法 ID |
| `code = not_connected` | 是否先调用并完成 `y3.lobby.connect(玩法ID)` |
| `code = connection_pending` | 连接还未完成，等待后再重试 |
| `code = invalid_argument` | 必填参数是否缺失 |
| `code = timeout` | 平台回包或状态确认是否超时 |
| `code = player_not_selected` | 同房分流指定了 `players`，但当前玩家不在列表内 |
| `code = not_in_team` / `not_captain` | 是否已在队伍中，以及当前玩家是否为队长 |
| `code = not_matching` / `state_conflict` | 当前匹配、启动或队伍状态是否允许该操作 |
| `code = member_not_found` / `player_not_found` | 目标 AID 是否属于当前队伍，或服务端是否能找到该玩家 |
| `code = local_player_missing` / `local_aid_missing` | 当前客户端是否能读取本地玩家及其平台 AID |
| `code = rpc_failed` | 远端调用失败；原始错误值会保留在 `result_data.remote_error_code` |
| `code = cancelled_by_terminal` | 旧请求被返回大厅或退出游戏取消，不需要再处理旧请求结果 |
| `code = connection_closing` | 正在返回大厅或退出游戏，当前不能建立连接 |
| `code = terminal_in_progress` | 正在返回大厅或退出游戏，当前不能发起其他功能请求 |
| `code = terminal_locked` | 已有返回大厅或退出游戏请求正在处理，不要重复点击 |
| `failed_events` 非空 | Lua 完成回调或 ECA 完成事件是否处理失败 |

[下一篇：ECA 功能使用](./04-ECA功能使用.md)
