---
name: eca-json-builder
description: >
  生成、读取和修改 Y3 编辑器可见可编辑的 ECA JSON，包括项目函数、全局触发器、
  单位或技能物编触发器、变量、插件函数库、ECA 数据表、自定义事件和存档数据。
  Use when the task mentions ECA 函数、ECA 触发器、trigger JSON、物编触发器、
  ECA 变量、插件触发器、ECA 数据表、项目自定义事件或存档读取。
---

# ECA JSON Builder

生成编辑器能够加载、显示、编辑并再次保存的正式 ECA 数据。使用 Python 3 标准库和内建
`eca_index.json`；项目函数与触发器不得写入 `custom_eca/custom_eca.json` 或
`ExternalResource/readable_eca/`。

## 工作流

1. 确定项目根目录、地图目录和目标种类。目标文件路径、已有索引和同类编辑器文件均已定位时完成。
2. 按目标分支只读取 [详细参考](eca-json-builder.md) 的相关章节：
   - 项目函数：`项目正式 ECA 函数`、`生成后加载到 Y3 编辑器`。
   - 全局触发器：`触发器结构`、`Arg 类型 ID 速查`、`变量系统`、`工作流`。
   - 动态子触发：`动态子触发 DSL`。
   - 单位或技能物编触发器：对应的 `物编触发器` 章节。
   - 插件、数据表、自定义事件或存档：对应的数据源章节。
   先用 `rg -n "^## " .codex/skills/eca-json-builder/eca-json-builder.md` 定位章节，再读取所需范围；不把整份参考文档载入上下文。
3. 用 `lookup.py` 或专用读取脚本取得真实名称、参数顺序和类型。每个即将生成的 ECA 名称都能在索引或项目数据中解析时完成。
4. 用 `gen_function.py`、`gen_trigger.py` 或物编编辑脚本生成；先运行 `--dry-run`，检查目标路径、稳定 ID、参数节点和变量声明。预览没有未知类型回退或未解释警告时完成。
5. 写入后运行结构校验，并核对触发器文件数与 `index.txt` 条目数。所有生成文件通过校验且索引一一对应时完成。
6. 按“编辑器加载协议”加载并取得编辑器证据。编辑器能够显示目标、重新保存后关键结构保持一致时完成。
7. 运行 `py -3 .codex\skills\eca-json-builder\verify_skill.py`。命令成功且本轮没有未处理的“硬化信号”时才结束任务。

## 工具

| 工具 | 职责 |
|---|---|
| `lookup.py` | 查询内建 ECA 索引和全局事件 |
| `gen_function.py` | 从 DSL 生成项目 ECA 函数并维护函数索引 |
| `gen_trigger.py` | 从 DSL 生成全局触发器并维护触发器索引 |
| `eca_json_helper.py` | 模板、结构校验、合并和描述规范化 |
| `read_trigger.py` / `edit_trigger.py` | 读取或编辑已有全局与物编触发器 |
| `var_manager.py` | 管理全局、局部和物编组变量 |
| `plugin_eca.py` | 读取插件函数库与触发器数据 |
| `table_reader.py` | 读取 ECA 数据表 |
| `project_event.py` | 读取项目自定义事件 |
| `archive_reader.py` | 读取存档定义 |
| `verify_skill.py` | 运行 Skill 静态检查和全部回归测试 |

常用命令：

```powershell
py -3 .codex\skills\eca-json-builder\lookup.py <eca_name>
py -3 .codex\skills\eca-json-builder\gen_function.py --dry-run <函数DSL.json>
py -3 .codex\skills\eca-json-builder\gen_trigger.py --dry-run <触发器DSL.json>
py -3 .codex\skills\eca-json-builder\eca_json_helper.py validate <生成结果.json>
py -3 .codex\skills\eca-json-builder\verify_skill.py
```

## 编辑器加载协议

当目标地图已在编辑器中打开时，按依赖顺序执行：

1. 写文件前调用一次 `y3editor.save_editor()`，保留当前编辑器修改。
2. 先写入并校验全部项目函数、函数索引和稳定 `func_id`。
3. 写入函数后直接调用 `y3editor.restart_editor(save_before_restart=false)`；旧编辑器内存仍持有旧函数，因此此处不得再次保存。
4. 地图重开后核对函数文件和索引未被改写，再串行导入不含 `sub_trigger` 的普通触发器：

```text
y3editor.import_eca(trigger_json_path="<global_trigger/trigger/*.json 的绝对路径>")
```

记录返回的 `success`、`mode`、`trigger_id` 和 `hotfix_status`。`import_eca` 仅接受
`global_trigger/trigger/` 下的触发器；项目函数通过地图重开加载。

含 `sub_trigger` 的触发器通过 `restart_editor(save_before_restart=false)` 加载。重开后保存并检查
子触发字典、父子 ID 和裸整数注册 ID 仍完整。

## 生成不变量

| 不变量 | 完成标准 |
|---|---|
| ECA 名称 | `event_type`、`condition_type`、`action_type` 均由索引解析，不自创名称 |
| 自定义事件 | DSL 名称唯一解析到 `customevent.json` 的整数 ID；最终 `CUS_EVENT` 保存整数 |
| 变量引用 | tuple 为 `["TYPE", "name", "local"/"global"]`，声明与引用类型一致 |
| TABLE | 普通对象或列表先降级为局部 TABLE 的创建与填值动作，调用处传 `VARIABLE` |
| 变量初值 | STRING=`""`，BOOLEAN=`false`，FLOAT/ANGLE=`0.0`，其他类型=`0` |
| 全局变量 | 同步维护 `variable_dict`、`variable_group_info`、`variable_length_dict` |
| 可选参数 | builder 同步生成长度一致的 `op_arg` 与 `op_arg_enable` |
| 函数身份 | 同一逻辑的 `func_id` 跨重复生成和跨地图保持稳定 |
| 函数描述 | 每个参数在 `func_des` 的语义位置出现一次 `{参数名}` 占位符 |
| 函数返回 | `func_return`、`func_rtv_name_list`、返回动作和局部返回变量一致 |

## 硬化门

以下任一情况是“硬化信号”：生成器异常或输出错误、编辑器拒绝/隐藏/改写结果、用户人工纠正、
需要手工修改生成 JSON、需要临时绕过 Skill。出现信号时，立即读取并完整执行
[问题硬化流程](references/hardening.md)，再回到当前任务。

硬化完成标准：可推广的问题已有最小复现和回归保护，修复位于正确层级，统一验证通过；涉及编辑器
序列化的问题还须保留脱敏的编辑器样本并完成往返比对。单地图或单业务特例留在项目实现中，不写入
通用 Skill。
