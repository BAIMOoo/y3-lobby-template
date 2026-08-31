# Lua Trace 问题归档

> 记录运行期 Trace / stack traceback 类问题，便于后续复用修复经验。
> ⚠️ 每次自动化测试或手动调试遇到 trace 时，必须在此沉淀。

## 记录规范

- 问题现象：简述报错内容或触发场景
- 根因：说明为什么会出现该 Trace
- 解决方案：记录最终有效的修复方式
- 预防建议：总结后续如何避免重复出现

---

## 1. include 路径错误导致模块加载失败

- 时间：2026-05-14
- 场景：热重载时 `include 'td_game'` 报 `module not found`
- Trace：`attempt to call a nil value` — 模块未加载导致后续函数调用 nil
- 根因：`include` 路径基于 `script/` 目录，不需要加前缀。写成 `include 'script/td_game'` 会找不到
- 解决方案：`include 'td_game'`（直接模块名，不含路径前缀）
- 预防建议：include 路径 = 文件名去 `.lua` 后缀，不加目录前缀

---

## 2. 事件回调中 unit 已被移除

- 时间：2026-05-14
- 场景：怪物死亡事件回调中访问 `unit:get_point()`，偶发 nil
- Trace：`attempt to index a nil value (local 'pos')`
- 根因：事件回调时 unit 可能已被 `remove()` 或引擎回收，`get_point()` 返回 nil
- 解决方案：回调内先 `if not unit:is_exist() then return end`
- 预防建议：所有事件回调中操作 unit 前必须 `is_exist()` 守卫

---

## 3. 本地私人副本目标使用大厅关卡导致 `KeyError: 'map_data'`

- 时间：2026-07-20
- 场景：在 `EntryMap` 大厅中调用 `request_create_private_dungeon`，目标仍传当前 `EntryMap`
- Trace：`error during Python call: KeyError: 'map_data'`
- 根因：本地私人副本接口需要独立目标关卡的地图数据；大厅关卡不能作为自己的副本目标
- 解决方案：传入目标关卡 `MapName001` 的 UUID；同时在 `dungeon.json` 中为对应十进制关卡 ID 注册目标模式
- 预防建议：大厅与副本使用不同关卡时，本地接口传 UUID，匹配/RPC 配置使用同一 ID 的十进制表示，并确保副本配置存在

---

## 4. 返回大厅目标未注册导致“目标副本配置不存在”

- 时间：2026-07-23
- 场景：从 `MapName001` 的 `1003` 私人副本请求创建 `EntryMap` 的 `1001` 单人大厅实例
- 现象：平台提示“目标副本配置不存在”
- 根因：调整副本配置时，用 `MapName001 + 1002/1003` 整体替换了原有 `EntryMap` 配置，导致 `EntryMap + 1001` 从 `dungeon.json` 消失
- 解决方案：按关卡十进制 ID 合并配置，同时保留 `EntryMap + 1001` 和 `MapName001 + 1002/1003`
- 预防建议：修改 `dungeon.json` 后运行 `tests/game_mode_config_test.ps1`，分别验证大厅和副本关卡的模式注册

---

*最后更新: 2026-07-23*

---

## 5. 自定义事件已配置但 Lua 元数据为空导致终态事件发送失败

- 时间：2026-07-30
- 场景：ECA 调用大厅服务后，请求本身成功，但发送 `大厅服务请求完成` 终态事件时报“不存在此自定义事件”，随后编号通道又报“尚未生成自定义事件元数据”。
- Trace：`y3.util.eca_helper.lua:22: 不存在此自定义事件：大厅服务请求完成`。
- 根因：主关卡 `customevent.json` 已包含事件 `1876423410`，但 `script/y3-helper/meta/customEvents.lua` 仍为 0 字节；因此 `y3.eca.call` 没有名称实现，`y3.const.CustomEventName` 也没有名称到编号的映射。当前 Y3 Lua 库没有不依赖生成元数据的按名称反查事件编号 API。
- 解决方案：名称通道保持优先；编号通道先读取生成元数据，缺失时使用从主关卡编辑器配置核对得到的正式编号 `1876423410`，并按生成代码格式把终态字典封装为 `{ 回调数据 = payload }` 后调用 `y3.game.send_custom_event`。子关卡继承主关卡事件配置，使用同一编号。
- 预防建议：新增事件后同时核对主关卡实际编号和 `customEvents.lua` 生成状态；若删除重建事件导致编号变化，必须同步更新 Lua 后备常量与合同测试。禁止手写 Y3 工程 JSON。

*最后更新: 2026-07-30*

---

## 6. 线上 `virtual_script` 不包含 `.pb` 导致大厅连接未发出

- 时间：2026-08-10
- 场景：本地存在 `script/y3/game/lobby/proto/service.pb`，上传平台后调用 `y3.lobby.connect(...)`。
- Trace：`virtual_script/y3/game/lobby/proto/service.pb: No such file or directory`。
- 根因：平台只将 Lua 脚本放入 `virtual_script`，未包含脚本目录中的 `.pb` 二进制文件；旧版 `proto_helper.lua` 在网络连接前直接用 `io.open` 读取该文件。
- 解决方案：由 `service.pb` 确定性生成 `service_pb.lua`，使用分块 `\\xNN` 字符串内嵌协议字节；运行时 `require` Lua 模块后传给 `pb.load`，不再读取 `.pb` 文件。
- 预防建议：发布前运行 `py -3 tools/generate_lobby_service_pb.py --check` 和 `lua tests/lobby_embedded_protocol_test.lua`，同时验证内嵌内容与源 `.pb` 逐字节一致。

*最后更新: 2026-08-10*

---

## 11. 本地调试固定使用 QA 环境

- 时间：2026-08-12
- 场景：地图入口已调用 `y3.lobby.connect(190356, false, 'pre')`，但本地多开日志仍显示连接 QA 地址 `42.186.215.253:8092`，多人私人副本请求返回 `dungeonLevelConf is nil`。
- 结论：本地 BOB 后端与平台发布环境的配置并不等价，不能通过显式 `endpoint_env` 绕过本地调试隔离。客户端端点解析应优先判断 `y3.game.is_debug_mode()`，本地调试始终选择 QA。
- 解决方案：端点选择顺序保持为“本地调试或平台 QA > 显式 `endpoint_env` > 平台 pre > prod”。因此本地即使传入 `pre` 也连接 `42.186.215.253:8092`；发布到平台后仍可根据显式参数选择 pre。
- 预防建议：端点合同测试必须覆盖“本地调试 + 显式 pre”，并直接断言最终仍为 QA 地址，避免本地环境意外连接预发布服务。

*最后更新: 2026-08-12*

---

## 10. 统一局内私人副本必须按调用链区分平台 ID 与引擎 UUID

- 时间：2026-08-11
- 场景：大厅测试 UI 将“同房分流”和“跨房合流”合并为一个“局内私人副本”按钮后，组队和单人路径分别报错。
- Trace：组队路径先报 `string expected for field 'aid', got number`，修正后又报 `err = 4, data = dungeonLevelConf is nil`；无队伍路径曾报 `ValueError: badly formed hexadecimal UUID string`。首次组队编码异常还会令后续同类 BOB 请求提示“不能重入”。
- 根因：统一入口涉及三类不能互换的标识：BOB 连接使用上传平台后的玩法固定 ID，组队 `DungeonSpaceField.game_map_id` 使用当前地图版本 UUID，`level_id` 使用 `dungeon.json` 的 38 位配置键；单人引擎 `request_create_private_dungeon` 使用目标关卡 UUID。重构时曾把运行时 `game_play_id=10209075` 当成旧版玩法固定 ID `190356`，导致服务端登录上下文无法查到 `DungeonLevelConf`；后续又混用了两种关卡 ID 表示。合并按钮时还把单人引擎模式 `1003` 复用于组队 BOB，而参照项目的 `DungeonManager_StartMatchPrivateDungeonGame` 使用 `1002`；同时新增的 `in_game` 三态过滤偏离了参照项目全量传递 `team_info.members` 的契约。
- 解决方案：两张地图连接 BOB 时恢复传入平台玩法固定 ID `190356` 和对应 `pre` 服务环境；组队 BOB 使用当前地图 UUID `game_map_id`、`dungeon.json` 十进制 `level_id` 和组队模式 `1002`，单人引擎使用目标 UUID `engine_level_id` 和单人模式 `1003`。组队 `players` 按 `team_info.members` 全量构建，每项 `aid` 转成字符串并保留必要的 `version = '2.0'`，同时在发送日志中输出玩法 ID、两个关卡字段、模式和人数。
- 预防建议：不要从 `GameAPI.get_dungeon_info().game_play_id` 推导 BOB 的玩法固定 ID，也不要因为对外按钮合并就合并两条底层路由的模式参数和成员规则。回归测试必须分别锁定连接玩法 ID、服务环境、组队地图 UUID、组队平台关卡 ID、单人引擎 UUID、单人/组队模式、全量成员和 protobuf 字符串 AID/version。

*补充时间: 2026-08-11*

---

## 7. 测试 UI 的接口拒绝和异步失败未写入日志

- 时间：2026-08-10
- 场景：本地点击大厅测试 UI 的分流或合流按钮，界面可能提示失败，但运行日志中没有对应操作和错误。
- 根因：`safe_action` 只在 Lua 抛出异常时调用 `log.error`；接口返回 `accepted = false`、异步完成事件失败以及按钮因前置条件禁用时，都只更新界面文字或按钮状态。
- 解决方案：统一记录操作发起、同步完成、同步拒绝、Lua 异常、异步完成、状态事件和按钮不可用原因；日志固定包含 `action`、`request_id`、`code`、`reason` 等字段。聊天、加入口令和连接相关的非标准失败原因必须脱敏，不能记录聊天正文、关卡口令或连接令牌。
- 预防建议：测试 UI 新增对外调用接口时必须经过统一日志入口，并用回归测试覆盖同步成功、同步拒绝、异常、异步成功、异步失败、禁用原因和敏感信息脱敏。

*最后更新: 2026-08-10*

---

## 8. `xpcall` 只返回错误文本导致 Python 堆栈丢失

- 时间：2026-08-10
- 场景：第二次调用同房分流时，平台接口返回 `error during Python call: KeyError: 1`，但日志中没有 Python 文件名和行号。
- 根因：大厅框架的 `xpcall` 错误处理器只执行 `tostring(err)`；等接口把 `request_error` 返回给上层后，Python 异常上下文已经失效，无法再通过 `python.get_exc_info()` 取得堆栈。
- 解决方案：在 `xpcall` 错误处理器内立即调用 `log.error`。现有日志器会在异常仍有效时读取 `python.get_exc_info()` 并写入 Python 堆栈；对外接口仍只返回简短错误文本。聊天和加入口令等敏感操作不读取可能包含敏感内容的 Python 堆栈，日志与对外 `reason` 都只返回脱敏摘要。
- 预防建议：凡是需要捕获平台 Python 异常的保护调用，都必须在 `xpcall` 错误处理器中完成日志记录，不能只在 `pcall` 或 `xpcall` 返回后补日志。

*最后更新: 2026-08-10*

---

## 9. 无回调跨图请求被错误建模为完成事件和永久锁

- 时间：2026-08-10
- 场景：本地测试中第一次同房分流只提交了 `request_create_private_dungeon`，客户端仍留在大厅；数秒后再次点击时，平台 Python 层抛出 `KeyError: 1`。
- 根因：该引擎接口没有最终结果回调，框架却把“引擎方法已调用”包装成成功完成事件，随后又用只能依赖换图重建运行时才能清除的 `cross_map_transition` 永久锁阻止重试。伪完成误导 ECA/UI，永久锁则在平台未切图时让当前运行时无法恢复。
- 解决方案：同房分流、口令加入和返回大厅采用请求提交型契约，返回 `cross_map_tracking = 'degraded'` 和 `entered_target = 'unknown'`，不发送成功 completion、不登记 ECA 等待项、不保留永久跨图锁。没有非空 `custom_param` 时严格使用旧实现的三参数调用。真实成功由新地图加载后重新查询状态确认。
- 预防建议：无最终回调的跨图接口必须分别表达“请求已发出”和“目标地图已进入”。防重只能使用自动恢复的短期机制；真实客户端未切图时不得依赖手工清锁恢复，也不得用本地 completion 代替平台成功证据。

*最后更新: 2026-08-10*

---

## 12. 单人私人副本路径未加载项目协议导致旧网络握手缺类型

- 时间：2026-08-24
- 场景：项目同时使用大厅服务和旧 `net_work`；单人私人副本走 `solo_engine`，不会创建大厅 BOB 客户端。
- Trace：`net_work/core/core.lua:174: type 'pb.CheckRequest' does not exists`，旧网络连接后持续握手失败并重连。
- 根因：旧 `register_pb()` 只尝试 `proto.pb` 与 `protocol/proto.pb` 两个相对路径；当前运行目录下均不可用。此前依赖大厅连接间接调用 `pb.loadCustomProtocol()`，但单人引擎路径不会初始化大厅协议，因此加载顺序不成立。
- 解决方案：`net_work` 初始化时主动调用 `pb.loadCustomProtocol()`，并通过 `pb.types()` 确认 `pb.CheckRequest` 已注册；旧相对文件路径仅作为兼容回退，所有路径都缺少类型时在初始化阶段给出明确错误。
- 预防建议：共享 protobuf 类型的模块必须自行完成协议初始化，不得依赖另一业务模块的副作用；回归测试应覆盖项目协议成功、旧文件回退和类型仍缺失三种情况。
- 隔离验证：目标项目排查大厅私人副本期间，可临时将 `LEGACY_PB_SERVICE_ENABLED` 设为 `false`。此模式保留 `Client`、handler 和服务包装对象，但跳过旧 PB 注册、Socket 连接、握手和重连；项目 `protocol.pb` 同时恢复为大厅协议版本。该开关只用于故障隔离，不代表旧服务的最终下线方案。

*最后更新: 2026-08-24*

---

## 13. 大厅客户端计时器在 loading 恢复后触发假超时

- 时间：2026-08-31
- 场景：玩家 loading 或客户端主线程长时间卡顿后，大厅连接、版本检查或业务请求立即报超时；网络轮询还会在恢复首帧集中补跑。
- Trace：`【BOB】请求远端版本号超时！`，或大厅完成事件返回 `code = 'timeout'`。
- 根因：大厅超时、心跳和底层网络轮询使用 `y3.ctimer`。它按客户端墙钟推进，恢复后的首个 `OnTick` 会扫描并执行 loading 期间所有已到期的秒计时器；而网络与 HTTP 回调的恢复顺序没有保证。`y3.ltimer` 实际由 `y3.timer.loop_frame(1)` 驱动，与 `y3.timer` 使用相同的同步逻辑帧时间，旧注释将其描述为异步本地计时器不准确。
- 解决方案：大厅业务超时、连接超时、退出清理、心跳、断线延迟和 `y3.util.network` 轮询统一迁移到 `y3.ltimer`；需要下一帧执行的逻辑使用 `y3.ltimer.wait_frame(1)`。版本 HTTP 检查删除额外的 5 秒 `ctimer`，改用 `request_url` 原生 `timeout = 5`，通过一次性 `finish` 守卫处理空响应、解析失败和迟到重复回调。
- 预防建议：大厅与客户端网络框架禁止重新引入 `y3.ctimer`；新增或修改超时逻辑时运行 `lua tests/lobby_timer_contract_test.lua`。计时回调只处理大厅和客户端状态，不修改同步玩法数据。

*最后更新: 2026-08-31*
