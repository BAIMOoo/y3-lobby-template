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

`connect(玩法ID, 是否在游戏关卡, 服务环境)` 的第一个参数是正整数玩法固定 ID，必填。当前示例项目使用 `190356`；迁移到自己的项目时，填写目标项目上传平台后供 BOB 服务识别的玩法固定 ID。不要用运行时 `GameAPI.get_dungeon_info().game_play_id` 代替它。

第二个参数可选，默认为 `false`。如果当前关卡已经是目标玩法关卡，并且仍需要连接大厅服务，可传 `true`：

```lua
y3.lobby.connect(190356, true)
```

第三个参数可选，用于指定服务环境。外部项目只需要使用 `'qa'` 和 `'prod'`：本地调试始终连接 `qa`，即使显式传入其他值也不会改变；项目在线上发布时应显式传入 `'prod'`：

```lua
y3.lobby.connect(190356, false, 'prod')
```

重复调用时，框架会返回当前连接请求或当前连接状态，不会创建多个客户端。

组队、匹配、聊天、高级查询和有队伍的局内私人副本接口必须在连接成功后调用。未连接时会立即返回失败，常见 `code` 为 `not_connected` 或 `connection_pending`。无队伍的局内私人副本、加入口令和获取口令不要求预先连接。

`return_lobby(params)` 和 `exit_game()` 不要求预先连接。目标玩法关卡如果只需要返回大厅或退出游戏，不需要为此调用 `connect()`。两者语义不同：返回大厅只提交跨图请求，保留队伍、匹配和 BOB 连接；退出游戏才会尽力清理大厅状态。

## 完成回调

异步接口会先返回立即结果。真正完成时，Lua 侧通过 `on_complete` 订阅：

```lua
local listener = y3.lobby.on_complete(function(payload)
    print(payload.action)
    print(payload.request_id)
    print(payload.success)
end)
```

同一个普通异步请求只会完成一次。同步失败不会再触发完成回调。

`private_dungeon()` 在无队伍或一人队伍时、`join_by_token()` 和 `return_lobby()` 是请求提交型跨图接口。引擎没有提供平台最终结果回调，因此这些 request-only 路由不会触发 `on_complete`；其 `accepted = true` 只表示当前客户端已发出引擎请求。必须等待新地图实际加载并重新查询状态，才能确认成功。

`private_dungeon()` 在多人队伍时走组队异步路由：只有队长可发起，框架按 `team_info.members` 全量传递成员，完成结果仍通过 `on_complete` 返回。组队路由失败时不会降级调用单人引擎路径。一人队伍与无队伍相同，走单人引擎请求。

如果建立连接或其他对外调用接口的请求尚未完成，此时又调用 `return_lobby()` 或 `exit_game()`，旧请求会被取消，并且只会收到一次 `success = false`、`code = cancelled_by_terminal` 的完成结果。旧请求即使之后返回，也不会再改变结果。

返回大厅的立即结果通过 `result_data.platform_requested` 表示是否已调用引擎换图方法；该接口不返回 `cleanup_pending`。需要取消订阅时调用：

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
| `request_id` | 普通异步请求编号；request-only 跨图路由为空 |
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
| 建立连接 | `y3.lobby.connect(game_play_id, in_game, endpoint_env)` | `game_play_id` 为正整数玩法 ID，必填；`in_game`、`endpoint_env` 可选；外部项目本地使用 `qa`，线上使用 `prod` |
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
| 局内私人副本 | `y3.lobby.private_dungeon(params)` | `level_id`、`game_mode`、`max_player` 必填；`team_game_mode` 可选；多人队伍时全量传递成员并走组队异步路由 |
| 加入口令 | `y3.lobby.join_by_token(token)` | 使用口令进入目标关卡 |
| 获取口令 | `y3.lobby.get_token()` | 获取当前目标关卡口令 |
| 返回大厅 | `y3.lobby.return_lobby(params)` | `level_id`、`game_mode`、`max_player` 必填；无需预先连接；不清理队伍、匹配或 BOB |
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

### 局内私人副本

```lua
y3.lobby.private_dungeon({
    level_id = 'PLATFORM_LEVEL_ID',
    engine_level_id = 'ENGINE_LEVEL_UUID',
    game_mode = 1003,
    team_game_mode = 1002,
    max_player = 4,
    game_map_id = 'TARGET_MAP_ID',
})
```

`level_id` 是 `dungeon.json` 使用的 38 位关卡配置键，多人队伍时原样传给 BOB 的 `DungeonSpaceField.level_id`；`engine_level_id` 是同一目标关卡的 UUID 表示，无队伍或一人队伍时传给 `request_create_private_dungeon`。省略 `engine_level_id` 时会兼容沿用 `level_id`。`game_map_id` 是当前地图版本 UUID，可使用状态快照中的 `game_map_id`；它和 `level_id` 不是同一种表示。`game_mode` 传给单人引擎路由；`team_game_mode` 传给多人 BOB 路由，省略时兼容沿用 `game_mode`。`max_player` 是单人引擎路由的房间容量；目标关卡是否允许进入、人数上限和中途加入规则仍由 `dungeon.json` 决定。

调用者不再传 `players`，也不再选择“同房分流”或“跨房合流”。框架按当前队伍状态自动路由：

- 无队伍或一人队伍：走单人引擎请求，`route = 'solo_engine'`、`completion_mode = 'request_only'`、`request_id = ''`。`accepted = true` 只表示请求已提交，不表示平台最终进入。
- 多人队伍：仅队长可发起，按队伍快照全量传递成员并走组队异步请求，`route = 'team_bob'`、`completion_mode = 'async_event'`、`request_id` 非空；最终结果通过 `on_complete` 返回。

局内私人副本返回的 `result_data` 至少包含：

| 字段 | 含义 |
| --- | --- |
| `route` | `solo_engine`、`team_bob` 或 `rejected` |
| `completion_mode` | `request_only`、`async_event` 或 `sync_rejected` |
| `request_id` | 组队异步请求编号；单人和同步拒绝为空字符串 |
| `selected_players` | 多人 BOB 路由中全量传递的队伍成员 |
| `skipped_in_game_players` | 兼容字段；当前全量传递契约下为空 |
| `unknown_status_players` | 兼容字段；当前全量传递契约下为空 |
| `platform_requested` | 是否已调用平台或引擎请求 |
| `entered_target` | 当前可确认的进入状态；单人提交后通常为 `unknown`，同步拒绝为 `not_entered` |

旧 `y3.lobby.same_room_split(params)` 和 `y3.lobby.cross_room_merge(params)` 已从正式 Lua 接口删除。内部实现仍可能用“同房分流/跨房合流”解释路由，但新项目不要调用或文档化这两个旧接口。

### 加入口令与获取口令

```lua
local token_result = y3.lobby.get_token()
if token_result.accepted then
    y3.lobby.join_by_token(token_result.result_data.token)
end
```

`get_token()` 和 `join_by_token(token)` 不要求预先连接 BOB。`get_token()` 从当前关卡运行信息中读取口令。`join_by_token()` 返回 `accepted = true` 后仍需等待目标地图加载；平台可能因口令无效、房间已满或补人时间结束而拒绝。

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

`return_lobby(params)` 和 `exit_game()` 都可以在未连接时直接调用。`return_lobby(params)` 会立即提交引擎换图请求，不执行取消匹配、离队、删除玩家信息或销毁 BOB；当前地图未成功切换时，原连接和队伍缓存仍可使用，并可再次提交返回请求。实际加载大厅地图后需要重新连接并查询远端队伍状态。

`exit_game()` 才会进入异步终态清理，依次尽力取消匹配、离队、删除玩家信息并释放客户端。退出正在处理时：

- 新的 `connect()` 会立即失败，`code = connection_closing`。
- 新的队伍、匹配、聊天、局内私人副本、口令等操作会立即失败，`code = terminal_in_progress`。
- 第二个返回或退出请求会立即失败，`code = terminal_locked`。

`return_lobby()` 提交后会恢复调用前的连接状态：原本已连接则仍为 `connected`，未连接则为 `idle`。`exit_game()` 会先发出请求完成结果，再退出游戏。

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
| `code = not_in_team` / `not_captain` | 是否已在队伍中，以及当前玩家是否为队长 |
| `code = not_matching` / `state_conflict` | 当前匹配、启动或队伍状态是否允许该操作 |
| `code = member_not_found` / `player_not_found` | 目标 AID 是否属于当前队伍，或服务端是否能找到该玩家 |
| `code = local_player_missing` / `local_aid_missing` | 当前客户端是否能读取本地玩家及其平台 AID |
| `code = rpc_failed` | 远端调用失败；原始错误值会保留在 `result_data.remote_error_code` |
| `code = cancelled_by_terminal` | 旧请求被返回大厅或退出游戏取消，不需要再处理旧请求结果 |
| `code = connection_closing` | 终态操作正在占用连接，当前不能建立连接 |
| `code = terminal_in_progress` | 终态操作正在处理，当前不能发起其他功能请求 |
| `code = terminal_locked` | 已有终态操作正在处理，不要重复提交 |
| `failed_events` 非空 | Lua 完成回调或 ECA 完成事件是否处理失败 |

[下一篇：ECA 功能使用](./04-ECA功能使用.md)
