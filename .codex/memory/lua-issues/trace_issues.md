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
