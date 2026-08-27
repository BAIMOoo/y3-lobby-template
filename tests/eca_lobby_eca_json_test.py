# -*- coding: utf-8 -*-
from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FUNCTION_DSL = ROOT / "tools" / "eca" / "lobby_service_functions.json"
TRIGGER_DSL = ROOT / "tools" / "eca" / "lobby_service_tests.json"
ENTRY_TRIGGER_DSL = ROOT / "tools" / "eca" / "lobby_service_entry_map_tests.json"
STATUS_TRIGGER_DSL = ROOT / "tools" / "eca" / "lobby_status_event_listener.json"
ENTRY_UI_DSL = ROOT / "tools" / "eca" / "lobby_ui_entry_map.json"
DUNGEON_UI_DSL = ROOT / "tools" / "eca" / "lobby_ui_dungeon_map.json"
MAP_NAMES = ["EntryMap", "MapName001"]
ENTRY_LEVEL_ID = "172371058548994502264384971909138463342"
TRIGGER_ROOT = ROOT / "maps" / "EntryMap" / "global_trigger" / "trigger"
LOBBY_TRIGGER_ROOT = TRIGGER_ROOT / "大厅服务"
LOBBY_UI_TRIGGER_ROOT = LOBBY_TRIGGER_ROOT / "大厅UI"
DUNGEON_UI_TRIGGER_ROOT = LOBBY_TRIGGER_ROOT / "副本UI"
LOBBY_TEST_TRIGGER_ROOT = LOBBY_TRIGGER_ROOT / "接口测试"

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

FORBIDDEN_USER_TERMS = [
    "专属游戏房间",
    "创建私人副本",
    "启动多人私人副本",
    "加入口令副本",
    "获取副本口令",
    "重建大厅连接",
    "同房分流",
    "跨房合流",
]


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def walk_json(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk_json(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_json(child)


def lobby_function_files(map_name: str):
    function_root = ROOT / "maps" / map_name / "global_trigger" / "function"
    return list(function_root.rglob("大厅服务 - *.json"))


def ui_paths(node, prefix=""):
    path = f"{prefix}.{node['name']}" if prefix else node["name"]
    yield path
    for child in node.get("children", []):
        yield from ui_paths(child, path)


class LobbyEcaJsonTests(unittest.TestCase):
    def setUp(self):
        self.function_dsl = load_json(FUNCTION_DSL)
        self.trigger_dsl = load_json(TRIGGER_DSL)
        self.entry_trigger_dsl = load_json(ENTRY_TRIGGER_DSL)
        self.status_trigger_dsl = load_json(STATUS_TRIGGER_DSL)
        self.entry_ui_dsl = load_json(ENTRY_UI_DSL)
        self.dungeon_ui_dsl = load_json(DUNGEON_UI_DSL)
        self.functions = self.function_dsl["functions"]

    def test_function_dsl_lists_exactly_26_official_external_call_interfaces(self):
        names = [item["name"] for item in self.functions]
        self.assertEqual(EXPECTED_ECA_NAMES, names)
        self.assertEqual(26, len(names))
        self.assertEqual(len(names), len(set(names)))

    def test_entry_map_declares_lobby_completion_and_status_events(self):
        event_data = load_json(ROOT / "maps" / "EntryMap" / "customevent.json")
        events = {
            item["items"][1]: event_data["conf"][str(item["items"][0])]
            for item in event_data["group_info"]
        }
        self.assertEqual([["回调数据", 100011]], events["大厅服务请求完成"])
        self.assertEqual([["事件数据", 100011]], events["大厅服务状态变化"])

    def test_both_maps_declare_the_same_lobby_custom_events(self):
        expected = load_json(ROOT / "maps" / "EntryMap" / "customevent.json")
        actual = load_json(ROOT / "maps" / "MapName001" / "customevent.json")
        self.assertEqual(expected, actual)
        self.assertEqual(
            [["回调数据", 100011]],
            actual["conf"]["1876423410"],
        )

    def test_status_event_listener_only_dumps_the_event_table(self):
        trigger = self.status_trigger_dsl["triggers"][0]
        self.assertEqual(
            [["RECEIVE_CUSTOM_EVENT", "大厅服务状态变化"]],
            trigger["event"],
        )
        self.assertEqual([], trigger["condition"])
        self.assertEqual(
            [["DUMP_TABLE", ["GET_CUS_EVENT_PARAM", "事件数据"]]],
            trigger["action"],
        )

        generated = load_json(
            LOBBY_TEST_TRIGGER_ROOT
            / "大厅服务 - 状态变化打印.json"
        )
        self.assertEqual(1931000009, generated["trigger_id"])
        self.assertEqual([], generated["condition"])
        self.assertEqual(1204774815, generated["event"][0]["args_list"][0]["args_list"][0])
        self.assertEqual("DUMP_TABLE", generated["action"][0]["action_type"])
        self.assertIn("事件数据", json.dumps(generated["action"], ensure_ascii=False))

    def test_maps_contain_exactly_the_26_generated_lobby_functions(self):
        expected_files = {f"{name}.json" for name in EXPECTED_ECA_NAMES}
        for map_name in MAP_NAMES:
            paths = lobby_function_files(map_name)
            actual_files = {path.name for path in paths}
            with self.subTest(map_name=map_name):
                self.assertEqual(expected_files, actual_files)
                for path in paths:
                    payload = load_json(path)
                    self.assertEqual(path.stem, payload["func_name"])

    def test_return_lobby_descriptions_define_engine_uuid_and_request_only_contract(self):
        descriptions = [
            next(
                item["description"]
                for item in self.functions
                if item["name"] == "大厅服务 - 返回大厅"
            )
        ]
        for map_name in MAP_NAMES:
            path = next(
                path
                for path in lobby_function_files(map_name)
                if path.name == "大厅服务 - 返回大厅.json"
            )
            descriptions.append(load_json(path)["func_des"])

        for description in descriptions:
            with self.subTest(description=description):
                self.assertIn("level_id", description)
                self.assertIn("引擎 UUID", description)
                self.assertIn("不读取状态快照", description)
                self.assertIn("不等待完成事件", description)

    def test_generated_connect_function_requires_game_play_id_argument(self):
        for map_name in MAP_NAMES:
            path = next(
                path
                for path in lobby_function_files(map_name)
                if path.name == "大厅服务 - 建立连接.json"
            )
            payload = load_json(path)
            serialized = json.dumps(payload, ensure_ascii=False)
            eval_lua = payload["action"][0]["args_list"][1]
            with self.subTest(map_name=map_name):
                self.assertTrue(payload["valid"])
                self.assertIn("玩法ID", serialized)
                self.assertIn("INTEGER", serialized)
                self.assertIn("是否在游戏关卡", serialized)
                self.assertIn("BOOLEAN", serialized)
                self.assertIn("Bind['大厅服务 - 建立连接'](args[1], args[2])", serialized)
                self.assertEqual([True, True, False, False, False], eval_lua["op_arg_enable"])
                self.assertEqual(100001, eval_lua["op_arg"][1]["arg_type"])
                self.assertEqual("VARIABLE", eval_lua["op_arg"][1]["sub_type"])
                self.assertEqual(
                    ["BOOLEAN", "是否在游戏关卡", "local"],
                    eval_lua["op_arg"][1]["args_list"][0]["items"],
                )

    def test_each_eca_function_returns_one_table_and_keeps_lua_binding_enabled(self):
        for item in self.functions:
            with self.subTest(name=item["name"]):
                self.assertTrue(item.get("lua_bind"), item["name"])
                self.assertEqual(
                    [{"name": "result", "type": "TABLE", "var": "t"}],
                    item.get("returns"),
                )

    def test_optional_parameters_are_limited_to_documented_optional_inputs(self):
        optional = [
            (item["name"], param["name"])
            for item in self.functions
            for param in item.get("params", [])
            if not param.get("required", True)
        ]
        self.assertEqual(
            [
                ("大厅服务 - 建立连接", "是否在游戏关卡"),
                ("大厅服务 - 获取聊天记录", "频道"),
                ("大厅服务 - 获取聊天消息", "频道"),
                ("大厅服务 - 获取队伍信息", "目标AID"),
                ("大厅服务 - 获取玩家信息", "目标AID"),
            ],
            optional,
        )

    def test_dynamic_required_values_are_expressed_without_exposing_version(self):
        specs = {item["name"]: item for item in self.functions}
        self.assertEqual(
            [
                {"name": "玩法ID", "type": "INTEGER", "required": True},
                {"name": "是否在游戏关卡", "type": "BOOLEAN", "required": False},
            ],
            specs["大厅服务 - 建立连接"].get("params"),
        )
        self.assertEqual(
            [{"name": "人数上限", "type": "INTEGER", "required": True}],
            specs["大厅服务 - 创建队伍"].get("params"),
        )
        self.assertEqual(
            [{"name": "匹配参数", "type": "TABLE", "required": True}],
            specs["大厅服务 - 开始匹配"].get("params"),
        )
        self.assertEqual(
            [{"name": "副本参数", "type": "TABLE", "required": True}],
            specs["大厅服务 - 局内私人副本"].get("params"),
        )
        self.assertEqual(
            [{"name": "大厅参数", "type": "TABLE", "required": True}],
            specs["大厅服务 - 返回大厅"].get("params"),
        )

        serialized = json.dumps(self.function_dsl, ensure_ascii=False)
        for required_text in [
            "game_mode",
            "score",
            "level_id",
            "max_player",
            "game_map_id",
            "token",
            "玩法ID",
            "是否在游戏关卡",
            "目标AID",
            "序号",
        ]:
            with self.subTest(required_text=required_text):
                self.assertIn(required_text, serialized)
        self.assertNotIn("version", serialized)

    def test_table_parameter_descriptions_define_required_runtime_fields(self):
        specs = {item["name"]: item for item in self.functions}
        expected_fields = {
            "大厅服务 - 开始匹配": ["level_id", "game_mode", "score"],
            "大厅服务 - 局内私人副本": ["game_map_id", "level_id", "game_mode", "max_player"],
            "大厅服务 - 返回大厅": ["level_id", "game_mode", "max_player"],
        }
        for name, fields in expected_fields.items():
            description = specs[name].get("description", "")
            with self.subTest(name=name):
                for field in fields:
                    self.assertIn(field, description)
                self.assertNotIn("version", description)

    def test_private_dungeon_and_token_names_replace_old_split_merge_wording(self):
        serialized = json.dumps(
            {"functions": self.functions, "triggers": self.trigger_dsl["triggers"]},
            ensure_ascii=False,
        )
        self.assertIn("局内私人副本", serialized)
        self.assertIn("加入口令", serialized)
        self.assertIn("获取口令", serialized)
        for term in FORBIDDEN_USER_TERMS:
            with self.subTest(term=term):
                self.assertNotIn(term, serialized)

    def test_trigger_dsl_does_not_pin_current_project_event_id_or_function_id(self):
        serialized = json.dumps(self.trigger_dsl, ensure_ascii=False)
        forbidden_values = [
            "1876423410",
            "1263239224",
            "a1377fd18bfb11f1b9d919bc08ffd172",
        ]
        for value in forbidden_values:
            with self.subTest(value=value):
                self.assertNotIn(value, serialized)

    def test_eca_tools_do_not_include_project_specific_or_debug_leftovers(self):
        serialized = json.dumps(
            {"functions": self.functions, "triggers": self.trigger_dsl["triggers"]},
            ensure_ascii=False,
        )
        for value in [
            "188836",
            "默认人数 8",
            "p_count",
            "create_room",
            "start_ai",
            '"game_mode": 1001',
            '"game_mode": 1002',
            '"game_mode": 1003',
        ]:
            with self.subTest(value=value):
                self.assertNotIn(value, serialized)

    def test_trigger_dsl_uses_event_name_and_callback_data_parameter(self):
        values = list(walk_json(self.trigger_dsl))
        self.assertIn("大厅服务请求完成", values)
        self.assertIn("回调数据", values)
        self.assertIn("RECEIVE_CUSTOM_EVENT", values)
        self.assertNotIn("RECEIVE_CUSTOM_EVENT_NAME", values)

    def test_trigger_examples_pass_required_dynamic_arguments_and_match_request_id(self):
        triggers = {item["name"]: item for item in self.trigger_dsl["triggers"]}
        create_team = triggers["大厅服务 - 创建队伍测试"]
        create_team_serialized = json.dumps(create_team, ensure_ascii=False)
        self.assertIn('"args": [4]', create_team_serialized)
        self.assertIn("request_id", create_team_serialized)
        self.assertIn("创建队伍立即结果", create_team_serialized)
        self.assertIn("大厅服务请求完成", create_team_serialized)
        self.assertIn("回调数据", create_team_serialized)

    def test_trigger_examples_cover_latest_terminal_function_mappings(self):
        trigger_serialized = {
            trigger["name"]: json.dumps(trigger, ensure_ascii=False)
            for trigger in self.trigger_dsl["triggers"]
        }
        expected_examples = {
            "大厅服务 - 退出游戏": "大厅服务 - 退出游戏",
            "大厅服务 - 获取状态快照": "大厅服务 - 获取状态快照",
        }
        for label, function_name in expected_examples.items():
            with self.subTest(label=label):
                matches = [
                    trigger_name
                    for trigger_name, serialized in trigger_serialized.items()
                    if f'"name": "{function_name}"' in serialized
                ]
                self.assertEqual(1, len(matches), f"{label} 示例必须唯一映射到对应 ECA 函数")

    def test_trigger_examples_cover_required_dynamic_table_arguments(self):
        serialized = json.dumps(self.trigger_dsl, ensure_ascii=False)
        required_examples = {
            "大厅服务 - 开始匹配": ["level_id", "game_mode"],
            "大厅服务 - 局内私人副本": ["game_map_id", "level_id", "game_mode", "max_player"],
            "大厅服务 - 返回大厅": ["level_id", "game_mode", "max_player"],
        }
        for function_name, fields in required_examples.items():
            with self.subTest(function_name=function_name):
                self.assertIn(f'"name": "{function_name}"', serialized)
                for field in fields:
                    self.assertIn(field, serialized)
        private_dungeon_trigger = next(
            trigger for trigger in self.trigger_dsl["triggers"]
            if trigger["name"] == "大厅服务 - 局内私人副本测试"
        )
        private_dungeon_serialized = json.dumps(private_dungeon_trigger, ensure_ascii=False)
        self.assertNotIn("players", private_dungeon_serialized)
        self.assertNotIn("version", serialized)

    def test_async_trigger_examples_register_completion_event_and_compare_request_id(self):
        async_names = [
            "大厅服务 - 建立连接",
            "大厅服务 - 创建队伍",
            "大厅服务 - 开始匹配",
            "大厅服务 - 局内私人副本",
            "大厅服务 - 退出游戏",
        ]
        serialized_triggers = [
            json.dumps(trigger, ensure_ascii=False)
            for trigger in self.trigger_dsl["triggers"]
        ]
        for function_name in async_names:
            with self.subTest(function_name=function_name):
                matches = [
                    serialized
                    for serialized in serialized_triggers
                    if f'"name": "{function_name}"' in serialized
                ]
                self.assertEqual(1, len(matches), f"{function_name} 需要一个示例映射")
                example = matches[0]
                self.assertIn("大厅服务请求完成", example)
                self.assertIn("回调数据", example)
                self.assertIn("request_id", example)

    def test_return_lobby_example_is_request_only(self):
        trigger = next(
            trigger for trigger in self.trigger_dsl["triggers"]
            if trigger["name"] == "大厅服务 - 返回大厅测试"
        )
        serialized = json.dumps(trigger, ensure_ascii=False)
        self.assertNotIn("大厅服务请求完成", serialized)
        self.assertNotIn("request_id", serialized)
        self.assertNotIn("sub_triggers", trigger)
        self.assertNotIn("your_lobby_level_id", serialized)
        self.assertIn("your_lobby_engine_level_uuid", serialized)
        self.assertIn("accepted", serialized)
        self.assertIn("platform_requested", serialized)
        self.assertIn("实际成功以关卡切换为准", serialized)

    def test_entry_map_return_lobby_trigger_uses_real_engine_target_and_is_request_only(self):
        trigger = load_json(
            LOBBY_TEST_TRIGGER_ROOT
            / "大厅服务 - 返回大厅测试.json"
        )
        fields = {}
        for action in trigger["action"]:
            if action["action_type"] != "SET_TABLE_VALUE_1D":
                continue
            key_arg, value_arg = action["args_list"][1:3]
            fields[key_arg["args_list"][0]] = value_arg["args_list"][0]

        self.assertEqual(
            {
                "level_id": "81ad7554-7e6b-11f1-8f5c-c78cd393ba6e",
                "game_mode": 1001,
                "max_player": 1,
            },
            fields,
        )
        serialized = json.dumps(trigger, ensure_ascii=False)
        self.assertNotIn("request_id", serialized)
        self.assertNotIn("大厅服务请求完成", serialized)
        self.assertFalse(trigger.get("sub_trigger"))
        self.assertIn("platform_requested", serialized)

    def test_entry_map_private_dungeon_trigger_uses_real_cross_map_targets(self):
        trigger = load_json(
            LOBBY_TEST_TRIGGER_ROOT
            / "大厅服务 - 局内私人副本测试.json"
        )
        serialized = json.dumps(trigger, ensure_ascii=False)
        literal_fields = {}
        for action in trigger["action"]:
            if action["action_type"] != "SET_TABLE_VALUE_1D":
                continue
            key_arg, value_arg = action["args_list"][1:3]
            value = value_arg.get("args_list", [None])[0]
            if isinstance(value, (str, int)):
                literal_fields[key_arg["args_list"][0]] = value
        self.assertEqual(
            {
                "action": "private_dungeon",
                "level_id": "50377054694119407947881484918402159964",
                "engine_level_id": "25e6448f-7e73-11f1-88ae-03dc5a85955c",
                "game_mode": 1003,
                "team_game_mode": 1002,
                "max_player": 2,
            },
            literal_fields,
        )
        for expected in [
            '"game_map_id"',
            "状态快照立即结果",
            "06baf266d22b5844b236f6a8dea1828e",
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, serialized)
        self.assertNotIn("your_level_id", serialized)
        self.assertNotIn("your_game_map_id", serialized)
        self.assertNotIn("optional_custom_param", serialized)

    def test_trigger_examples_are_not_documenting_immediate_success_for_async_calls(self):
        serialized = json.dumps(self.trigger_dsl, ensure_ascii=False)
        forbidden_fragments = [
            "立即完成",
            "立刻完成",
            "立即成功",
            "立刻成功",
            "无需等待回调",
        ]
        for fragment in forbidden_fragments:
            with self.subTest(fragment=fragment):
                self.assertNotIn(fragment, serialized)

    def test_formal_ui_excludes_developer_only_functions(self):
        expected_ids = {
            load_json(path)["func_id"]
            for path in lobby_function_files("EntryMap")
        }
        used_ids = {
            node["call_function"]["func_id"]
            for dsl in (self.entry_ui_dsl, self.dungeon_ui_dsl)
            for node in walk_json(dsl)
            if isinstance(node, dict) and "call_function" in node
        }
        developer_only_names = {
            "大厅服务 - 建立连接",
            "大厅服务 - 设置匹配分数",
            "大厅服务 - 获取队伍信息",
            "大厅服务 - 获取玩家信息",
            "大厅服务 - 刷新玩家信息",
        }
        developer_only_ids = {
            load_json(path)["func_id"]
            for path in lobby_function_files("EntryMap")
            if path.stem in developer_only_names
        }
        self.assertEqual(expected_ids - developer_only_ids, used_ids)
        self.assertEqual(21, len(used_ids))

    def test_entry_ui_contains_semantic_rows_and_no_developer_controls(self):
        tree = load_json(ROOT / "ui_tree" / "EcaLobbyExample_Tree.json")
        paths = set(ui_paths(tree))
        self.assertIn(
            "EcaLobbyExample.action_panel.button_same_level_private_dungeon",
            paths,
        )
        for index in range(1, 5):
            self.assertIn(f"EcaLobbyExample.team_panel.member_row_{index}", paths)
            self.assertIn(
                f"EcaLobbyExample.team_panel.member_row_{index}.button_transfer_{index}",
                paths,
            )
            self.assertIn(
                f"EcaLobbyExample.team_panel.member_row_{index}.button_kick_{index}",
                paths,
            )
            for field in ["index", "name", "aid", "state", "current"]:
                self.assertIn(
                    f"EcaLobbyExample.team_panel.member_row_{index}.label_member_{field}_{index}",
                    paths,
                )
        self.assertNotIn("EcaLobbyExample.developer_panel", paths)
        self.assertNotIn("EcaLobbyExample.button_developer", paths)
        self.assertIn(
            "EcaLobbyExample.exit_confirm_overlay.exit_confirm_panel.button_exit_confirm",
            paths,
        )

    def test_every_ui_path_used_by_dsl_exists_in_its_map_tree(self):
        cases = [
            (
                self.entry_ui_dsl,
                load_json(ROOT / "ui_tree" / "EcaLobbyExample_Tree.json"),
            ),
            (
                self.dungeon_ui_dsl,
                load_json(ROOT / "ui_tree" / "EcaDungeonExample_Tree.json"),
            ),
        ]
        for dsl, tree in cases:
            root_name = tree["name"]
            available = set(ui_paths(tree))
            referenced = {
                f"{root_name}.{node[3]}" if node[3] else root_name
                for node in walk_json(dsl)
                if isinstance(node, list)
                and len(node) == 4
                and node[0] == "GET_UI_COMP_BY_PATH"
            }
            with self.subTest(map_name=dsl["map"]):
                self.assertTrue(referenced)
                self.assertEqual(set(), referenced - available)

    def test_async_ui_triggers_filter_completion_without_overriding_snapshot_permissions(self):
        triggers = [
            trigger
            for dsl in (self.entry_ui_dsl, self.dungeon_ui_dsl)
            for trigger in dsl["triggers"]
            if trigger.get("sub_triggers")
        ]
        self.assertGreaterEqual(len(triggers), 13)
        for trigger in triggers:
            serialized = json.dumps(trigger, ensure_ascii=False)
            with self.subTest(trigger=trigger["name"]):
                self.assertNotIn("SET_UI_COMP_ENABLE", serialized)
                self.assertIn("大厅服务请求完成", serialized)
                self.assertIn("回调数据", serialized)
                self.assertIn("request_id", serialized)
                self.assertIn("UNREG_TRIGGER", serialized)

    def test_member_management_buttons_share_one_dynamic_trigger_per_action(self):
        cases = [
            {
                "trigger_name": "ECA大厅UI - 转移队长",
                "button_prefix": "button_transfer_",
                "event_name": "eca_lobby_transfer",
                "function_id": "83b1f3fc8b595bdfbd913e7b09695ca5",
                "trigger_id": 1942000006,
                "child_id": 1942100005,
            },
            {
                "trigger_name": "ECA大厅UI - 移出队员",
                "button_prefix": "button_kick_",
                "event_name": "eca_lobby_kick",
                "function_id": "54499d6fa32853e1870acd409a6515ea",
                "trigger_id": 1942000007,
                "child_id": 1942100006,
            },
        ]
        trigger_names = [trigger["name"] for trigger in self.entry_ui_dsl["triggers"]]
        initializer = next(
            trigger
            for trigger in self.entry_ui_dsl["triggers"]
            if trigger["name"] == "ECA大厅UI - 初始化"
        )
        trigger_root = LOBBY_UI_TRIGGER_ROOT
        for case in cases:
            trigger_name = case["trigger_name"]
            with self.subTest(trigger=trigger_name):
                self.assertEqual(1, trigger_names.count(trigger_name))
                for index in range(1, 5):
                    self.assertNotIn(f"{trigger_name}{index}", trigger_names)

                bindings = [
                    node
                    for node in walk_json(initializer)
                    if isinstance(node, list)
                    and len(node) == 4
                    and node[0] == "CREATE_UI_COMP_EVENT_EX_EX"
                    and isinstance(node[1], list)
                    and len(node[1]) == 4
                    and node[1][0] == "GET_UI_COMP_BY_PATH"
                    and case["button_prefix"] in node[1][3]
                ]
                self.assertEqual(4, len(bindings))
                self.assertEqual(
                    {case["event_name"]},
                    {binding[3] for binding in bindings},
                )

                trigger = next(
                    trigger
                    for trigger in self.entry_ui_dsl["triggers"]
                    if trigger["name"] == trigger_name
                )
                serialized = json.dumps(trigger, ensure_ascii=False)
                for expected in [
                    "GET_UI_COMP_FROM_EVENT",
                    "GET_UI_COMP_NAME",
                    "STR_REPLACE",
                    case["button_prefix"],
                    "STR_TO_INT",
                    "ff8d602fd5235532934fcc588f045d96",
                    case["function_id"],
                    "request_id",
                    "UNREG_TRIGGER",
                ]:
                    self.assertIn(expected, serialized)
                self.assertEqual(1, len(trigger.get("sub_triggers", [])))

                generated_path = trigger_root / f"{trigger_name}.json"
                self.assertTrue(generated_path.is_file())
                for index in range(1, 5):
                    self.assertFalse(
                        (trigger_root / f"{trigger_name}{index}.json").exists()
                    )

                generated = load_json(generated_path)
                self.assertEqual(case["trigger_id"], generated["trigger_id"])
                child_id = str(case["child_id"])
                self.assertEqual([child_id], list(generated.get("sub_trigger", {})))
                child = generated["sub_trigger"][child_id]
                self.assertEqual(case["trigger_id"], child["p_trigger_id"])
                self.assertFalse(child["enabled"])
                self.assertIn(child_id, json.dumps(generated["action"]))

    def test_generated_button_enable_actions_use_literal_boolean_values(self):
        initializers = [
            load_json(LOBBY_UI_TRIGGER_ROOT / "ECA大厅UI - 初始化.json"),
            load_json(DUNGEON_UI_TRIGGER_ROOT / "ECA副本UI - 初始化.json"),
        ]
        enable_actions = [
            node
            for initializer in initializers
            for node in walk_json(initializer)
            if isinstance(node, dict) and node.get("action_type") == "SET_UI_COMP_ENABLE"
        ]
        self.assertGreaterEqual(len(enable_actions), 18)
        for action in enable_actions:
            value = action["args_list"][2]
            with self.subTest(element_id=action["element_id"]):
                self.assertEqual(1, value.get("sub_type"))
                self.assertEqual(1, len(value.get("args_list", [])))
                self.assertIsInstance(value["args_list"][0], bool)

    def test_cross_map_ui_requests_do_not_register_fake_completion_callbacks(self):
        names = {
            "ECA大厅UI - 局内私人副本",
            "ECA大厅UI - 同关卡不同模式",
            "ECA大厅UI - 加入口令",
            "ECA副本UI - 返回大厅",
        }
        triggers = {
            trigger["name"]: trigger
            for dsl in (self.entry_ui_dsl, self.dungeon_ui_dsl)
            for trigger in dsl["triggers"]
            if trigger["name"] in names
        }
        self.assertEqual(names, set(triggers))
        for name, trigger in triggers.items():
            serialized = json.dumps(trigger, ensure_ascii=False)
            with self.subTest(trigger=name):
                self.assertNotIn("sub_triggers", trigger)
                self.assertNotIn("大厅服务请求完成", serialized)
                self.assertNotIn("request_id", serialized)
                self.assertIn("以切图结果为准", serialized)

    def test_same_level_private_dungeon_uses_entry_map_mode_1003(self):
        trigger = next(
            item
            for item in self.entry_ui_dsl["triggers"]
            if item["name"] == "ECA大厅UI - 同关卡不同模式"
        )
        serialized = json.dumps(trigger, ensure_ascii=False)
        for expected in [
            '"level_id", "172371058548994502264384971909138463342"',
            '"engine_level_id", "81ad7554-7e6b-11f1-8f5c-c78cd393ba6e"',
            '"game_mode", 1003',
            '"team_game_mode", 1003',
            '"max_player", 2',
            "eca_lobby_same_level_private_dungeon",
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, serialized)

        dungeon = load_json(ROOT / "dungeon.json")
        self.assertEqual(
            {
                "can_add_in_time": 120,
                "enable_private": 1,
                "enable_public": 0,
                "max_player_num": 8,
            },
            dungeon["172371058548994502264384971909138463342"]["game_modes"]["1003"],
        )

    def test_generated_ui_triggers_keep_editor_ui_type_ids_and_timer_metadata(self):
        generated = [
            load_json(path)
            for trigger_root, pattern in [
                (LOBBY_UI_TRIGGER_ROOT, "ECA大厅UI - *.json"),
                (DUNGEON_UI_TRIGGER_ROOT, "ECA副本UI - *.json"),
            ]
            for path in trigger_root.glob(pattern)
        ]
        self.assertEqual(24, len(generated))
        all_nodes = [node for trigger in generated for node in walk_json(trigger)]
        ui_args = [
            node
            for node in all_nodes
            if isinstance(node, dict)
            and node.get("sub_type") == "GET_UI_COMP_BY_PATH"
        ]
        event_args = [
            node
            for node in all_nodes
            if isinstance(node, dict) and node.get("sub_type") == "STR_TO_UI_EVENT"
        ]
        event_type_args = [
            node["args_list"][1]
            for node in all_nodes
            if isinstance(node, dict)
            and node.get("action_type") == "CREATE_UI_COMP_EVENT_EX_EX"
        ]
        boolean_table_args = [
            node
            for node in all_nodes
            if isinstance(node, dict)
            and node.get("sub_type") == "GET_BOOLEAN_TABLE_VAR_1D"
        ]
        timers = [
            node
            for node in all_nodes
            if isinstance(node, dict)
            and node.get("action_type") == "RUN_LOOP_TIMER_NO_SAVE"
        ]
        self.assertTrue(ui_args)
        self.assertTrue(event_args)
        self.assertTrue(event_type_args)
        self.assertTrue(boolean_table_args)
        self.assertEqual({100070}, {node["arg_type"] for node in ui_args})
        self.assertEqual({100067}, {node["arg_type"] for node in event_args})
        self.assertEqual({100072}, {node["arg_type"] for node in event_type_args})
        self.assertEqual({100001}, {node["arg_type"] for node in boolean_table_args})
        self.assertEqual(2, len(timers))
        for timer in timers:
            self.assertEqual(
                {"__tuple__": True, "items": [{}, {}]},
                timer.get("local_var"),
            )

    def test_entry_map_owns_both_ui_contexts_and_all_ui_triggers(self):
        self.assertEqual("EntryMap", self.entry_ui_dsl["map"])
        self.assertEqual("EntryMap", self.dungeon_ui_dsl["map"])
        self.assertTrue(
            (ROOT / "maps" / "EntryMap" / "ui" / "EcaLobbyExample.json").is_file()
        )
        self.assertTrue(
            (ROOT / "maps" / "EntryMap" / "ui" / "EcaDungeonExample.json").is_file()
        )
        self.assertFalse(
            (ROOT / "maps" / "MapName001" / "ui" / "EcaDungeonExample.json").exists()
        )
        panel_groups = load_json(
            ROOT / "maps" / "EntryMap" / "editor" / "uipaneltreegroupinfo.json"
        )
        custom_panels = {
            item["items"][1]: item["items"][0]
            for item in panel_groups[0]["group"]
        }
        self.assertEqual(
            {
                "EcaLobbyExample": "c3eb744a-f544-45d2-8e24-a2e279a67662",
                "EcaDungeonExample": "908f7d63-a40d-42e1-8ed4-b076b01095a2",
            },
            {
                name: custom_panels[name]
                for name in ("EcaLobbyExample", "EcaDungeonExample")
            },
        )
        child_trigger_root = ROOT / "maps" / "MapName001" / "global_trigger" / "trigger"
        self.assertEqual(16, len(list(LOBBY_UI_TRIGGER_ROOT.glob("ECA大厅UI - *.json"))))
        self.assertEqual(8, len(list(DUNGEON_UI_TRIGGER_ROOT.glob("ECA副本UI - *.json"))))
        self.assertEqual([], list(child_trigger_root.glob("ECA副本UI - *.json")))

    def test_entry_map_groups_generated_triggers_by_domain(self):
        self.assertEqual(["大厅服务", "大厅UI"], self.entry_ui_dsl["folder"])
        self.assertEqual(["大厅服务", "副本UI"], self.dungeon_ui_dsl["folder"])
        self.assertEqual(["大厅服务", "接口测试"], self.trigger_dsl["folder"])
        self.assertEqual(["大厅服务", "接口测试"], self.entry_trigger_dsl["folder"])
        self.assertEqual(
            ["大厅服务", "接口测试"],
            self.status_trigger_dsl["folder"],
        )

        root_index = load_json(TRIGGER_ROOT / "index.txt")
        self.assertEqual(
            {"New trigger.json", "UI.folder", "大厅服务.folder"},
            set(root_index),
        )
        self.assertEqual(
            {"大厅UI.folder", "副本UI.folder", "接口测试.folder"},
            set(load_json(LOBBY_TRIGGER_ROOT / "index.txt")),
        )

        expected_by_folder = {
            LOBBY_UI_TRIGGER_ROOT: {
                f"{trigger['name']}.json"
                for trigger in self.entry_ui_dsl["triggers"]
            },
            DUNGEON_UI_TRIGGER_ROOT: {
                f"{trigger['name']}.json"
                for trigger in self.dungeon_ui_dsl["triggers"]
            },
            LOBBY_TEST_TRIGGER_ROOT: {
                f"{trigger['name']}.json"
                for dsl in (self.entry_trigger_dsl, self.status_trigger_dsl)
                for trigger in dsl["triggers"]
            },
        }
        for folder, expected in expected_by_folder.items():
            with self.subTest(folder=folder.name):
                self.assertEqual(expected, set(load_json(folder / "index.txt")))
                self.assertEqual(
                    expected,
                    {path.name for path in folder.glob("*.json")},
                )

        root_business_files = [
            path.name
            for path in TRIGGER_ROOT.glob("*.json")
            if path.name.startswith(("ECA", "大厅服务 - "))
        ]
        self.assertEqual([], root_business_files)

    def test_entry_map_service_test_dsl_is_current(self):
        result = subprocess.run(
            [sys.executable, "tools/eca/build_entry_map_service_tests.py", "--check"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_ui_initializers_use_exact_lobby_runtime_context(self):
        expected = [
            [
                "OR",
                [
                    [
                        "STRING_COMPARE",
                        ["ANY_VAR_TO_STR", ["GET_GAME_MODE"]],
                        "==",
                        "0",
                    ],
                    [
                        "STRING_COMPARE",
                        ["ANY_VAR_TO_STR", ["GET_GAME_MODE"]],
                        "==",
                        "1001",
                    ],
                ],
            ],
        ]
        for dsl, name in [
            (self.entry_ui_dsl, "ECA大厅UI - 初始化"),
            (self.dungeon_ui_dsl, "ECA副本UI - 初始化"),
        ]:
            trigger = next(item for item in dsl["triggers"] if item["name"] == name)
            with self.subTest(trigger=name):
                self.assertEqual("IF_THEN_ELSE", trigger["action"][0][0])
                self.assertEqual(expected, trigger["action"][0][1])

    def test_ui_initializers_only_activate_the_matching_context(self):
        init_actions = {}
        for dsl, name in [
            (self.entry_ui_dsl, "ECA大厅UI - 初始化"),
            (self.dungeon_ui_dsl, "ECA副本UI - 初始化"),
        ]:
            trigger = next(item for item in dsl["triggers"] if item["name"] == name)
            init_actions[name] = trigger["action"][0]

        def visibility(branch):
            return {
                action[3][2]: action[2]
                for action in branch
                if action[0] == "SET_UI_COMP_VISIBLE" and action[3][3] == ""
            }

        def timer_count(branch):
            return sum(action[0] == "RUN_LOOP_TIMER_NO_SAVE" for action in branch)

        lobby_init = init_actions["ECA大厅UI - 初始化"]
        dungeon_init = init_actions["ECA副本UI - 初始化"]
        self.assertEqual(
            {
                "c3eb744a-f544-45d2-8e24-a2e279a67662": True,
                "908f7d63-a40d-42e1-8ed4-b076b01095a2": False,
            },
            visibility(lobby_init[2]),
        )
        self.assertEqual(
            {"c3eb744a-f544-45d2-8e24-a2e279a67662": False},
            visibility(lobby_init[3]),
        )
        self.assertEqual(
            {"908f7d63-a40d-42e1-8ed4-b076b01095a2": False},
            visibility(dungeon_init[2]),
        )
        self.assertEqual(
            {
                "c3eb744a-f544-45d2-8e24-a2e279a67662": False,
                "908f7d63-a40d-42e1-8ed4-b076b01095a2": True,
            },
            visibility(dungeon_init[3]),
        )
        self.assertEqual((1, 0), (timer_count(lobby_init[2]), timer_count(lobby_init[3])))
        self.assertEqual((0, 1), (timer_count(dungeon_init[2]), timer_count(dungeon_init[3])))

    def test_generated_runtime_context_only_compares_converted_mode_strings(self):
        generated = [
            load_json(
                LOBBY_UI_TRIGGER_ROOT
                / name
            )
            for name in ["ECA大厅UI - 初始化.json"]
        ] + [
            load_json(DUNGEON_UI_TRIGGER_ROOT / "ECA副本UI - 初始化.json")
        ]
        for trigger in generated:
            conditions = trigger["action"][0]["args_list"][0]["args_list"]
            self.assertEqual(1, len(conditions))
            mode_or = conditions[0]
            with self.subTest(trigger=trigger["trigger_name"]):
                self.assertEqual("OR", mode_or["condition_type"])
                mode_compares = mode_or["args_list"][0]["args_list"]
                self.assertEqual(100021, mode_or["args_list"][0]["arg_type"])
                self.assertEqual(["0", "1001"], [
                    item["args_list"][2]["args_list"][0]
                    for item in mode_compares
                ])
                for mode_compare in mode_compares:
                    self.assertEqual("STRING_COMPARE", mode_compare["condition_type"])
                    self.assertEqual(
                        [100003, 100035, 100003],
                        [arg["arg_type"] for arg in mode_compare["args_list"]],
                    )
                    self.assertEqual(
                        "ANY_VAR_TO_STR",
                        mode_compare["args_list"][0]["sub_type"],
                    )
                    game_mode_arg = mode_compare["args_list"][0]["args_list"][0]
                    self.assertEqual(100505, game_mode_arg["arg_type"])
                    self.assertEqual("GET_GAME_MODE", game_mode_arg["sub_type"])

                invalid_zero_compares = [
                    node
                    for node in walk_json(trigger)
                    if isinstance(node, dict)
                    and node.get("condition_type") == "GAME_MODE_COMPARE"
                    and any(
                        arg.get("args_list") == [0]
                        for arg in node.get("args_list", [])
                        if isinstance(arg, dict)
                    )
                ]
                self.assertEqual([], invalid_zero_compares)
                self.assertNotIn("GET_CURRENT_LEVEL", json.dumps(conditions))
                self.assertNotIn("ANY_COMPARE", json.dumps(conditions))

    def test_lua_test_ui_is_preserved_but_disabled_by_default(self):
        for map_name in MAP_NAMES:
            source = (ROOT / "maps" / map_name / "script" / "main.lua").read_text(
                encoding="utf-8"
            )
            with self.subTest(map_name=map_name):
                self.assertIn("local ENABLE_LUA_TEST_UI = false", source)
                self.assertIn("include 'test_ui'", source)
                self.assertIn("if ENABLE_LUA_TEST_UI then", source)

    def test_join_token_diagnostics_are_redacted_in_both_maps(self):
        for map_name in MAP_NAMES:
            source = (
                ROOT
                / "maps"
                / map_name
                / "script"
                / "y3"
                / "game"
                / "lobby"
                / "init.lua"
            ).read_text(encoding="utf-8")
            with self.subTest(map_name=map_name):
                self.assertIn("加入口令请求 | token=<redacted>", source)
                self.assertNotIn("加入口令请求 | token=' .. token", source)

    def test_eca_ui_uses_the_same_image_assets_as_lua_test_ui(self):
        lua_source = (
            ROOT / "maps" / "EntryMap" / "script" / "test_ui.lua"
        ).read_text(encoding="utf-8")
        for resource_id in range(134217729, 134217745):
            self.assertIn(str(resource_id), lua_source)
        self.assertIn("local BACKDROP_IMAGE = 134230328", lua_source)

        ui_docs = [
            load_json(ROOT / "maps" / "EntryMap" / "ui" / "EcaLobbyExample.json"),
            load_json(
                ROOT / "maps" / "EntryMap" / "ui" / "EcaDungeonExample.json"
            ),
        ]
        buttons = [
            node
            for doc in ui_docs
            for node in walk_json(doc)
            if isinstance(node, dict) and node.get("type") == 1
        ]
        images = {
            node["name"]: node
            for doc in ui_docs
            for node in walk_json(doc)
            if isinstance(node, dict) and node.get("type") == 4
        }

        expected_button_assets = {
            "normal": [134217733, 134217734, 134217735, 134217736],
            "primary": [134217737, 134217738, 134217739, 134217740],
            "danger": [134217741, 134217742, 134217743, 134217744],
        }
        for button in buttons:
            name = button["name"]
            variant = "normal"
            if name == "button_private_dungeon":
                variant = "primary"
            elif name in {"button_exit", "button_exit_confirm", "button_dismiss_team"} or name.startswith(
                "button_kick_"
            ):
                variant = "danger"
            actual = [
                button["normal_picture"],
                button["suspend_picture"],
                button["press_picture"],
                button["disabled_picture"],
            ]
            with self.subTest(button=name):
                self.assertEqual(expected_button_assets[variant], actual)
                for status in ("normal", "suspend", "press", "disabled"):
                    self.assertEqual(
                        {"__tuple__": True, "items": [8.0, 8.0, 8.0, 8.0]},
                        button[f"{status}_cap_insets"],
                    )

        self.assertEqual(134230328, images["image_backdrop"]["image"])
        self.assertEqual(109589, images["exit_confirm_overlay_bg"]["image"])
        for name in [
            "chat_panel_bg",
            "team_panel_bg",
            "action_panel_bg",
            "status_panel_bg",
            "header_panel_bg",
            "dungeon_chat_panel_bg",
            "dungeon_status_panel_bg",
        ]:
            self.assertEqual(134217729, images[name]["image"])
        for name in [
            "member_row_1_bg",
            "member_row_2_bg",
            "member_row_3_bg",
            "member_row_4_bg",
            "status_mode_bg",
            "status_player_bg",
            "status_bob_bg",
            "status_login_bg",
            "status_team_bg",
            "status_count_bg",
            "status_match_bg",
            "status_launch_bg",
        ]:
            self.assertEqual(134217730, images[name]["image"])
        self.assertEqual(134217731, images["exit_confirm_panel_bg"]["image"])
        for name in [
            "image_input_chat_bg",
            "image_input_team_id_bg",
            "image_input_token_bg",
        ]:
            self.assertEqual(134217732, images[name]["image"])


if __name__ == "__main__":
    unittest.main()
