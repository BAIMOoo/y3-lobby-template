# ECA 功能使用

[返回文档首页](./README.md)

本文面向 ECA 作者，只说明 27 个 ECA 对外调用接口、返回字段和请求完成事件。迁移步骤见 [迁移](./02-迁移.md)。

返回大厅、退出游戏和请求取消结果都通过已有的 `大厅服务请求完成` 事件接收，不新增 ECA 对外调用接口。

## 准备

ECA 项目需要先完成三件事：

1. 按迁移文档复制 `script/y3/` 和协议文件。
2. 在主关卡创建自定义事件 `大厅服务请求完成`。
3. 给该事件添加字典参数 `回调数据`。

不要复制其他项目的事件编号。目标项目已有同名事件时，检查参数是否为 `回调数据`，类型是否为字典。

如果需要实时刷新界面，也可以创建自定义事件 `大厅服务状态变化`，并添加字典参数 `事件数据`。这个事件是可选的；未创建时不会阻断大厅功能，只是收不到状态变化通知。`大厅服务请求完成` 仍是异步接口必需事件。

## 编辑器操作路径

ECA 触发器中按下面方式调用：

1. 在需要发起大厅服务请求的位置添加动作“执行 Lua 代码”。
2. 在代码中从 `Bind` 表取出“大厅服务 - 接口名”，再调用该函数。
3. 有参数时，把 ECA 参数列表按顺序传给 `args`，例如 `args[1]` 是第一个参数。
4. 将“执行 Lua 代码”的返回值接收为 ECA `TABLE` 变量。
5. 读取返回表里的 `accepted`、`reason`、`code`、`request_id`。

建连示例：

```lua
local call = Bind['大厅服务 - 建立连接']
return call(args[1])
```

上例中，`args[1]` 是正整数玩法 ID。当前示例项目使用 `10190356`；迁移到自己的项目时，填写目标项目对应的玩法 ID。这个值不是调试参数，也不是 UUID 格式的 `map_id`。

如果当前关卡是目标玩法关卡，可把第二个参数传为 `true`：

```lua
local call = Bind['大厅服务 - 建立连接']
return call(args[1], true)
```

单参数示例：

```lua
local call = Bind['大厅服务 - 创建队伍']
return call(args[1])
```

参数表示例：

```lua
local call = Bind['大厅服务 - 开始匹配']
return call(args[1])
```

上例中，`args[1]` 由 ECA 参数列表提供，类型应为 `TABLE`。

## 返回字段

每次调用 ECA 对外调用接口后，都会立即得到一个 ECA `TABLE`。

| 立即返回字段 | 含义 |
| --- | --- |
| `accepted` | 请求是否已发出 |
| `reason` | 未发出原因或补充说明 |
| `code` | 便于判断的结果码 |
| `request_id` | 请求编号 |
| `action` | 操作名称 |
| `sync` | 是否为同步结果 |
| `result_data` | 同步返回的数据 |

`accepted = false` 时，不会再触发请求完成事件。

`accepted = true` 且接口为异步动作时，后续只触发一次 `大厅服务请求完成`，并通过 `回调数据` 返回：

| `回调数据` 字段 | 含义 |
| --- | --- |
| `request_id` | 与立即返回的请求编号对应 |
| `action` | 操作名称 |
| `success` | 最终是否成功 |
| `reason` | 最终失败原因或补充说明 |
| `code` | 最终结果码 |
| `result_data` | 最终结果数据 |

远端未知错误不会被框架强行解释，最终结果保持 `code = rpc_failed`，并把原始错误值放在 `result_data.remote_error_code`。

如果建立连接或其他对外调用接口的请求尚未完成，此时又调用“大厅服务 - 返回大厅”或“大厅服务 - 退出游戏”，旧请求会通过同一个 `大厅服务请求完成` 事件返回一次取消结果：`success = false`、`code = cancelled_by_terminal`。旧请求即使之后返回，也不会再改变结果。

请求前发现事件不存在时，接口返回 `accepted = false`、`code = event_missing`。请求已经发出但通知失败时，失败记录会写入 `failed_events`，可通过“大厅服务 - 获取状态快照”查看。

状态变化事件的 `事件数据` 包含 `event`、`source`、`status`、`code`、`reason`、`data`、`snapshot`、`sequence`。稳定事件名包括 `connection_changed`、`team_changed`、`team_joined`、`team_left`、`member_joined`、`member_left`、`matching_changed`、`launching_changed`、`message_received`、`client_update_required`。

其中 `data` 只使用稳定公共字段：连接事件为 `code`、`reason`；队伍事件为 `team`；离队事件为 `reason`、`team`；成员事件为 `member`；匹配和启动事件分别为 `matching`、`launching`；聊天事件为 `message`；更新事件为 `required`。不要读取 BOB 内部字段。

## 27 个 ECA 对外调用接口

所有接口均返回 ECA `TABLE`。

| ECA 对外调用接口 | 参数 | 说明 |
| --- | --- | --- |
| `大厅服务 - 建立连接` | `玩法ID: integer`；`是否在游戏关卡: boolean`，可不填 | 按项目玩法 ID 建立或重新建立大厅服务连接 |
| `大厅服务 - 获取连接状态` | 无 | 同步查询当前连接状态 |
| `大厅服务 - 设置匹配分数` | `分数: integer` | 更新当前玩家分数 |
| `大厅服务 - 创建队伍` | `人数上限: integer` | 当前玩家按人数上限创建队伍 |
| `大厅服务 - 加入队伍` | `队伍编号: integer` | 加入指定队伍 |
| `大厅服务 - 离开队伍` | 无 | 离开当前队伍 |
| `大厅服务 - 解散队伍` | 无 | 队长解散队伍 |
| `大厅服务 - 转移队长` | `目标AID: integer` | 把队长转移给指定队员 |
| `大厅服务 - 移出队员` | `目标AID: integer` | 队长移出指定队员 |
| `大厅服务 - 获取队伍成员` | 无 | 同步返回成员数据 |
| `大厅服务 - 获取队伍成员项` | `序号: integer` | 同步返回第 N 个队伍成员 |
| `大厅服务 - 开始匹配` | `匹配参数: table` | 必须包含 `level_id`、`game_mode`；`score` 可选 |
| `大厅服务 - 取消匹配` | 无 | 取消当前匹配 |
| `大厅服务 - 发送队伍聊天` | `消息: string` | 发送队伍聊天 |
| `大厅服务 - 发送世界聊天` | `消息: string` | 发送世界聊天 |
| `大厅服务 - 获取聊天记录` | `频道: string`，可不填 | 同步返回聊天记录 |
| `大厅服务 - 获取聊天消息` | `序号: integer`；`频道: string`，可不填 | 同步返回第 N 条聊天消息 |
| `大厅服务 - 同房分流` | `分流参数: table` | 必须包含 `level_id`、`game_mode`、`max_player`；`players` 可选 |
| `大厅服务 - 跨房合流` | `合流参数: table` | 必须包含 `game_map_id`、`level_id`、`game_mode`、`players` |
| `大厅服务 - 加入口令` | `口令: string` | 使用口令进入目标关卡 |
| `大厅服务 - 获取口令` | 无 | 同步返回当前目标关卡口令 |
| `大厅服务 - 返回大厅` | `大厅参数: table` | 必须包含 `level_id`、`game_mode`、`max_player`；无需预先连接；已有连接时先清理 |
| `大厅服务 - 退出游戏` | 无 | 无需预先连接；已有连接时先清理 |
| `大厅服务 - 获取状态快照` | 无 | 同步返回当前状态 |
| `大厅服务 - 获取队伍信息` | `目标AID: integer`，可不填 | 异步查询指定 AID 的队伍信息；省略时查询自己 |
| `大厅服务 - 获取玩家信息` | `目标AID: integer`，可不填 | 异步查询指定 AID 的玩家信息；省略时查询自己 |
| `大厅服务 - 刷新玩家信息` | 无 | 异步把当前玩家状态同步到大厅服务 |

新项目应使用上表名称。

## 参数表字段

| 参数表 | 必填字段 | 可选字段 | 说明 |
| --- | --- | --- | --- |
| `匹配参数` | `level_id`、`game_mode` | `score` | `level_id` 和 `game_mode` 应与 `match.json` 对应 |
| `分流参数` | `level_id`、`game_mode`、`max_player` | `players`、`custom_param` | 用于同房分流 |
| `合流参数` | `game_map_id`、`level_id`、`game_mode`、`players` | 无 | `players` 每项只需要包含 `aid` |
| `大厅参数` | `level_id`、`game_mode`、`max_player` | `custom_param` | 用于返回大厅 |

`version` 字段由框架内部写入固定字符串 `"2.0"`，ECA 作者不需要传。

同房分流的 `players` 是可选目标玩家列表，每项包含 `aid`；提供时仅列表内玩家切换，省略时当前房间内调用到该接口的玩家都会执行。

同房分流、加入口令和获取口令不要求预先连接 BOB。组队、匹配、聊天、跨房合流和高级查询接口仍需先建立连接。

同房分流、加入口令、跨房合流和返回大厅的完成结果会包含 `platform_requested`、`entered_target`、`confirm_by`：分别表示平台切换请求是否已发出、是否已确认进入目标关卡、确认依据。无法确认是否已进入目标关卡时，`entered_target` 为 `unknown`。

## 使用顺序

ECA 调用建议按这个顺序处理：

1. 玩家进入后调用“大厅服务 - 建立连接”，并传入目标项目的玩法 ID。
2. 立即结果 `accepted = false` 时显示 `reason`，不等待请求完成事件。
3. 立即结果 `accepted = true` 时保存 `request_id`。
4. 在 `大厅服务请求完成` 的 `回调数据` 中匹配 `request_id`。
5. 根据 `success`、`reason`、`result_data` 更新按钮、提示和状态显示。

目标玩法关卡如果只需要“大厅服务 - 返回大厅”或“大厅服务 - 退出游戏”，可以直接调用，不需要先建立大厅连接。已有连接时，两个接口都会先清理大厅状态；返回大厅的完成事件可从 `result_data.cleanup` 查看清理结果。其他需要大厅连接的对外调用接口仍需先连接并等待成功。

返回或退出正在处理时，新的“大厅服务 - 建立连接”会返回 `connection_closing`，队伍、匹配、聊天、同房分流、跨房合流、口令等操作会返回 `terminal_in_progress`，第二个返回或退出会返回 `terminal_locked`。

返回大厅结束后状态恢复为 `idle`。退出游戏会先触发请求完成事件，再退出游戏。

同一名玩家同一时间不要发多个队伍、匹配、同房分流、跨房合流、返回大厅或退出请求。聊天可以按按钮触发逐条发送。

“大厅服务 - 获取队伍成员项”和“大厅服务 - 获取聊天消息”用于 ECA 逐项读取列表，序号从 `1` 开始。合法序号越界时会立即返回 `accepted = true`、`result_data.exists = false`。

“大厅服务 - 获取队伍信息”始终异步查询；玩家没有队伍属于成功结果，`result_data.has_team = false`。“大厅服务 - 获取玩家信息”缓存命中时同步返回，未命中时才异步查询，找不到玩家时返回 `player_not_found`。“大厅服务 - 刷新玩家信息”异步把当前玩家状态同步到大厅服务，不是从服务端拉取信息。只有异步受理的请求才通过 `大厅服务请求完成` 返回最终结果。

## 常见失败

| 现象 | 先检查 |
| --- | --- |
| `event_missing` | 是否创建 `大厅服务请求完成`，是否有字典参数 `回调数据` |
| `invalid_game_play_id` | 建立连接时是否传入正整数玩法 ID；不要填写 UUID 格式的 `map_id` |
| `not_connected` | 是否先调用“大厅服务 - 建立连接”并等待成功 |
| `connection_pending` | 连接还在进行，等待后再操作 |
| `invalid_argument` | 是否缺少必填字段，例如人数上限、`level_id`、`game_mode`、`max_player`、`players` |
| `player_not_selected` | 同房分流指定了 `players`，但当前玩家不在列表内 |
| `not_in_team` / `not_captain` | 是否已在队伍中，以及当前玩家是否为队长 |
| `not_matching` / `state_conflict` | 当前匹配、启动或队伍状态是否允许该操作 |
| `member_not_found` / `player_not_found` | 目标 AID 是否属于当前队伍，或服务端是否能找到该玩家 |
| `local_player_missing` / `local_aid_missing` | 当前客户端是否能读取本地玩家及其平台 AID |
| `rpc_failed` | 远端调用失败；原始错误值见 `result_data.remote_error_code` |
| `cancelled_by_terminal` | 旧请求被返回大厅或退出游戏取消，按取消结果更新界面即可 |
| `connection_closing` | 正在返回大厅或退出游戏，当前不能建立连接 |
| `terminal_in_progress` | 正在返回大厅或退出游戏，当前不能发起其他功能请求 |
| `terminal_locked` | 已有返回大厅或退出游戏请求正在处理，不要重复点击 |
| 队伍操作失败 | 队伍编号、目标 AID、队长权限 |
| 匹配失败 | `gamemode.json`、`match.json`、`dungeon.json` 是否对应 |
| 同房分流或跨房合流失败 | 目标模式、人数、队伍成员、关卡是否允许进入 |
| 加入口令失败 | 口令、人数上限、中途加入时间 |

[下一篇：验证与故障排查](./05-验证与故障排查.md)
