# 简易匹配测试界面上下文

- 任务：参考 `F:\release` 的完整大厅匹配 UI，在当前项目补充用于测试匹配功能的简易 UI。
- 期望结果：测试人员可以通过可见界面操作现有 `BOB` 能力并观察关键状态，减少对快捷键和聊天命令的依赖。
- 用户指定方案：以 `F:\release` 为参考，而不是从零猜测交互。
- 意图推断：目标是功能联调和验收，不是把正式大厅界面完整移植过来。
- 已确认事实：参考项目通过 `include 'pub.ui'`、`UI.init()` 在 `BOB` 准备就绪后绑定 `[0]F1_main_hall`。
- 已确认事实：参考 UI 依赖大厅 UI JSON、`layout_player_block_leader` 预制体及 `MainTips`、`PlayerSave`、`SquadUi` 等正式业务对象。
- 已确认事实：当前项目只有 9 个基础 UI 文件，没有 `[0]F1_main_hall.json` 和 `layout_player_block_leader.json`。
- 已确认事实：当前项目已经提供创建队伍、加入队伍、离队、开始/取消匹配、本地私人副本、RPC 私人副本和状态查询等测试函数。
- 约束：保持测试 UI 简单；不新增依赖；复用现有 `BOB` API；本轮处于 deep-interview，只澄清需求，不实现。
- 未知项：第一版必须覆盖的测试动作、是否测试聊天、是否展示队员列表、界面资源构建方式、视觉要求、验收方式。
- 决策边界未知：可否新增独立 UI JSON/预制体；是否允许调整 `pub.lua` 暴露状态；是否保留现有快捷键作为备用入口。
- 可能触点：`maps/EntryMap/script/pub/init.lua`、`pub.lua`、新的简易 UI Lua 模块、`maps/EntryMap/ui/` 下的界面资源。
- 初始上下文摘要状态：不需要压缩。
