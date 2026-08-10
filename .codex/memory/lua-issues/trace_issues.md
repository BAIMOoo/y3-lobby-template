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

## 9. 无回调跨图请求完成后重复调用触发平台 `KeyError`

- 时间：2026-08-10
- 场景：本地测试中第一次同房分流只提交了 `request_create_private_dungeon`，客户端仍留在大厅；数秒后再次点击时，平台 Python 层抛出 `KeyError: 1`。
- 根因：该引擎接口没有最终结果回调，框架却在“平台请求已提交”后立即释放通用操作锁，把请求提交完成误当成跨图生命周期完成。本地测试不会实际切换地图，因此后续点击会重复进入不可重入的平台接口。
- 解决方案：平台调用成功返回后保留 `cross_map_transition` 锁；后续同房分流返回 `cross_map_pending`，不再调用平台接口。锁随目标地图的新 Lua 运行时或测试重置一起清除；平台调用本身抛错时不设置锁。
- 预防建议：无最终回调的跨图接口必须分别表达“请求已提交”和“目标地图已进入”。在目标地图加载前，应由独立的跨图阶段锁阻止重复提交。

*最后更新: 2026-08-10*
