# 游戏大厅系统

本文档说明如何把大厅服务框架迁移到自己的项目，并使用框架提供的 Lua 与 ECA 对外调用接口。

迁移目标不是复制测试项目的玩法逻辑，而是接入通用能力：大厅连接、组队、匹配、聊天、局内私人副本、加入口令、获取口令、返回大厅和退出游戏。

“同房分流”和“跨房合流”只用于解释局内私人副本的底层路由：无队伍时走引擎单人私人副本请求；有队伍时由队长发起组队私人副本请求，并只带明确不在游戏中的成员。Lua 与 ECA 不再公开这两个旧正式接口。

## 文档导航

| 文档 | 用途 |
| --- | --- |
| [项目概览](./01-项目概览.md) | 了解框架能做什么 |
| [迁移](./02-迁移.md) | 复制文件、配置 JSON、创建 ECA 完成事件 |
| [Lua 功能使用](./03-Lua功能使用.md) | 使用 `y3.lobby` 对外调用接口 |
| [ECA 功能使用](./04-ECA功能使用.md) | 使用 26 个 ECA 对外调用接口 |
| [验证与故障排查](./05-验证与故障排查.md) | 检查迁移结果并定位问题 |

建议先完成迁移，再按项目作者类型阅读 Lua 或 ECA 使用说明。

## 文档范围

本文档只覆盖游戏内大厅服务框架，不包含：

- 外部项目配置器。
- Y3、Lua、ECA 基础教学。
- 项目专属战斗与单位生成逻辑。
- 正式 UI 美术制作。
- BOB 后端服务部署与协议开发。
- 地图发布及平台审核流程。

## 可参考的当前项目文件

如需对照测试项目，可查看：

- `maps/EntryMap/script/main.lua`
- `maps/EntryMap/script/y3/game/lobby/init.lua`
- `maps/EntryMap/script/y3/game/lobby/eca.lua`
- `maps/EntryMap/script/pub/test_ui.lua`
- `tests/eca_lobby_api_contract_test.lua`
- `tests/lobby_embedded_protocol_test.lua`
- `tools/eca/lobby_service_functions.json`
- `tools/eca/lobby_service_tests.json`
- `setting.json`

这些文件分别展示正式 `y3.lobby` 框架、测试项目入口、测试 UI 适配和框架契约验证。`pub/test_ui.lua` 属于测试项目 UI，不是迁移时必须复制的通用框架文件。
