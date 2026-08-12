# -*- coding: utf-8 -*-
from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FUNCTION_DSL = ROOT / "tools" / "eca" / "lobby_service_functions.json"
TRIGGER_DSL = ROOT / "tools" / "eca" / "lobby_service_tests.json"
STATUS_TRIGGER_DSL = ROOT / "tools" / "eca" / "lobby_status_event_listener.json"
MAP_NAMES = ["EntryMap", "MapName001"]

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


class LobbyEcaJsonTests(unittest.TestCase):
    def setUp(self):
        self.function_dsl = load_json(FUNCTION_DSL)
        self.trigger_dsl = load_json(TRIGGER_DSL)
        self.status_trigger_dsl = load_json(STATUS_TRIGGER_DSL)
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
            ROOT
            / "maps"
            / "EntryMap"
            / "global_trigger"
            / "trigger"
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
            "大厅服务 - 返回大厅",
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


if __name__ == "__main__":
    unittest.main()
