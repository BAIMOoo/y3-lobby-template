# -*- coding: utf-8 -*-
from __future__ import annotations

import ast
import json
import re
import subprocess
import sys
import unittest
import zipfile
from pathlib import Path
from typing import Optional
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
TEST_FILE = Path(__file__).resolve()
DOCS = ROOT / "docs" / "游戏大厅系统"
README = DOCS / "README.md"
TOPIC_FILES = [
    "01-项目概览.md",
    "02-迁移.md",
    "03-Lua功能使用.md",
    "04-ECA功能使用.md",
    "05-验证与故障排查.md",
]
ALL_DOCS = ["README.md", *TOPIC_FILES]
MIGRATION_PACKAGE = DOCS / "迁移包"
PACKAGE_Y3_ROOT = MIGRATION_PACKAGE / "script" / "y3"
PACKAGE_PROTOCOL = MIGRATION_PACKAGE / "需要合并到项目" / "custom" / "protocol" / "protocol.pb"
PACKAGE_ECA_TRIGGER = MIGRATION_PACKAGE / "大厅服务ECA触发包.zip"
WORKTREE = ROOT / ".omx" / "worktrees" / "y3-lualib-lobby"
ENTRYMAP_Y3_ROOT = ROOT / "maps" / "EntryMap" / "script" / "y3"
CHILD_MAP_Y3_ROOT = ROOT / "maps" / "MapName001" / "script" / "y3"
PUBLISHED_Y3_ROOTS = [WORKTREE, ENTRYMAP_Y3_ROOT, CHILD_MAP_Y3_ROOT, PACKAGE_Y3_ROOT]
FUNCTION_DSL = ROOT / "tools" / "eca" / "lobby_service_functions.json"
TEST_GAME_PLAY_ID = 190356

EXPECTED_ECA_NAMES = [
    "大厅服务 - 建立连接",
    "大厅服务 - 获取连接状态",
    "大厅服务 - 设置匹配分数",
    "大厅服务 - 创建队伍",
    "大厅服务 - 加入队伍",
    "大厅服务 - 离开队伍",
    "大厅服务 - 解散队伍",
    "大厅服务 - 转移队长",
    "大厅服务 - 移出队员",
    "大厅服务 - 获取队伍成员",
    "大厅服务 - 开始匹配",
    "大厅服务 - 取消匹配",
    "大厅服务 - 发送队伍聊天",
    "大厅服务 - 发送世界聊天",
    "大厅服务 - 获取聊天记录",
    "大厅服务 - 局内私人副本",
    "大厅服务 - 加入口令",
    "大厅服务 - 获取口令",
    "大厅服务 - 返回大厅",
    "大厅服务 - 退出游戏",
    "大厅服务 - 获取状态快照",
    "大厅服务 - 获取聊天消息",
    "大厅服务 - 获取队伍成员项",
    "大厅服务 - 获取队伍信息",
    "大厅服务 - 获取玩家信息",
    "大厅服务 - 刷新玩家信息",
]

FORBIDDEN_DOC_TERMS = [
    "专属游戏房间",
    "轻量方案",
    "Lua-only",
    "完整 BOB 迁移",
    "完整BOB迁移",
    "完整迁移",
    "门面函数",
    "门面",
    "事实入口",
    "三层迁移模型",
    "底层 RPC",
    "接线",
    "业务接口",
    "业务类 ECA 对外调用接口",
]

FORBIDDEN_FIXED_VALUES = [
    "1876423410",
    "1263239224",
    "a1377fd18bfb11f1b9d919bc08ffd172",
]

FENCE_RE = re.compile(r"^```([^\r\n`]*)\r?\n(.*?)^```\s*$", re.MULTILINE | re.DOTALL)
LINK_RE = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def iter_fenced_blocks(path: Path):
    for match in FENCE_RE.finditer(read_text(path)):
        yield match.group(1).strip(), match.group(2)


def resolve_markdown_target(source: Path, raw_target: str) -> Optional[Path]:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    target = target.split("#", 1)[0]
    target = unquote(target)
    if not target or target.startswith(("http://", "https://", "mailto:")):
        return None
    return (source.parent / target).resolve()


class DocumentationExamplesTest(unittest.TestCase):
    def test_python_38_grammar(self):
        try:
            ast.parse(read_text(TEST_FILE), filename=str(TEST_FILE), feature_version=(3, 8))
        except SyntaxError as error:
            self.fail(f"测试脚本不兼容 Python 3.8 语法：{error}")

    def test_expected_document_order_matches_migrate_then_usage_flow(self):
        missing = [name for name in ALL_DOCS if not (DOCS / name).is_file()]
        self.assertEqual([], missing)
        readme = read_text(README)
        positions = [readme.index(f"](./{name})") for name in TOPIC_FILES]
        self.assertEqual(sorted(positions), positions)
        self.assertLess(positions[1], positions[2], "文档必须先讲迁移，再讲 Lua 使用")
        self.assertLess(positions[1], positions[3], "文档必须先讲迁移，再讲 ECA 使用")

    def test_local_markdown_links_exist(self):
        failures = []
        for name in ALL_DOCS:
            source = DOCS / name
            for raw_target in LINK_RE.findall(read_text(source)):
                target = resolve_markdown_target(source, raw_target)
                if target is not None and not target.exists():
                    failures.append(f"{source.relative_to(ROOT)} -> {raw_target}")
        self.assertEqual([], failures, "无效本地链接：\n" + "\n".join(failures))

    def test_json_examples_parse(self):
        failures = []
        checked = 0
        for name in ALL_DOCS:
            for index, (info, code) in enumerate(iter_fenced_blocks(DOCS / name), 1):
                if info.split(maxsplit=1)[0].lower() != "json":
                    continue
                checked += 1
                try:
                    json.loads(code)
                except json.JSONDecodeError as error:
                    failures.append(f"{name} 代码块 {index}: {error}")
        self.assertGreater(checked, 0, "文档中必须至少包含一个可校验 JSON 示例")
        self.assertEqual([], failures, "JSON 示例无效：\n" + "\n".join(failures))

    def test_lua_examples_have_valid_parseable_syntax(self):
        checker = (
            "local source = io.read('*a')\n"
            "local ok, err = load(source, 'doc-example', 't', {})\n"
            "if ok then os.exit(0) end\n"
            "local wrapped = 'local y3 = {}\\nlocal GameAPI = {}\\nlocal Bind = setmetatable({}, { __index = function() return function() return {} end end })\\nlocal function __doc_example__()\\n' .. source .. '\\nend\\n'\n"
            "local wrapped_ok, wrapped_err = load(wrapped, 'doc-example-fragment', 't', {})\n"
            "if wrapped_ok then os.exit(0) end\n"
            "io.stderr:write(tostring(err), '\\n', tostring(wrapped_err), '\\n')\n"
            "os.exit(1)\n"
        )
        failures = []
        checked = 0
        for name in ALL_DOCS:
            for index, (info, code) in enumerate(iter_fenced_blocks(DOCS / name), 1):
                language = info.split(maxsplit=1)[0].lower() if info else ""
                if language not in {"lua", "luau"}:
                    continue
                checked += 1
                completed = subprocess.run(
                    ["lua", "-e", checker],
                    input=code,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    encoding="utf-8",
                )
                if completed.returncode != 0:
                    failures.append(f"{name} Lua 代码块 {index}: {completed.stderr.strip()}")
        self.assertGreater(checked, 0, "文档中必须至少包含一个可校验 Lua 示例")
        self.assertEqual([], failures, "Lua 示例语法无效：\n" + "\n".join(failures))

    def test_docs_use_plain_external_call_interface_language(self):
        corpus = "\n".join(read_text(DOCS / name) for name in ALL_DOCS)
        self.assertIn("对外调用接口", corpus)
        self.assertIn("局内私人副本", corpus)
        for term in FORBIDDEN_DOC_TERMS:
            with self.subTest(term=term):
                self.assertNotIn(term, corpus)

    def test_docs_list_26_official_eca_external_call_interfaces(self):
        eca_doc = read_text(DOCS / "04-ECA功能使用.md")
        missing = [name for name in EXPECTED_ECA_NAMES if f"`{name}`" not in eca_doc]
        self.assertEqual([], missing)
        self.assertIn("大厅服务请求完成", eca_doc)
        self.assertIn("回调数据", eca_doc)
        self.assertIn("failed_events", eca_doc)
        self.assertIn("event_missing", eca_doc)
        self.assertIn("大厅服务状态变化", eca_doc)
        self.assertIn("事件数据", eca_doc)
        self.assertIn("获取队伍成员项", eca_doc)
        self.assertIn("获取聊天消息", eca_doc)
        self.assertIn("刷新玩家信息", eca_doc)

    def test_docs_explain_eca_trigger_package_import_without_generator_json(self):
        eca_doc = read_text(DOCS / "04-ECA功能使用.md")
        migration_doc = read_text(DOCS / "02-迁移.md")
        self.assertIn("导入迁移包中的 `大厅服务ECA触发包.zip`", eca_doc)
        self.assertIn("从函数列表中选择导入的“大厅服务 - 接口名”", eca_doc)
        self.assertNotIn("执行 Lua 代码", eca_doc)
        self.assertNotIn("Bind['大厅服务 - 建立连接']", eca_doc)
        self.assertNotIn("tools/eca/lobby_service_functions.json", eca_doc)
        self.assertNotIn("tools/eca/lobby_service_tests.json", eca_doc)
        self.assertNotIn("tools/eca/lobby_service_functions.json", migration_doc)
        self.assertNotIn("tools/eca/lobby_service_tests.json", migration_doc)

    def test_docs_describe_required_dynamic_fields_and_internal_version_boundary(self):
        corpus = "\n".join(read_text(DOCS / name) for name in ALL_DOCS)
        for field in ["game_mode", "score", "level_id", "max_player", "game_map_id"]:
            with self.subTest(field=field):
                self.assertIn(field, corpus)
        self.assertIn("2.0", corpus)
        self.assertIn("内部", corpus)
        self.assertNotRegex(corpus, r"version\s*[=:]")

    def test_example_maps_use_prod_lobby_endpoints(self):
        lobby_entry = read_text(ROOT / "maps" / "EntryMap" / "script" / "main.lua")
        target_entry = read_text(ROOT / "maps" / "MapName001" / "script" / "main.lua")
        self.assertIn(f"local GAME_PLAY_ID = {TEST_GAME_PLAY_ID}", lobby_entry)
        self.assertIn("y3.lobby.connect(GAME_PLAY_ID, false, 'prod')", lobby_entry)
        self.assertIn("y3.lobby.connect(GAME_PLAY_ID, true, 'prod')", target_entry)
        self.assertIn("y3.lobby.get_connection_status()", target_entry)
        self.assertNotIn("include 'pub.init'", lobby_entry)
        self.assertNotIn("include 'pub.init'", target_entry)

    def test_external_docs_only_expose_qa_and_prod_lobby_environments(self):
        corpus = "\n".join(read_text(DOCS / name) for name in ALL_DOCS)
        self.assertIn("`qa`", corpus)
        self.assertIn("`prod`", corpus)
        self.assertNotIn("`pre`", corpus)
        self.assertNotIn("'pre'", corpus)

    def test_example_maps_do_not_keep_legacy_pub_lobby(self):
        for map_name in ["EntryMap", "MapName001"]:
            script_root = ROOT / "maps" / map_name / "script"
            pub_root = script_root / "pub"
            with self.subTest(map_name=map_name, path="test_ui.lua"):
                self.assertTrue((script_root / "test_ui.lua").is_file())
                self.assertFalse(pub_root.exists())

    def test_docs_explain_required_game_play_id_for_connection(self):
        corpus = "\n".join(read_text(DOCS / name) for name in ALL_DOCS)
        self.assertIn(f"y3.lobby.connect({TEST_GAME_PLAY_ID})", corpus)
        self.assertIn("玩法固定 ID", corpus)
        self.assertIn("不要使用 `GameAPI.get_dungeon_info().game_play_id`", corpus)
        self.assertIn("作者之家后台", corpus)
        self.assertIn("它不是地图模式配置项，也不写在 `match.json` 或 `dungeon.json` 中", corpus)
        self.assertIn("invalid_game_play_id", corpus)
        self.assertNotIn("connect()` 无参数", corpus)
        self.assertNotIn("由平台运行环境提供，不是调用参数", corpus)

    def test_private_dungeon_docs_explain_filter_result_fields(self):
        lua_guide = read_text(DOCS / "03-Lua功能使用.md")
        eca_guide = read_text(DOCS / "04-ECA功能使用.md")
        self.assertIn("y3.lobby.private_dungeon", lua_guide)
        self.assertNotIn("{ aid = 10001 }", lua_guide)
        self.assertIn("调用者不再传 `players`", lua_guide)
        self.assertIn("调用者不传 `players`", eca_guide)
        for field in ["selected_players", "skipped_in_game_players", "unknown_status_players"]:
            with self.subTest(field=field):
                self.assertIn(field, lua_guide)
                self.assertIn(field, eca_guide)

    def test_docs_do_not_reuse_current_project_event_or_function_ids(self):
        corpus = "\n".join(read_text(DOCS / name) for name in ALL_DOCS)
        for value in FORBIDDEN_FIXED_VALUES:
            with self.subTest(value=value):
                self.assertNotIn(value, corpus)

    def test_migration_package_contains_only_official_lualib_protocol_and_eca_trigger(self):
        files = [path for path in MIGRATION_PACKAGE.rglob("*") if path.is_file()]
        unexpected = []
        for path in files:
            rel = path.relative_to(MIGRATION_PACKAGE).as_posix()
            if rel.startswith("script/y3/"):
                continue
            if rel == "需要合并到项目/custom/protocol/protocol.pb":
                continue
            if rel == "大厅服务ECA触发包.zip":
                continue
            unexpected.append(rel)
        self.assertEqual([], unexpected, "迁移包存在白名单之外的文件：\n" + "\n".join(unexpected))
        self.assertTrue(PACKAGE_Y3_ROOT.is_dir())
        self.assertTrue((PACKAGE_Y3_ROOT / "game" / "lobby" / "proto" / "service_pb.lua").is_file())
        self.assertTrue(PACKAGE_PROTOCOL.is_file())
        self.assertTrue(PACKAGE_ECA_TRIGGER.is_file())
        self.assertFalse((MIGRATION_PACKAGE / "script" / "pub").exists())

    def test_migration_eca_trigger_contains_event_and_all_functions(self):
        with zipfile.ZipFile(PACKAGE_ECA_TRIGGER) as archive:
            self.assertEqual(
                {"attr.json", "cus_event.json", "ReadMe.md", "trigger_data.json", "version_info.json"},
                set(archive.namelist()),
            )
            event_data = json.loads(archive.read("cus_event.json"))
            trigger_data = json.loads(archive.read("trigger_data.json"))

        events = {
            event["name"]: event["conf"]
            for event in event_data["cus_event"].values()
        }
        self.assertEqual(
            {
                "大厅服务请求完成": [["回调数据", 100011]],
                "大厅服务状态变化": [["事件数据", 100011]],
            },
            events,
        )

        function_names = set()

        def collect_functions(value):
            if isinstance(value, dict):
                if isinstance(value.get("func_name"), str):
                    function_names.add(value["func_name"])
                for child in value.values():
                    collect_functions(child)
            elif isinstance(value, list):
                for child in value:
                    collect_functions(child)

        collect_functions(trigger_data)
        self.assertEqual(set(EXPECTED_ECA_NAMES), function_names)

    def test_migration_package_does_not_include_eca_json_or_project_specific_files(self):
        forbidden_suffixes = [
            "tools/eca/lobby_service_functions.json",
            "tools/eca/lobby_service_tests.json",
            "gamemode.json",
            "match.json",
            "dungeon.json",
            "setting.json",
        ]
        package_files = [
            path.relative_to(MIGRATION_PACKAGE).as_posix()
            for path in MIGRATION_PACKAGE.rglob("*")
            if path.is_file()
        ]
        for suffix in forbidden_suffixes:
            with self.subTest(suffix=suffix):
                self.assertFalse(any(path.endswith(suffix) for path in package_files))

    def test_official_lualib_patch_contains_lobby_module_and_not_user_log_change(self):
        required = [
            WORKTREE / "game" / "lobby" / "init.lua",
            WORKTREE / "game" / "lobby" / "eca.lua",
            WORKTREE / "game" / "lobby" / "result.lua",
            WORKTREE / "game" / "lobby" / "state.lua",
            WORKTREE / "game" / "lobby" / "client.lua",
            WORKTREE / "game" / "lobby" / "proto" / "service.pb",
            WORKTREE / "game" / "lobby" / "proto" / "service_pb.lua",
            WORKTREE / "tools" / "generate_lobby_service_pb.py",
        ]
        missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
        self.assertEqual([], missing)
        self.assertTrue((WORKTREE / "init.lua").is_file())
        if (WORKTREE / "util" / "log.lua").is_file():
            self.assertFalse((WORKTREE / "util" / "log.lua").read_text(encoding="utf-8").startswith("-- lobby"))

    def test_published_lualib_uses_role_names_in_log_files(self):
        expected = (WORKTREE / "util" / "log.lua").read_bytes()
        expected = expected.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        for lualib_root in PUBLISHED_Y3_ROOTS:
            with self.subTest(root=lualib_root):
                actual = (lualib_root / "util" / "log.lua").read_bytes()
                actual = actual.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
                self.assertEqual(expected, actual)
                self.assertIn(b"get_role__unique_name", actual)
                self.assertIn(b"lua_player%02d_%s.log", actual)

    def test_embedded_service_protocol_is_current(self):
        synchronized_files = [
            "game/lobby/proto/proto_helper.lua",
            "game/lobby/proto/service.pb",
            "game/lobby/proto/service_pb.lua",
            "tools/generate_lobby_service_pb.py",
        ]
        for lualib_root in PUBLISHED_Y3_ROOTS:
            with self.subTest(root=lualib_root):
                process = subprocess.run(
                    [sys.executable, "tools/generate_lobby_service_pb.py", "--check"],
                    cwd=lualib_root,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(0, process.returncode, process.stdout + process.stderr)
                for relative_path in synchronized_files:
                    expected = (WORKTREE / relative_path).read_bytes()
                    actual = (lualib_root / relative_path).read_bytes()
                    if Path(relative_path).suffix != ".pb":
                        expected = expected.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
                        actual = actual.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
                    self.assertEqual(
                        expected,
                        actual,
                        f"大厅协议发布副本不一致: {lualib_root / relative_path}",
                    )

    def test_lobby_module_sources_keep_protocol_and_version_boundaries(self):
        lobby_root = WORKTREE / "game" / "lobby"
        source = "\n".join(
            path.read_text(encoding="utf-8", errors="replace")
            for path in lobby_root.rglob("*.lua")
        )
        self.assertRegex(source, r"""["']2\.0["']""")
        self.assertIn("custom/protocol/protocol.pb", source)
        self.assertNotIn("version =", read_text(ROOT / "tools" / "eca" / "lobby_service_functions.json"))

    def test_real_bob_e2e_boundary_is_documented_as_not_tested_when_unavailable(self):
        guide = read_text(DOCS / "05-验证与故障排查.md")
        self.assertIn("Not-tested", guide)
        self.assertIn("真实 BOB", guide)
        self.assertNotIn("fake client 可以替代真实 BOB", guide)


if __name__ == "__main__":
    unittest.main()
