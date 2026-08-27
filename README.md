# 私有副本测试

这是一个基于 Y3 2.0 的大厅系统与私有副本测试项目，用于展示和验证大厅连接、组队、匹配、聊天以及进入私人副本等游戏内流程。

本项目主要作为大厅系统迁移和接入时的参考。迁移到其他项目时，应按专题文档选择通用框架文件，不要直接复制本项目专属的测试界面和玩法逻辑。

## 实现分支

| 分支 | 示例实现 | 适用作者 |
| --- | --- | --- |
| `main` | Lua 调用与 Lua 测试界面，主要实现位于 `maps/*/script/` | Lua 作者 |
| `eca-example-map` | 编辑器可见、可编辑的 ECA 函数、触发器与正式示例界面 | ECA 作者 |

ECA 作者应切换到 `eca-example-map` 分支参照实现，不要把 `main` 分支的 `test_ui.lua` 当成 ECA 示例。两个分支复用同一套 `y3.lobby` 运行时框架；区别主要在项目调用层和示例 UI 的实现方式。

## 核心能力

- 建立大厅服务连接并查询连接状态。
- 创建、加入和管理队伍。
- 发起匹配、取消匹配并进入目标关卡。
- 使用队伍聊天和世界聊天。
- 创建单人或多人私人副本，并通过口令加入副本。
- 返回大厅、退出游戏以及查询大厅状态。
- 通过 Lua 或 ECA 调用同一套大厅系统能力。

## 地图职责

| 地图 | 职责 |
| --- | --- |
| `EntryMap` | 项目入口与大厅测试地图。`main` 提供 Lua 测试界面；`eca-example-map` 同时持有大厅与副本两套 ECA UI 和对应触发器。 |
| `MapName001` | 匹配、单人私人副本和多人私人副本的目标关卡，用于验证进入关卡后的连接与运行状态。 |

## 详细文档

大厅系统的迁移步骤、Lua 与 ECA 使用说明、验证方法和故障排查，请阅读[游戏大厅系统文档](./docs/游戏大厅系统/README.md)。

## 代码仓库

- GitHub 主仓库：[https://github.com/BAIMOoo/y3-lobby-template](https://github.com/BAIMOoo/y3-lobby-template)
- Gitee 镜像仓库：[https://gitee.com/baim00/y3-lobby-template](https://gitee.com/baim00/y3-lobby-template)
