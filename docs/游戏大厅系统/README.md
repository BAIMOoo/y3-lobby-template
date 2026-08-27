# 游戏大厅系统

本文档说明如何把大厅服务框架迁移到自己的项目，并使用框架提供的 Lua 与 ECA 对外调用接口。

仓库的 `main` 分支是 Lua 示例实现；ECA 作者应切换到 `eca-example-map` 分支查看编辑器可见、可编辑的 ECA 实现。文档中的接口契约对两个分支都适用，但示例 UI、触发器位置和初始化方式以对应分支为准。

迁移目标不是复制测试项目的玩法逻辑，而是接入通用能力：大厅连接、组队、匹配、聊天、局内私人副本、加入口令、获取口令、返回大厅和退出游戏。

“同房分流”和“跨房合流”只用于解释局内私人副本的底层路由：无队伍或一人队伍时走引擎单人私人副本请求；多人队伍时由队长发起组队私人副本请求，并按队伍快照全量传递成员。Lua 与 ECA 不再公开这两个旧正式接口。

## 文档导航

| 文档 | 用途 |
| --- | --- |
| [项目概览](./01-项目概览.md) | 了解框架能做什么 |
| [迁移](./02-迁移.md) | 复制文件、配置 JSON、导入 ECA 触发包 |
| [Lua 功能使用](./03-Lua功能使用.md) | 使用 `y3.lobby` 对外调用接口 |
| [ECA 功能使用](./04-ECA功能使用.md) | 使用 26 个 ECA 对外调用接口 |
| [验证与故障排查](./05-验证与故障排查.md) | 检查迁移结果并定位问题 |

建议先完成迁移，再按项目作者类型阅读 Lua 或 ECA 使用说明。

## 分支选择

| 作者类型 | 参考分支 | 主要参考内容 |
| --- | --- | --- |
| Lua | `main` | `maps/EntryMap/script/main.lua`、`test_ui.lua` 和 `y3.lobby` 调用流程 |
| ECA | `eca-example-map` | `EcaLobbyExample`、`EcaDungeonExample`、30 个正式 UI 触发器和 26 个大厅服务 ECA 函数 |

`eca-example-map` 中两套正式 ECA UI 都由 `EntryMap` 持有，`MapName001` 不保存另一份副本 UI。示例会根据运行模式显示大厅或副本界面，并默认关闭用于对照的 Lua 测试 UI。

## 文档范围

本文档只覆盖游戏内大厅服务框架，不包含：

- 外部项目配置器。
- Y3、Lua、ECA 基础教学。
- 项目专属战斗与单位生成逻辑。
- 正式 UI 美术制作。
- BOB 后端服务部署与协议开发。
- 地图发布及平台审核流程。

## 可参考的当前项目文件

`main` 分支中的 Lua 示例主要参考：

- `maps/EntryMap/script/main.lua`
- `maps/EntryMap/script/y3/game/lobby/init.lua`
- `maps/EntryMap/script/y3/game/lobby/eca.lua`
- `maps/EntryMap/script/test_ui.lua`
- `tests/eca_lobby_api_contract_test.lua`
- `tests/lobby_embedded_protocol_test.lua`

`eca-example-map` 分支中的 ECA 示例主要参考：

- `maps/EntryMap/ui/EcaLobbyExample.json`
- `maps/EntryMap/ui/EcaDungeonExample.json`
- `maps/EntryMap/global_trigger/trigger/ECA大厅UI - *.json`
- `maps/EntryMap/global_trigger/trigger/ECA副本UI - *.json`
- `contracts/ui/manifest.json`
- `tests/eca_lobby_eca_json_test.py`
- `tests/ui_contract_parity_test.py`
- `tools/eca/lobby_service_functions.json`
- `tools/eca/lobby_service_tests.json`
- `setting.json`

这些文件分别展示正式 `y3.lobby` 框架、项目入口、Lua/ECA 示例 UI 和契约验证。`test_ui.lua`、ECA 示例 UI、项目专属 UI 触发器及 `tools/eca/` 都不是迁移时必须复制的通用框架文件；ECA 目标项目应导入迁移包中的正式触发包，再按自己的 UI 和玩法改写调用层。
