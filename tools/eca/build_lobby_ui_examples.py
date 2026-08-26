# -*- coding: utf-8 -*-
"""Build compact ECA DSL files for the lobby example UI on both maps."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ENTRY_DSL = ROOT / "tools" / "eca" / "lobby_ui_entry_map.json"
DUNGEON_DSL = ROOT / "tools" / "eca" / "lobby_ui_dungeon_map.json"

ENTRY_ROOT = "c3eb744a-f544-45d2-8e24-a2e279a67662"
DUNGEON_ROOT = "908f7d63-a40d-42e1-8ed4-b076b01095a2"

FUNCTIONS = {
    "connect": "2a405018f61e54659d17a44122db0379",
    "connection": "fb4e6115da4b5f02b2dcf819cfd1f642",
    "score": "b5c349b3c7685d6b83ff25ccf0e1b672",
    "create_team": "c4c20f402758558687a6ee8ef68aca42",
    "join_team": "54060a9631fc543a8c780fe4bb5c4c15",
    "leave_team": "277e96944b0f5adfb51734662a67fc09",
    "dismiss_team": "2068174b8878529e951c06a86968e453",
    "transfer": "83b1f3fc8b595bdfbd913e7b09695ca5",
    "kick": "54499d6fa32853e1870acd409a6515ea",
    "members": "98f17b779b50566496a5175924ec5036",
    "start_match": "98f2d6a6a7195c03baa1606d67537034",
    "cancel_match": "fcd89f79856a5272ae977c11e60c2fdb",
    "team_chat": "a4b886695cfd53e6ba30adc15025c5bb",
    "world_chat": "45f48cac073155d38ca8dc7edc934517",
    "chat_history": "403f34876b6854779906e8855b689305",
    "private_dungeon": "0d827eca2ea0531c83ce1d8cff4db2f1",
    "join_token": "74f227e953815cc8992ed2935dbe600e",
    "token": "da0b1d8bb1f354ec8b4f91fca5c8c653",
    "return_lobby": "1fec80e8afe657b88e0fdd00a336fe05",
    "exit": "f384a7cfa22959a09b7ea36e9ddbff86",
    "snapshot": "06baf266d22b5844b236f6a8dea1828e",
    "chat_message": "c4c12fda3fb251f88eda0279bbf6b4ed",
    "member": "ff8d602fd5235532934fcc588f045d96",
    "team_info": "6f30cca1e4ca5988a85a195b2987e7cc",
    "player_info": "7f7cc39d015d5299b896508e49870ec9",
    "refresh_player": "ff7679dbd754547d986ab8c0dd9fd604",
}

MATCH_LEVEL_ID = "50377054694119407947881484918402159964"
PRIVATE_LEVEL_UUID = "25e6448f-7e73-11f1-88ae-03dc5a85955c"
LOBBY_LEVEL_UUID = "81ad7554-7e6b-11f1-8f5c-c78cd393ba6e"


class Ids:
    def __init__(self, parent: int, child: int) -> None:
        self.parent = parent
        self.child = child

    def next_parent(self) -> int:
        self.parent += 1
        return self.parent

    def next_child(self) -> int:
        self.child += 1
        return self.child


def player(local: bool = False):
    return ["GET_CLIENT_ROLE"] if local else ["TRIGGER_PLAYER"]


def ui(root: str, path: str, local: bool = False):
    return ["GET_UI_COMP_BY_PATH", player(local), root, path]


def table_var(name: str):
    return {"var": name, "type": "TABLE"}


def table_field(source, key: str):
    return ["GET_TABLE_TABLE_VAR_1D", source, key]


def string_field(source, key: str):
    return ["GET_STRING_TABLE_VAR_1D", source, key]


def integer_field(source, key: str):
    return ["GET_INTEGER_TABLE_VAR_1D", source, key]


def boolean_field(source, key: str):
    return ["GET_BOOLEAN_TABLE_VAR_1D", source, key]


def result_data(name: str):
    return table_field(table_var(name), "result_data")


def custom_payload():
    return ["GET_CUS_EVENT_PARAM", "回调数据"]


def join_text(*parts):
    values = [part for part in parts if part is not None]
    if not values:
        return ""
    value = values[-1]
    for part in reversed(values[:-1]):
        value = ["STR_JOIN", part, value]
    return value


def as_text(value):
    return ["ANY_VAR_TO_STR", value]


def set_text(root: str, path: str, value, local: bool = False):
    return ["SET_UI_COMP_TEXT", player(local), ui(root, path, local), value]


def set_enabled(root: str, path: str, enabled: bool, local: bool = False):
    return ["SET_UI_COMP_ENABLE", player(local), ui(root, path, local), enabled]


def set_visible(root: str, path: str, visible, local: bool = False):
    return ["SET_UI_COMP_VISIBLE", player(local), visible, ui(root, path, local)]


def call(key: str, result: str, args=None, optional_args=None):
    spec = {
        "func_id": FUNCTIONS[key],
        "args": args or [],
        "returns": [{"var": result, "type": "TABLE"}],
    }
    if optional_args is not None:
        spec["optional_args"] = optional_args
    return {"call_function": spec}


def event_trigger(name: str):
    return ["TRIGGER_COMPONENT_EVENT", ["STR_TO_UI_EVENT", name]]


def register_event(root: str, path: str, event_name: str):
    return ["CREATE_UI_COMP_EVENT_EX_EX", ui(root, path, local=True), 1, event_name]


def dump_or_redact(value, redacted: bool):
    if redacted:
        return [["PRINT_MESSAGE_ACTION_TO_DIALOG", 3, "[ECA Lobby] 结果包含敏感字段，详细内容已省略"]]
    return [["DUMP_TABLE", value]]


def async_trigger(
    ids: Ids,
    *,
    name: str,
    event_name: str,
    root: str,
    button_path: str,
    result_path: str,
    function_key: str,
    args=None,
    optional_args=None,
    pre_actions=None,
    accepted_actions=None,
    redacted: bool = False,
):
    result_name = f"{name}立即结果"
    callback_name = f"{name}完成回调"
    result_ref = table_var(result_name)
    log_actions = dump_or_redact(result_ref, redacted)
    callback_log = dump_or_redact(custom_payload(), redacted)
    actions = [
        set_enabled(root, button_path, False),
        set_text(root, result_path, f"{name}：处理中"),
        *(pre_actions or []),
        call(function_key, result_name, args, optional_args),
        [
            "IF_THEN_ELSE",
            [["BOOL_COMPARE", boolean_field(result_ref, "accepted"), "==", True]],
            [
                *(accepted_actions or []),
                [
                    "IF_THEN_ELSE",
                    [["STRING_COMPARE", string_field(result_ref, "request_id"), "!=", ""]],
                    [
                        set_text(root, result_path, f"{name}：请求已受理"),
                        {"register_sub_trigger": callback_name},
                    ],
                    [
                        set_enabled(root, button_path, True),
                        set_text(root, result_path, f"{name}：同步完成"),
                        *log_actions,
                    ],
                ],
            ],
            [
                set_enabled(root, button_path, True),
                set_text(root, result_path, f"{name}：失败，请查看日志"),
                *log_actions,
            ],
        ],
    ]
    callback = {
        "name": callback_name,
        "id": ids.next_child(),
        "event": [["RECEIVE_CUSTOM_EVENT", "大厅服务请求完成"]],
        "action": [
            [
                "IF_THEN_ELSE",
                [[
                    "STRING_COMPARE",
                    string_field(custom_payload(), "request_id"),
                    "==",
                    string_field(result_ref, "request_id"),
                ]],
                [
                    set_enabled(root, button_path, True),
                    [
                        "IF_THEN_ELSE",
                        [["BOOL_COMPARE", boolean_field(custom_payload(), "success"), "==", True]],
                        [set_text(root, result_path, f"{name}：操作成功")],
                        [set_text(root, result_path, f"{name}：失败，请查看日志")],
                    ],
                    *callback_log,
                    ["UNREG_TRIGGER", ["CURRENT_DYNAMIC_TRIGGER_INSTANCE"]],
                ],
                [],
            ]
        ],
    }
    return {
        "name": name,
        "id": ids.next_parent(),
        "event": [event_trigger(event_name)],
        "condition": [],
        "action": actions,
        "sub_triggers": [callback],
    }


def request_only_trigger(
    ids: Ids,
    *,
    name: str,
    event_name: str,
    root: str,
    button_path: str,
    result_path: str,
    function_key: str,
    args,
    pre_actions=None,
    redacted: bool = False,
):
    result_name = f"{name}立即结果"
    result_ref = table_var(result_name)
    logs = dump_or_redact(result_ref, redacted)
    return {
        "name": name,
        "id": ids.next_parent(),
        "event": [event_trigger(event_name)],
        "condition": [],
        "action": [
            set_enabled(root, button_path, False),
            set_text(root, result_path, f"{name}：提交中"),
            *(pre_actions or []),
            call(function_key, result_name, args),
            set_enabled(root, button_path, True),
            [
                "IF_THEN_ELSE",
                [["BOOL_COMPARE", boolean_field(result_ref, "accepted"), "==", True]],
                [set_text(root, result_path, f"{name}：请求已提交，以切图结果为准"), *logs],
                [set_text(root, result_path, f"{name}：失败，请查看日志"), *logs],
            ],
        ],
    }


def message_line(result_name: str):
    message = table_field(result_data(result_name), "message")
    sender = table_field(message, "sender")
    return join_text(string_field(sender, "name"), "：", string_field(message, "message"))


def entry_refresh_actions():
    actions = [
        call("connection", "刷新连接状态"),
        call("snapshot", "刷新状态快照"),
        call("members", "刷新成员列表"),
        call("token", "刷新口令"),
        call("chat_history", "刷新聊天记录", optional_args=[None]),
    ]
    for index in range(1, 5):
        actions.append(call("member", f"刷新成员{index}", [index]))
    for index in range(1, 6):
        actions.append(call("chat_message", f"刷新聊天{index}", [index], [None]))

    snapshot = result_data("刷新状态快照")
    connection = result_data("刷新连接状态")
    token = result_data("刷新口令")
    actions.extend([
        set_text(ENTRY_ROOT, "status_panel.status_aid.label_aid_value", as_text(integer_field(snapshot, "aid")), True),
        set_text(ENTRY_ROOT, "status_panel.status_mode.label_mode_value", as_text(integer_field(snapshot, "game_mode")), True),
        set_text(ENTRY_ROOT, "status_panel.status_connection.label_connection_value", string_field(connection, "status"), True),
        set_text(ENTRY_ROOT, "status_panel.status_team.label_team_value", as_text(integer_field(snapshot, "team_id")), True),
        set_text(ENTRY_ROOT, "status_panel.status_match.label_match_value", as_text(boolean_field(snapshot, "matching")), True),
        set_text(ENTRY_ROOT, "status_panel.status_launch.label_launch_value", as_text(boolean_field(snapshot, "launching")), True),
        set_text(ENTRY_ROOT, "team_panel.label_team_id", join_text("队伍编号：", as_text(integer_field(snapshot, "team_id"))), True),
        set_text(ENTRY_ROOT, "action_panel.label_token", join_text("当前口令：", string_field(token, "token")), True),
    ])
    for index in range(1, 5):
        member_data = table_field(result_data(f"刷新成员{index}"), "member")
        exists = boolean_field(result_data(f"刷新成员{index}"), "exists")
        actions.extend([
            set_visible(ENTRY_ROOT, f"team_panel.member_row_{index}", exists, True),
            set_text(
                ENTRY_ROOT,
                f"team_panel.member_row_{index}.label_member_{index}",
                join_text(
                    f"#{index}  AID ",
                    as_text(integer_field(member_data, "aid")),
                    "  ",
                    string_field(member_data, "name"),
                    "  ",
                    string_field(member_data, "state"),
                ),
                True,
            ),
        ])
    history = message_line("刷新聊天1")
    for index in range(2, 6):
        history = join_text(history, "\n", message_line(f"刷新聊天{index}"))
    actions.append(set_text(ENTRY_ROOT, "chat_panel.label_chat_history", history, True))
    return actions


def dungeon_refresh_actions():
    actions = [
        call("connection", "副本刷新连接状态"),
        call("snapshot", "副本刷新状态快照"),
        call("token", "副本刷新口令"),
        call("chat_history", "副本刷新聊天记录", optional_args=[None]),
    ]
    for index in range(1, 6):
        actions.append(call("chat_message", f"副本刷新聊天{index}", [index], [None]))
    snapshot = result_data("副本刷新状态快照")
    connection = result_data("副本刷新连接状态")
    token = result_data("副本刷新口令")
    actions.extend([
        set_text(
            DUNGEON_ROOT,
            "dungeon_status_panel.label_status",
            join_text(
                "连接：", string_field(connection, "status"),
                "    AID：", as_text(integer_field(snapshot, "aid")),
                "    队伍：", as_text(integer_field(snapshot, "team_id")),
                "    模式：", as_text(integer_field(snapshot, "game_mode")),
            ),
            True,
        ),
        set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_token_value", string_field(token, "token"), True),
    ])
    history = message_line("副本刷新聊天1")
    for index in range(2, 6):
        history = join_text(history, "\n", message_line(f"副本刷新聊天{index}"))
    actions.append(set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_chat_history", history, True))
    return actions


def init_trigger(ids: Ids, name: str, root: str, bindings, refresh_actions):
    return {
        "name": name,
        "id": ids.next_parent(),
        "event": [["INIT_FINISHED"]],
        "condition": [],
        "action": [
            *[register_event(root, path, event_name) for path, event_name in bindings],
            ["RUN_LOOP_TIMER_NO_SAVE", 1.0, True, refresh_actions],
        ],
    }


def entry_dsl():
    ids = Ids(1942000000, 1942100000)
    bindings = [
        ("team_panel.button_create_team", "eca_lobby_create_team"),
        ("team_panel.button_join_team", "eca_lobby_join_team"),
        ("team_panel.button_leave_team", "eca_lobby_leave_team"),
        ("team_panel.button_dismiss_team", "eca_lobby_dismiss_team"),
        ("action_panel.button_match", "eca_lobby_match"),
        ("action_panel.button_private_dungeon", "eca_lobby_private_dungeon"),
        ("action_panel.button_join_dungeon", "eca_lobby_join_token"),
        ("chat_panel.button_team_chat", "eca_lobby_team_chat"),
        ("chat_panel.button_world_chat", "eca_lobby_world_chat"),
        ("button_developer", "eca_lobby_developer_toggle"),
        ("button_exit", "eca_lobby_exit"),
        ("developer_panel.button_dev_connect", "eca_lobby_dev_connect"),
        ("developer_panel.button_dev_score", "eca_lobby_dev_score"),
        ("developer_panel.button_dev_team_info", "eca_lobby_dev_team_info"),
        ("developer_panel.button_dev_player_info", "eca_lobby_dev_player_info"),
        ("developer_panel.button_dev_refresh_player", "eca_lobby_dev_refresh_player"),
    ]
    for index in range(1, 5):
        bindings.extend([
            (f"team_panel.member_row_{index}.button_transfer_{index}", f"eca_lobby_transfer_{index}"),
            (f"team_panel.member_row_{index}.button_kick_{index}", f"eca_lobby_kick_{index}"),
        ])

    triggers = [init_trigger(ids, "ECA大厅UI - 初始化", ENTRY_ROOT, bindings, entry_refresh_actions())]
    triggers.extend([
        async_trigger(
            ids,
            name="ECA大厅UI - 创建队伍",
            event_name="eca_lobby_create_team",
            root=ENTRY_ROOT,
            button_path="team_panel.button_create_team",
            result_path="team_panel.label_team_hint",
            function_key="create_team",
            args=[4],
        ),
        async_trigger(
            ids,
            name="ECA大厅UI - 加入队伍",
            event_name="eca_lobby_join_team",
            root=ENTRY_ROOT,
            button_path="team_panel.button_join_team",
            result_path="team_panel.label_team_hint",
            function_key="join_team",
            args=[["STR_TO_INT", ["GET_INPUT_FIELD_CONTENT", player(), ui(ENTRY_ROOT, "team_panel.input_team_id")]]],
        ),
        async_trigger(
            ids,
            name="ECA大厅UI - 离开队伍",
            event_name="eca_lobby_leave_team",
            root=ENTRY_ROOT,
            button_path="team_panel.button_leave_team",
            result_path="team_panel.label_team_hint",
            function_key="leave_team",
        ),
        async_trigger(
            ids,
            name="ECA大厅UI - 解散队伍",
            event_name="eca_lobby_dismiss_team",
            root=ENTRY_ROOT,
            button_path="team_panel.button_dismiss_team",
            result_path="team_panel.label_team_hint",
            function_key="dismiss_team",
        ),
    ])

    for index in range(1, 5):
        member_result = f"成员操作目标{index}"
        member_aid = integer_field(table_field(result_data(member_result), "member"), "aid")
        pre = [call("member", member_result, [index])]
        triggers.extend([
            async_trigger(
                ids,
                name=f"ECA大厅UI - 转移队长{index}",
                event_name=f"eca_lobby_transfer_{index}",
                root=ENTRY_ROOT,
                button_path=f"team_panel.member_row_{index}.button_transfer_{index}",
                result_path="team_panel.label_team_hint",
                function_key="transfer",
                args=[member_aid],
                pre_actions=pre,
            ),
            async_trigger(
                ids,
                name=f"ECA大厅UI - 移出队员{index}",
                event_name=f"eca_lobby_kick_{index}",
                root=ENTRY_ROOT,
                button_path=f"team_panel.member_row_{index}.button_kick_{index}",
                result_path="team_panel.label_team_hint",
                function_key="kick",
                args=[member_aid],
                pre_actions=pre,
            ),
        ])

    chat_input = ["GET_INPUT_FIELD_CONTENT", player(), ui(ENTRY_ROOT, "chat_panel.input_chat")]
    triggers.extend([
        async_trigger(
            ids,
            name="ECA大厅UI - 发送队伍聊天",
            event_name="eca_lobby_team_chat",
            root=ENTRY_ROOT,
            button_path="chat_panel.button_team_chat",
            result_path="chat_panel.label_chat_result",
            function_key="team_chat",
            args=[chat_input],
            accepted_actions=[set_text(ENTRY_ROOT, "chat_panel.input_chat", "")],
            redacted=True,
        ),
        async_trigger(
            ids,
            name="ECA大厅UI - 发送世界聊天",
            event_name="eca_lobby_world_chat",
            root=ENTRY_ROOT,
            button_path="chat_panel.button_world_chat",
            result_path="chat_panel.label_chat_result",
            function_key="world_chat",
            args=[chat_input],
            accepted_actions=[set_text(ENTRY_ROOT, "chat_panel.input_chat", "")],
            redacted=True,
        ),
    ])

    private_state = "局内私人副本状态"
    private_params = "局内私人副本参数"
    private_pre = [
        call("snapshot", private_state),
        ["SET_VARIABLE", table_var(private_params), ["GET_NEW_TABLE"]],
        ["SET_TABLE_VALUE_1D", table_var(private_params), "game_map_id", string_field(result_data(private_state), "game_map_id")],
        ["SET_TABLE_VALUE_1D", table_var(private_params), "level_id", MATCH_LEVEL_ID],
        ["SET_TABLE_VALUE_1D", table_var(private_params), "engine_level_id", PRIVATE_LEVEL_UUID],
        ["SET_TABLE_VALUE_1D", table_var(private_params), "game_mode", 1003],
        ["SET_TABLE_VALUE_1D", table_var(private_params), "team_game_mode", 1002],
        ["SET_TABLE_VALUE_1D", table_var(private_params), "max_player", 2],
    ]
    triggers.append(request_only_trigger(
        ids,
        name="ECA大厅UI - 局内私人副本",
        event_name="eca_lobby_private_dungeon",
        root=ENTRY_ROOT,
        button_path="action_panel.button_private_dungeon",
        result_path="action_panel.label_action_state",
        function_key="private_dungeon",
        args=[table_var(private_params)],
        pre_actions=private_pre,
    ))

    triggers.append(request_only_trigger(
        ids,
        name="ECA大厅UI - 加入口令",
        event_name="eca_lobby_join_token",
        root=ENTRY_ROOT,
        button_path="action_panel.button_join_dungeon",
        result_path="action_panel.label_action_state",
        function_key="join_token",
        args=[["GET_INPUT_FIELD_CONTENT", player(), ui(ENTRY_ROOT, "action_panel.input_token")]],
        redacted=True,
    ))

    match_state = "匹配按钮状态"
    start_params = "开始匹配参数"
    start_result = "开始匹配立即结果"
    cancel_result = "取消匹配立即结果"
    start_callback = "ECA大厅UI - 开始匹配完成回调"
    cancel_callback = "ECA大厅UI - 取消匹配完成回调"
    match_button = "action_panel.button_match"
    match_label = "action_panel.label_action_state"

    def match_resolution(result_name: str, callback_name: str, verb: str):
        ref = table_var(result_name)
        return [[
            "IF_THEN_ELSE",
            [["BOOL_COMPARE", boolean_field(ref, "accepted"), "==", True]],
            [[
                "IF_THEN_ELSE",
                [["STRING_COMPARE", string_field(ref, "request_id"), "!=", ""]],
                [set_text(ENTRY_ROOT, match_label, f"{verb}：请求已受理"), {"register_sub_trigger": callback_name}],
                [set_enabled(ENTRY_ROOT, match_button, True), set_text(ENTRY_ROOT, match_label, f"{verb}：同步完成"), ["DUMP_TABLE", ref]],
            ]],
            [set_enabled(ENTRY_ROOT, match_button, True), set_text(ENTRY_ROOT, match_label, f"{verb}：失败，请查看日志"), ["DUMP_TABLE", ref]],
        ]]

    def match_callback(name: str, trigger_id: int, result_name: str):
        return {
            "name": name,
            "id": trigger_id,
            "event": [["RECEIVE_CUSTOM_EVENT", "大厅服务请求完成"]],
            "action": [[
                "IF_THEN_ELSE",
                [["STRING_COMPARE", string_field(custom_payload(), "request_id"), "==", string_field(table_var(result_name), "request_id")]],
                [set_enabled(ENTRY_ROOT, match_button, True), set_text(ENTRY_ROOT, match_label, "匹配状态已更新"), ["DUMP_TABLE", custom_payload()], ["UNREG_TRIGGER", ["CURRENT_DYNAMIC_TRIGGER_INSTANCE"]]],
                [],
            ]],
        }

    triggers.append({
        "name": "ECA大厅UI - 匹配切换",
        "id": ids.next_parent(),
        "event": [event_trigger("eca_lobby_match")],
        "condition": [],
        "action": [
            set_enabled(ENTRY_ROOT, match_button, False),
            call("snapshot", match_state),
            [
                "IF_THEN_ELSE",
                [["BOOL_COMPARE", boolean_field(result_data(match_state), "matching"), "==", True]],
                [call("cancel_match", cancel_result), *match_resolution(cancel_result, cancel_callback, "取消匹配")],
                [
                    ["SET_VARIABLE", table_var(start_params), ["GET_NEW_TABLE"]],
                    ["SET_TABLE_VALUE_1D", table_var(start_params), "level_id", MATCH_LEVEL_ID],
                    ["SET_TABLE_VALUE_1D", table_var(start_params), "game_mode", 1002],
                    ["SET_TABLE_VALUE_1D", table_var(start_params), "score", 1000],
                    call("start_match", start_result, [table_var(start_params)]),
                    *match_resolution(start_result, start_callback, "开始匹配"),
                ],
            ],
        ],
        "sub_triggers": [
            match_callback(start_callback, ids.next_child(), start_result),
            match_callback(cancel_callback, ids.next_child(), cancel_result),
        ],
    })

    triggers.append({
        "name": "ECA大厅UI - 开发面板切换",
        "id": ids.next_parent(),
        "event": [event_trigger("eca_lobby_developer_toggle")],
        "condition": [],
        "action": [[
            "IF_THEN_ELSE",
            [["BOOL_COMPARE", ["GET_UI_COMP_VISIBLE", player(), ui(ENTRY_ROOT, "developer_panel")], "==", True]],
            [set_visible(ENTRY_ROOT, "developer_panel", False)],
            [set_visible(ENTRY_ROOT, "developer_panel", True)],
        ]],
    })

    dev_specs = [
        ("建立连接", "eca_lobby_dev_connect", "developer_panel.button_dev_connect", "connect", [190356], [{"type": "BOOLEAN", "value": False}], True),
        ("设置匹配分数", "eca_lobby_dev_score", "developer_panel.button_dev_score", "score", [1000], None, False),
        ("获取队伍信息", "eca_lobby_dev_team_info", "developer_panel.button_dev_team_info", "team_info", [], [None], False),
        ("获取玩家信息", "eca_lobby_dev_player_info", "developer_panel.button_dev_player_info", "player_info", [], [None], False),
        ("刷新玩家信息", "eca_lobby_dev_refresh_player", "developer_panel.button_dev_refresh_player", "refresh_player", [], None, False),
    ]
    for title, event_name, button_path, key, args, optional, redacted in dev_specs:
        triggers.append(async_trigger(
            ids,
            name=f"ECA大厅UI - {title}",
            event_name=event_name,
            root=ENTRY_ROOT,
            button_path=button_path,
            result_path="developer_panel.label_developer_result",
            function_key=key,
            args=args,
            optional_args=optional,
            redacted=redacted,
        ))

    triggers.append(async_trigger(
        ids,
        name="ECA大厅UI - 退出游戏",
        event_name="eca_lobby_exit",
        root=ENTRY_ROOT,
        button_path="button_exit",
        result_path="header_panel.label_context",
        function_key="exit",
    ))
    return {"map": "EntryMap", "triggers": triggers}


def dungeon_dsl():
    ids = Ids(1943000000, 1943100000)
    bindings = [
        ("dungeon_status_panel.button_return_lobby", "eca_dungeon_return_lobby"),
        ("dungeon_chat_panel.button_team_chat", "eca_dungeon_team_chat"),
        ("dungeon_chat_panel.button_world_chat", "eca_dungeon_world_chat"),
        ("dungeon_chat_panel.button_copy_token", "eca_dungeon_copy_token"),
        ("button_exit", "eca_dungeon_exit"),
    ]
    triggers = [init_trigger(ids, "ECA副本UI - 初始化", DUNGEON_ROOT, bindings, dungeon_refresh_actions())]
    chat_input = ["GET_INPUT_FIELD_CONTENT", player(), ui(DUNGEON_ROOT, "dungeon_chat_panel.input_chat")]
    triggers.extend([
        async_trigger(
            ids,
            name="ECA副本UI - 发送队伍聊天",
            event_name="eca_dungeon_team_chat",
            root=DUNGEON_ROOT,
            button_path="dungeon_chat_panel.button_team_chat",
            result_path="dungeon_chat_panel.label_chat_result",
            function_key="team_chat",
            args=[chat_input],
            accepted_actions=[set_text(DUNGEON_ROOT, "dungeon_chat_panel.input_chat", "")],
            redacted=True,
        ),
        async_trigger(
            ids,
            name="ECA副本UI - 发送世界聊天",
            event_name="eca_dungeon_world_chat",
            root=DUNGEON_ROOT,
            button_path="dungeon_chat_panel.button_world_chat",
            result_path="dungeon_chat_panel.label_chat_result",
            function_key="world_chat",
            args=[chat_input],
            accepted_actions=[set_text(DUNGEON_ROOT, "dungeon_chat_panel.input_chat", "")],
            redacted=True,
        ),
    ])

    return_params = "返回大厅参数"
    triggers.append(request_only_trigger(
        ids,
        name="ECA副本UI - 返回大厅",
        event_name="eca_dungeon_return_lobby",
        root=DUNGEON_ROOT,
        button_path="dungeon_status_panel.button_return_lobby",
        result_path="dungeon_status_panel.label_status",
        function_key="return_lobby",
        args=[table_var(return_params)],
        pre_actions=[
            ["SET_VARIABLE", table_var(return_params), ["GET_NEW_TABLE"]],
            ["SET_TABLE_VALUE_1D", table_var(return_params), "level_id", LOBBY_LEVEL_UUID],
            ["SET_TABLE_VALUE_1D", table_var(return_params), "game_mode", 1001],
            ["SET_TABLE_VALUE_1D", table_var(return_params), "max_player", 1],
        ],
    ))

    triggers.append({
        "name": "ECA副本UI - 显示口令",
        "id": ids.next_parent(),
        "event": [event_trigger("eca_dungeon_copy_token")],
        "condition": [],
        "action": [
            call("token", "副本显示口令"),
            set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_token_value", string_field(result_data("副本显示口令"), "token")),
            set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_chat_result", "口令已显示，请手动传递给另一客户端"),
        ],
    })
    triggers.append(async_trigger(
        ids,
        name="ECA副本UI - 退出游戏",
        event_name="eca_dungeon_exit",
        root=DUNGEON_ROOT,
        button_path="button_exit",
        result_path="dungeon_status_panel.label_status",
        function_key="exit",
    ))
    return {"map": "MapName001", "triggers": triggers}


def render(data) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def write_or_check(path: Path, content: str, check: bool) -> bool:
    if check:
        return path.is_file() and path.read_text(encoding="utf-8") == content
    path.write_text(content, encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = [(ENTRY_DSL, render(entry_dsl())), (DUNGEON_DSL, render(dungeon_dsl()))]
    stale = [str(path.relative_to(ROOT)) for path, content in outputs if not write_or_check(path, content, args.check)]
    if stale:
        print("stale generated ECA DSL: " + ", ".join(stale))
        return 1
    for path, _ in outputs:
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
