# -*- coding: utf-8 -*-
"""Build compact ECA DSL files for the lobby and dungeon UI on EntryMap."""

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
ENTRY_LEVEL_ID = "172371058548994502264384971909138463342"
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


def set_enabled_when(root: str, path: str, condition, local: bool = False):
    condition_list = [condition] if isinstance(condition[0], str) else condition
    return [
        "IF_THEN_ELSE",
        condition_list,
        [set_enabled(root, path, True, local)],
        [set_enabled(root, path, False, local)],
    ]


def set_visible(root: str, path: str, visible, local: bool = False):
    return ["SET_UI_COMP_VISIBLE", player(local), visible, ui(root, path, local)]


def set_button_text(root: str, path: str, value, local: bool = False):
    return [set_text(root, path, value, local)]


def bool_is(source, key: str, expected: bool):
    return ["BOOL_COMPARE", boolean_field(source, key), "==", expected]


def all_of(*conditions):
    return ["AND", list(conditions)]


def any_of(*conditions):
    return ["OR", list(conditions)]


def integer_equals(left, right):
    return ["INTEGER_COMPARE", left, "==", right]


def without_whitespace(value):
    for whitespace in (" ", "\t", "\r", "\n"):
        value = ["STR_REPLACE", value, whitespace, ""]
    return value


def lobby_context_conditions():
    return [
        [
            "OR",
            [
                ["STRING_COMPARE", as_text(["GET_GAME_MODE"]), "==", "0"],
                ["STRING_COMPARE", as_text(["GET_GAME_MODE"]), "==", "1001"],
            ],
        ],
    ]


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
    guard_conditions=None,
    rejected_actions=None,
    redacted: bool = False,
):
    result_name = f"{name}立即结果"
    callback_name = f"{name}完成回调"
    result_ref = table_var(result_name)
    log_actions = dump_or_redact(result_ref, redacted)
    callback_log = dump_or_redact(custom_payload(), redacted)
    actions = [
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
                        set_text(root, result_path, f"{name}：同步完成"),
                        *log_actions,
                    ],
                ],
            ],
            [
                set_text(root, result_path, f"{name}：失败，请查看日志"),
                *log_actions,
            ],
        ],
    ]
    if guard_conditions:
        actions = [[
            "IF_THEN_ELSE",
            guard_conditions,
            actions,
            rejected_actions or [set_text(root, result_path, f"{name}：输入无效")],
        ]]
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
    guard_conditions=None,
    rejected_actions=None,
    redacted: bool = False,
):
    result_name = f"{name}立即结果"
    result_ref = table_var(result_name)
    logs = dump_or_redact(result_ref, redacted)
    actions = [
        set_text(root, result_path, f"{name}：提交中"),
        *(pre_actions or []),
        call(function_key, result_name, args),
        [
            "IF_THEN_ELSE",
            [["BOOL_COMPARE", boolean_field(result_ref, "accepted"), "==", True]],
            [set_text(root, result_path, f"{name}：请求已提交，以切图结果为准"), *logs],
            [set_text(root, result_path, f"{name}：失败，请查看日志"), *logs],
        ],
    ]
    if guard_conditions:
        actions = [[
            "IF_THEN_ELSE",
            guard_conditions,
            actions,
            rejected_actions or [set_text(root, result_path, f"{name}：输入无效")],
        ]]
    return {
        "name": name,
        "id": ids.next_parent(),
        "event": [event_trigger(event_name)],
        "condition": [],
        "action": actions,
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
    connected = bool_is(snapshot, "connected", True)
    has_team = bool_is(snapshot, "has_team", True)
    no_team = bool_is(snapshot, "has_team", False)
    captain = bool_is(snapshot, "is_captain", True)
    not_matching = bool_is(snapshot, "matching", False)
    not_launching = bool_is(snapshot, "launching", False)
    can_manage = all_of(has_team, captain, not_matching, not_launching)
    can_leave = all_of(has_team, not_matching, not_launching)
    solo_or_captain = any_of(no_team, captain)
    can_match = all_of(connected, not_launching, solo_or_captain)
    can_private = any_of(no_team, all_of(connected, captain, not_matching, not_launching))
    actions.extend([
        set_text(ENTRY_ROOT, "status_panel.status_aid.label_aid_value", as_text(integer_field(snapshot, "aid")), True),
        set_text(ENTRY_ROOT, "status_panel.status_mode.label_mode_value", join_text("大厅 (", as_text(["GET_GAME_MODE"]), ")"), True),
        set_text(ENTRY_ROOT, "status_panel.status_player.label_player_value", join_text(["GET_PLAYER_NAME", player(True)], " / ID=", as_text(["PLAYER_ID_NUMBER", player(True)])), True),
        set_text(ENTRY_ROOT, "status_panel.status_bob.label_bob_value", string_field(snapshot, "status"), True),
        ["IF_THEN_ELSE", [connected], [set_text(ENTRY_ROOT, "status_panel.status_login.label_login_value", "已连接", True)], [set_text(ENTRY_ROOT, "status_panel.status_login.label_login_value", "未连接", True)]],
        ["IF_THEN_ELSE", [has_team], [set_text(ENTRY_ROOT, "status_panel.status_team.label_team_value", as_text(integer_field(snapshot, "team_id")), True)], [set_text(ENTRY_ROOT, "status_panel.status_team.label_team_value", "未加入", True)]],
        set_text(ENTRY_ROOT, "status_panel.status_count.label_count_value", join_text(as_text(integer_field(snapshot, "member_count")), "/", as_text(integer_field(snapshot, "member_limit"))), True),
        ["IF_THEN_ELSE", [bool_is(snapshot, "matching", True)], [set_text(ENTRY_ROOT, "status_panel.status_match.label_match_value", "匹配中", True)], [set_text(ENTRY_ROOT, "status_panel.status_match.label_match_value", "未匹配", True)]],
        ["IF_THEN_ELSE", [bool_is(snapshot, "launching", True)], [set_text(ENTRY_ROOT, "status_panel.status_launch.label_launch_value", "启动中", True)], [set_text(ENTRY_ROOT, "status_panel.status_launch.label_launch_value", "未启动", True)]],
        set_text(ENTRY_ROOT, "team_panel.label_team_id", join_text("队伍编号：", as_text(integer_field(snapshot, "team_id"))), True),
        set_text(ENTRY_ROOT, "team_panel.label_member_count", join_text(as_text(integer_field(snapshot, "member_count")), " / ", as_text(integer_field(snapshot, "member_limit"))), True),
        set_enabled_when(ENTRY_ROOT, "team_panel.button_leave_team", can_leave, True),
        set_enabled_when(ENTRY_ROOT, "team_panel.button_dismiss_team", can_manage, True),
        set_enabled_when(ENTRY_ROOT, "action_panel.button_private_dungeon", can_private, True),
        set_enabled_when(ENTRY_ROOT, "action_panel.button_same_level_private_dungeon", can_private, True),
        set_enabled_when(ENTRY_ROOT, "action_panel.button_match", can_match, True),
        set_enabled_when(ENTRY_ROOT, "chat_panel.button_team_chat", all_of(connected, has_team), True),
        set_enabled_when(ENTRY_ROOT, "chat_panel.button_world_chat", connected, True),
        [
            "IF_THEN_ELSE",
            [bool_is(snapshot, "launching", True)],
            set_button_text(ENTRY_ROOT, "action_panel.button_match", "启动中", True),
            [[
                "IF_THEN_ELSE",
                [bool_is(snapshot, "matching", True)],
                set_button_text(ENTRY_ROOT, "action_panel.button_match", "取消匹配", True),
                set_button_text(ENTRY_ROOT, "action_panel.button_match", "开始匹配", True),
            ]],
        ],
    ])
    for index in range(1, 5):
        member_data = table_field(result_data(f"刷新成员{index}"), "member")
        exists = boolean_field(result_data(f"刷新成员{index}"), "exists")
        is_self = integer_equals(
            integer_field(member_data, "aid"),
            integer_field(snapshot, "aid"),
        )
        actions.extend([
            set_visible(ENTRY_ROOT, f"team_panel.member_row_{index}", exists, True),
            set_text(
                ENTRY_ROOT,
                f"team_panel.member_row_{index}.label_member_index_{index}",
                str(index),
                True,
            ),
            [
                "IF_THEN_ELSE",
                [all_of(is_self, captain)],
                [set_text(ENTRY_ROOT, f"team_panel.member_row_{index}.label_member_name_{index}", join_text(string_field(member_data, "name"), " [队长]"), True)],
                [set_text(ENTRY_ROOT, f"team_panel.member_row_{index}.label_member_name_{index}", string_field(member_data, "name"), True)],
            ],
            set_text(ENTRY_ROOT, f"team_panel.member_row_{index}.label_member_aid_{index}", as_text(integer_field(member_data, "aid")), True),
            set_text(ENTRY_ROOT, f"team_panel.member_row_{index}.label_member_state_{index}", string_field(member_data, "state"), True),
            set_visible(ENTRY_ROOT, f"team_panel.member_row_{index}.label_member_current_{index}", is_self, True),
            set_visible(ENTRY_ROOT, f"team_panel.member_row_{index}.button_transfer_{index}", ["BOOL_COMPARE", is_self, "==", False], True),
            set_visible(ENTRY_ROOT, f"team_panel.member_row_{index}.button_kick_{index}", ["BOOL_COMPARE", is_self, "==", False], True),
            set_enabled_when(ENTRY_ROOT, f"team_panel.member_row_{index}.button_transfer_{index}", all_of(can_manage, ["BOOL_COMPARE", is_self, "==", False]), True),
            set_enabled_when(ENTRY_ROOT, f"team_panel.member_row_{index}.button_kick_{index}", all_of(can_manage, ["BOOL_COMPARE", is_self, "==", False]), True),
        ])
    team_count = join_text(
        as_text(integer_field(snapshot, "member_count")),
        "/",
        as_text(integer_field(snapshot, "member_limit")),
    )
    def team_summary(role: str, reason: str):
        return set_text(
            ENTRY_ROOT,
            "action_panel.label_action_team",
            join_text("队伍就绪  ", team_count, "    当前身份  ", role, "    ", reason),
            True,
        )

    actions.append([
        "IF_THEN_ELSE",
        [no_team],
        [team_summary("单人", "无队伍：可单人进入")],
        [[
            "IF_THEN_ELSE",
            [bool_is(snapshot, "is_captain", False)],
            [team_summary("队员", "只有队长可以发起局内私人副本")],
            [[
                "IF_THEN_ELSE",
                [bool_is(snapshot, "connected", False)],
                [team_summary("队长", "队伍路径需要大厅服务已连接")],
                [[
                    "IF_THEN_ELSE",
                    [bool_is(snapshot, "matching", True)],
                    [team_summary("队长", "队伍正在匹配，不能发起局内私人副本")],
                    [[
                        "IF_THEN_ELSE",
                        [bool_is(snapshot, "launching", True)],
                        [team_summary("队长", "队伍正在启动关卡，不能发起局内私人副本")],
                        [team_summary("队长", "可发起队伍副本")],
                    ]],
                ]],
            ]],
        ]],
    ])
    history = message_line("刷新聊天1")
    for index in range(2, 6):
        history = join_text(history, "\n", message_line(f"刷新聊天{index}"))
    actions.append([
        "IF_THEN_ELSE",
        [bool_is(result_data("刷新聊天1"), "exists", True)],
        [set_text(ENTRY_ROOT, "chat_panel.label_chat_history", history, True)],
        [set_text(ENTRY_ROOT, "chat_panel.label_chat_history", "暂无聊天消息", True)],
    ])
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
    connected = bool_is(snapshot, "connected", True)
    has_team = bool_is(snapshot, "has_team", True)
    token_available = ["STRING_COMPARE", string_field(token, "token"), "!=", ""]
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
        set_enabled_when(DUNGEON_ROOT, "dungeon_chat_panel.button_copy_token", token_available, True),
        set_enabled_when(DUNGEON_ROOT, "dungeon_chat_panel.button_team_chat", all_of(connected, has_team), True),
        set_enabled_when(DUNGEON_ROOT, "dungeon_chat_panel.button_world_chat", connected, True),
    ])
    history = message_line("副本刷新聊天1")
    for index in range(2, 6):
        history = join_text(history, "\n", message_line(f"副本刷新聊天{index}"))
    actions.append([
        "IF_THEN_ELSE",
        [bool_is(result_data("副本刷新聊天1"), "exists", True)],
        [set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_chat_history", history, True)],
        [set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_chat_history", "暂无聊天消息", True)],
    ])
    return actions


def init_trigger(
    ids: Ids,
    name: str,
    root: str,
    bindings,
    refresh_actions,
    *,
    lobby_ui: bool,
):
    active_actions = [
        *[register_event(root, path, event_name) for path, event_name in bindings],
        ["RUN_LOOP_TIMER_NO_SAVE", 0.5, True, refresh_actions],
    ]
    if lobby_ui:
        lobby_actions = [
            set_visible(ENTRY_ROOT, "", True, True),
            set_visible(DUNGEON_ROOT, "", False, True),
            *active_actions,
        ]
        dungeon_actions = [set_visible(ENTRY_ROOT, "", False, True)]
    else:
        lobby_actions = [set_visible(DUNGEON_ROOT, "", False, True)]
        dungeon_actions = [
            set_visible(ENTRY_ROOT, "", False, True),
            set_visible(DUNGEON_ROOT, "", True, True),
            set_visible(DUNGEON_ROOT, "image_backdrop", False, True),
            *active_actions,
        ]
    return {
        "name": name,
        "id": ids.next_parent(),
        "event": [["INIT_FINISHED"]],
        "condition": [],
        "action": [[
            "IF_THEN_ELSE",
            lobby_context_conditions(),
            lobby_actions,
            dungeon_actions,
        ]],
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
        ("action_panel.button_same_level_private_dungeon", "eca_lobby_same_level_private_dungeon"),
        ("action_panel.button_join_dungeon", "eca_lobby_join_token"),
        ("chat_panel.button_team_chat", "eca_lobby_team_chat"),
        ("chat_panel.button_world_chat", "eca_lobby_world_chat"),
        ("button_exit", "eca_lobby_exit_show"),
        ("exit_confirm_overlay.exit_confirm_panel.button_exit_cancel", "eca_lobby_exit_cancel"),
        ("exit_confirm_overlay.exit_confirm_panel.button_exit_confirm", "eca_lobby_exit_confirm"),
    ]
    for index in range(1, 5):
        bindings.extend([
            (f"team_panel.member_row_{index}.button_transfer_{index}", f"eca_lobby_transfer_{index}"),
            (f"team_panel.member_row_{index}.button_kick_{index}", f"eca_lobby_kick_{index}"),
        ])

    triggers = [init_trigger(
        ids,
        "ECA大厅UI - 初始化",
        ENTRY_ROOT,
        bindings,
        entry_refresh_actions(),
        lobby_ui=True,
    )]
    triggers.extend([
        async_trigger(
            ids,
            name="ECA大厅UI - 创建队伍",
            event_name="eca_lobby_create_team",
            root=ENTRY_ROOT,
            button_path="team_panel.button_create_team",
            result_path="chat_panel.label_chat_result",
            function_key="create_team",
            args=[2],
        ),
        async_trigger(
            ids,
            name="ECA大厅UI - 加入队伍",
            event_name="eca_lobby_join_team",
            root=ENTRY_ROOT,
            button_path="team_panel.button_join_team",
            result_path="chat_panel.label_chat_result",
            function_key="join_team",
            args=[["STR_TO_INT", ["GET_INPUT_FIELD_CONTENT", player(), ui(ENTRY_ROOT, "team_panel.input_team_id")]]],
            guard_conditions=[["INTEGER_COMPARE", ["STR_TO_INT", ["GET_INPUT_FIELD_CONTENT", player(), ui(ENTRY_ROOT, "team_panel.input_team_id")]], ">", 0]],
            rejected_actions=[set_text(ENTRY_ROOT, "chat_panel.label_chat_result", "加入队伍：请输入有效数字编号")],
        ),
        async_trigger(
            ids,
            name="ECA大厅UI - 离开队伍",
            event_name="eca_lobby_leave_team",
            root=ENTRY_ROOT,
            button_path="team_panel.button_leave_team",
            result_path="chat_panel.label_chat_result",
            function_key="leave_team",
        ),
        async_trigger(
            ids,
            name="ECA大厅UI - 解散队伍",
            event_name="eca_lobby_dismiss_team",
            root=ENTRY_ROOT,
            button_path="team_panel.button_dismiss_team",
            result_path="chat_panel.label_chat_result",
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
                result_path="chat_panel.label_chat_result",
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
                result_path="chat_panel.label_chat_result",
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
            guard_conditions=[["STRING_COMPARE", chat_input, "!=", ""]],
            rejected_actions=[set_text(ENTRY_ROOT, "chat_panel.label_chat_result", "队伍聊天：消息为空")],
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
            guard_conditions=[["STRING_COMPARE", chat_input, "!=", ""]],
            rejected_actions=[set_text(ENTRY_ROOT, "chat_panel.label_chat_result", "世界聊天：消息为空")],
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
        result_path="chat_panel.label_chat_result",
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
        result_path="chat_panel.label_chat_result",
        function_key="join_token",
        args=[["GET_INPUT_FIELD_CONTENT", player(), ui(ENTRY_ROOT, "action_panel.input_token")]],
        guard_conditions=[["STRING_COMPARE", without_whitespace(["GET_INPUT_FIELD_CONTENT", player(), ui(ENTRY_ROOT, "action_panel.input_token")]), "!=", ""]],
        rejected_actions=[set_text(ENTRY_ROOT, "chat_panel.label_chat_result", "加入口令：请输入关卡口令")],
        redacted=True,
    ))

    match_state = "匹配按钮状态"
    start_params = "开始匹配参数"
    start_result = "开始匹配立即结果"
    cancel_result = "取消匹配立即结果"
    start_callback = "ECA大厅UI - 开始匹配完成回调"
    cancel_callback = "ECA大厅UI - 取消匹配完成回调"
    match_button = "action_panel.button_match"
    match_label = "chat_panel.label_chat_result"

    def match_resolution(result_name: str, callback_name: str, verb: str):
        ref = table_var(result_name)
        return [[
            "IF_THEN_ELSE",
            [["BOOL_COMPARE", boolean_field(ref, "accepted"), "==", True]],
            [[
                "IF_THEN_ELSE",
                [["STRING_COMPARE", string_field(ref, "request_id"), "!=", ""]],
                [set_text(ENTRY_ROOT, match_label, f"{verb}：请求已受理"), {"register_sub_trigger": callback_name}],
                [set_text(ENTRY_ROOT, match_label, f"{verb}：同步完成"), ["DUMP_TABLE", ref]],
            ]],
            [set_text(ENTRY_ROOT, match_label, f"{verb}：失败，请查看日志"), ["DUMP_TABLE", ref]],
        ]]

    def match_callback(name: str, trigger_id: int, result_name: str):
        return {
            "name": name,
            "id": trigger_id,
            "event": [["RECEIVE_CUSTOM_EVENT", "大厅服务请求完成"]],
            "action": [[
                "IF_THEN_ELSE",
                [["STRING_COMPARE", string_field(custom_payload(), "request_id"), "==", string_field(table_var(result_name), "request_id")]],
                [set_text(ENTRY_ROOT, match_label, "匹配状态已更新"), ["DUMP_TABLE", custom_payload()], ["UNREG_TRIGGER", ["CURRENT_DYNAMIC_TRIGGER_INSTANCE"]]],
                [],
            ]],
        }

    triggers.append({
        "name": "ECA大厅UI - 匹配切换",
        "id": ids.next_parent(),
        "event": [event_trigger("eca_lobby_match")],
        "condition": [],
        "action": [
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

    triggers.extend([
        {
            "name": "ECA大厅UI - 显示退出确认",
            "id": ids.next_parent(),
            "event": [event_trigger("eca_lobby_exit_show")],
            "condition": [],
            "action": [set_visible(ENTRY_ROOT, "exit_confirm_overlay", True)],
        },
        {
            "name": "ECA大厅UI - 取消退出",
            "id": ids.next_parent(),
            "event": [event_trigger("eca_lobby_exit_cancel")],
            "condition": [],
            "action": [set_visible(ENTRY_ROOT, "exit_confirm_overlay", False)],
        },
        async_trigger(
            ids,
            name="ECA大厅UI - 确认退出游戏",
            event_name="eca_lobby_exit_confirm",
            root=ENTRY_ROOT,
            button_path="exit_confirm_overlay.exit_confirm_panel.button_exit_confirm",
            result_path="chat_panel.label_chat_result",
            function_key="exit",
            pre_actions=[set_visible(ENTRY_ROOT, "exit_confirm_overlay", False)],
        ),
    ])

    same_level_state = "同关卡不同模式状态"
    same_level_params = "同关卡不同模式参数"
    triggers.append(request_only_trigger(
        ids,
        name="ECA大厅UI - 同关卡不同模式",
        event_name="eca_lobby_same_level_private_dungeon",
        root=ENTRY_ROOT,
        button_path="action_panel.button_same_level_private_dungeon",
        result_path="chat_panel.label_chat_result",
        function_key="private_dungeon",
        args=[table_var(same_level_params)],
        pre_actions=[
            call("snapshot", same_level_state),
            ["SET_VARIABLE", table_var(same_level_params), ["GET_NEW_TABLE"]],
            ["SET_TABLE_VALUE_1D", table_var(same_level_params), "game_map_id", string_field(result_data(same_level_state), "game_map_id")],
            ["SET_TABLE_VALUE_1D", table_var(same_level_params), "level_id", ENTRY_LEVEL_ID],
            ["SET_TABLE_VALUE_1D", table_var(same_level_params), "engine_level_id", LOBBY_LEVEL_UUID],
            ["SET_TABLE_VALUE_1D", table_var(same_level_params), "game_mode", 1003],
            ["SET_TABLE_VALUE_1D", table_var(same_level_params), "team_game_mode", 1003],
            ["SET_TABLE_VALUE_1D", table_var(same_level_params), "max_player", 2],
        ],
    ))
    return {"map": "EntryMap", "triggers": triggers}


def dungeon_dsl():
    ids = Ids(1943000000, 1943100000)
    bindings = [
        ("dungeon_status_panel.button_return_lobby", "eca_dungeon_return_lobby"),
        ("dungeon_chat_panel.button_team_chat", "eca_dungeon_team_chat"),
        ("dungeon_chat_panel.button_world_chat", "eca_dungeon_world_chat"),
        ("dungeon_chat_panel.button_copy_token", "eca_dungeon_copy_token"),
        ("button_exit", "eca_dungeon_exit_show"),
        ("exit_confirm_overlay.exit_confirm_panel.button_exit_cancel", "eca_dungeon_exit_cancel"),
        ("exit_confirm_overlay.exit_confirm_panel.button_exit_confirm", "eca_dungeon_exit_confirm"),
    ]
    triggers = [init_trigger(
        ids,
        "ECA副本UI - 初始化",
        DUNGEON_ROOT,
        bindings,
        dungeon_refresh_actions(),
        lobby_ui=False,
    )]
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
            guard_conditions=[["STRING_COMPARE", chat_input, "!=", ""]],
            rejected_actions=[set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_chat_result", "队伍聊天：消息为空")],
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
            guard_conditions=[["STRING_COMPARE", chat_input, "!=", ""]],
            rejected_actions=[set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_chat_result", "世界聊天：消息为空")],
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
        "name": "ECA副本UI - 复制口令",
        "id": ids.next_parent(),
        "event": [event_trigger("eca_dungeon_copy_token")],
        "condition": [],
        "action": [
            call("token", "副本显示口令"),
            [
                "IF_THEN_ELSE",
                [["STRING_COMPARE", string_field(result_data("副本显示口令"), "token"), "!=", ""]],
                [
                    set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_token_value", string_field(result_data("副本显示口令"), "token")),
                    ["COPY_UI_TEXT_TO_CLIPBOARD", player(), ui(DUNGEON_ROOT, "dungeon_chat_panel.label_token_value")],
                    set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_chat_result", "关卡口令已复制到剪贴板"),
                ],
                [set_text(DUNGEON_ROOT, "dungeon_chat_panel.label_chat_result", "当前没有可复制的关卡口令")],
            ],
        ],
    })
    triggers.extend([
        {
            "name": "ECA副本UI - 显示退出确认",
            "id": ids.next_parent(),
            "event": [event_trigger("eca_dungeon_exit_show")],
            "condition": [],
            "action": [set_visible(DUNGEON_ROOT, "exit_confirm_overlay", True)],
        },
        {
            "name": "ECA副本UI - 取消退出",
            "id": ids.next_parent(),
            "event": [event_trigger("eca_dungeon_exit_cancel")],
            "condition": [],
            "action": [set_visible(DUNGEON_ROOT, "exit_confirm_overlay", False)],
        },
        async_trigger(
            ids,
            name="ECA副本UI - 确认退出游戏",
            event_name="eca_dungeon_exit_confirm",
            root=DUNGEON_ROOT,
            button_path="exit_confirm_overlay.exit_confirm_panel.button_exit_confirm",
            result_path="dungeon_chat_panel.label_chat_result",
            function_key="exit",
            pre_actions=[set_visible(DUNGEON_ROOT, "exit_confirm_overlay", False)],
        ),
    ])
    return {"map": "EntryMap", "triggers": triggers}


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
