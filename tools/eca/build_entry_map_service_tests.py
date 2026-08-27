# -*- coding: utf-8 -*-
"""Build EntryMap-specific ECA service tests from the reusable example DSL."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools" / "eca" / "lobby_service_tests.json"
OUTPUT = ROOT / "tools" / "eca" / "lobby_service_entry_map_tests.json"

PRIVATE_LEVEL_ID = "50377054694119407947881484918402159964"
PRIVATE_LEVEL_UUID = "25e6448f-7e73-11f1-88ae-03dc5a85955c"
LOBBY_LEVEL_UUID = "81ad7554-7e6b-11f1-8f5c-c78cd393ba6e"


def table_var(name: str) -> dict:
    return {"var": name, "type": "TABLE"}


def set_field(table_name: str, key: str, value) -> list:
    return ["SET_TABLE_VALUE_1D", table_var(table_name), key, value]


def trigger_by_name(dsl: dict, name: str) -> dict:
    return next(trigger for trigger in dsl["triggers"] if trigger["name"] == name)


def build_dsl(source: dict) -> dict:
    dsl = copy.deepcopy(source)
    dsl["folder"] = ["大厅服务", "接口测试"]

    private_dungeon = trigger_by_name(dsl, "大厅服务 - 局内私人副本测试")
    private_dungeon["action"] = [
        ["SET_VARIABLE", table_var("副本参数"), ["GET_NEW_TABLE"]],
        {
            "call_function": {
                "func_id": "06baf266d22b5844b236f6a8dea1828e",
                "name": "大厅服务 - 获取状态快照",
                "args": [],
                "returns": [table_var("状态快照立即结果")],
            }
        },
        set_field("副本参数", "action", "private_dungeon"),
        set_field("副本参数", "level_id", PRIVATE_LEVEL_ID),
        set_field("副本参数", "engine_level_id", PRIVATE_LEVEL_UUID),
        set_field(
            "副本参数",
            "game_map_id",
            [
                "GET_STRING_TABLE_VAR_1D",
                [
                    "GET_TABLE_TABLE_VAR_1D",
                    table_var("状态快照立即结果"),
                    "result_data",
                ],
                "game_map_id",
            ],
        ),
        set_field("副本参数", "game_mode", 1003),
        set_field("副本参数", "team_game_mode", 1002),
        set_field("副本参数", "max_player", 2),
        ["PRINT_MESSAGE_ACTION_TO_DIALOG", 3, "调用大厅服务 - 局内私人副本；立即结果如下"],
        {
            "call_function": {
                "func_id": "0d827eca2ea0531c83ce1d8cff4db2f1",
                "name": "大厅服务 - 局内私人副本",
                "args": [table_var("副本参数")],
                "returns": [table_var("局内私人副本立即结果")],
            }
        },
        ["DUMP_TABLE", table_var("局内私人副本立即结果")],
        [
            "IF_THEN_ELSE",
            [
                [
                    "STRING_COMPARE",
                    [
                        "GET_STRING_TABLE_VAR_1D",
                        table_var("局内私人副本立即结果"),
                        "request_id",
                    ],
                    "!=",
                    "",
                ]
            ],
            [{"register_sub_trigger": "大厅服务 - 局内私人副本完成回调"}],
            [["PRINT_MESSAGE_ACTION_TO_DIALOG", 3, "局内私人副本请求未受理，请查看立即结果"]],
        ],
    ]

    return_lobby = trigger_by_name(dsl, "大厅服务 - 返回大厅测试")
    return_lobby["action"] = [
        ["SET_VARIABLE", table_var("返回大厅参数"), ["GET_NEW_TABLE"]],
        set_field("返回大厅参数", "level_id", LOBBY_LEVEL_UUID),
        set_field("返回大厅参数", "game_mode", 1001),
        set_field("返回大厅参数", "max_player", 1),
        ["PRINT_MESSAGE_ACTION_TO_DIALOG", 3, "调用大厅服务 - 返回大厅；立即结果如下"],
        {
            "call_function": {
                "func_id": "1fec80e8afe657b88e0fdd00a336fe05",
                "name": "大厅服务 - 返回大厅",
                "args": [table_var("返回大厅参数")],
                "returns": [table_var("返回大厅立即结果")],
            }
        },
        ["DUMP_TABLE", table_var("返回大厅立即结果")],
        [
            "PRINT_MESSAGE_ACTION_TO_DIALOG",
            3,
            "返回大厅不产生完成事件；请检查 accepted 和 result_data.platform_requested，实际成功以关卡切换为准",
        ],
    ]
    return dsl


def render(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, indent=4) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    expected = render(build_dsl(source))
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != expected:
            raise SystemExit(f"outdated generated file: {OUTPUT}")
        return 0

    OUTPUT.write_text(expected, encoding="utf-8")
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
