# -*- coding: utf-8 -*-
"""Synchronize ECA lobby UI image assets with the verified Lua test UI."""

from __future__ import annotations

import copy
import json
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UI_FILES = [
    ROOT / "maps" / "EntryMap" / "ui" / "EcaLobbyExample.json",
    ROOT / "maps" / "EntryMap" / "ui" / "EcaDungeonExample.json",
]

BACKDROP = 134230328
PANEL = 134217729
PANEL_SOFT = 134217730
PANEL_DEEP = 134217731
INPUT = 134217732
FLAT = 109589

BUTTONS = {
    "normal": (134217733, 134217734, 134217735, 134217736),
    "primary": (134217737, 134217738, 134217739, 134217740),
    "danger": (134217741, 134217742, 134217743, 134217744),
}

PANEL_COLOR = [30, 25, 18, 236]
PANEL_SOFT_COLOR = [35, 29, 21, 226]
PANEL_DEEP_COLOR = [21, 18, 14, 244]

PANEL_BACKGROUNDS = {
    "chat_panel_bg",
    "team_panel_bg",
    "action_panel_bg",
    "status_panel_bg",
    "header_panel_bg",
    "dungeon_chat_panel_bg",
    "dungeon_status_panel_bg",
}
SOFT_BACKGROUNDS = {
    "status_aid_bg",
    "status_mode_bg",
    "status_player_bg",
    "status_bob_bg",
    "status_login_bg",
    "status_connection_bg",
    "status_team_bg",
    "status_count_bg",
    "status_match_bg",
    "status_launch_bg",
}
DANGER_BUTTONS = {
    "button_exit",
    "button_exit_confirm",
    "button_dismiss_team",
}
PRIMARY_BUTTONS = {"button_private_dungeon"}

SAME_LEVEL_BUTTON = "button_same_level_private_dungeon"
SAME_LEVEL_TEXT = "同关卡不同模式"


def tuple_value(items):
    return {"__tuple__": True, "items": items}


def stable_uid(ui_name: str, node_path: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"y3://{ui_name}/{node_path}"))


def make_backdrop(ui_name: str):
    return {
        "adapter_option": [True, True, True, True, 0.0, 0.0, 0.0, 0.0],
        "children": [],
        "color": [255, 255, 255, 255],
        "event_list": [],
        "image": BACKDROP,
        "name": "image_backdrop",
        "open_adapter": True,
        "pos_data": tuple_value([960.0, 540.0, 50.0, 50.0, 1, 1]),
        "prefab_sub_key": None,
        "scene_ui_name": None,
        "size": [1920.0, 1080.0],
        "swallow_touches": False,
        "type": 4,
        "uid": stable_uid(ui_name, "image_backdrop"),
    }


def make_input_background(ui_name: str, input_node: dict, node_path: str):
    return {
        "adapter_option": copy.deepcopy(input_node.get("adapter_option", [])),
        "cap_insets": [8.0, 8.0, 8.0, 8.0],
        "children": [],
        "color": [255, 255, 255, 255],
        "event_list": [],
        "image": INPUT,
        "is_scale9_enable": True,
        "name": f"image_{input_node['name']}_bg",
        "open_adapter": input_node.get("open_adapter", False),
        "pos_data": copy.deepcopy(input_node["pos_data"]),
        "prefab_sub_key": None,
        "scene_ui_name": None,
        "size": copy.deepcopy(input_node["size"]),
        "swallow_touches": False,
        "type": 4,
        "uid": stable_uid(ui_name, f"{node_path}.image_{input_node['name']}_bg"),
    }


def button_variant(name: str) -> str:
    if name in PRIMARY_BUTTONS:
        return "primary"
    if name in DANGER_BUTTONS or name.startswith("button_kick_"):
        return "danger"
    return "normal"


def sync_node(node: dict) -> None:
    name = node.get("name", "")
    if node.get("type") == 1:
        normal, hover, pressed, disabled = BUTTONS[button_variant(name)]
        node["normal_picture"] = normal
        node["suspend_picture"] = hover
        node["press_picture"] = pressed
        node["disabled_picture"] = disabled
        for status in ("normal", "suspend", "press", "disabled"):
            node[f"{status}_cap_insets"] = tuple_value([8.0, 8.0, 8.0, 8.0])
        return

    if node.get("type") != 4:
        return
    if name == "exit_confirm_overlay_bg":
        node["image"] = FLAT
        node["color"] = [0, 0, 0, 190]
    elif name == "developer_panel_bg":
        node["image"] = PANEL_DEEP
        node["color"] = PANEL_DEEP_COLOR
    elif name in PANEL_BACKGROUNDS:
        node["image"] = PANEL
        node["color"] = PANEL_COLOR
    elif name in SOFT_BACKGROUNDS or (
        name.startswith("member_row_") and name.endswith("_bg")
    ):
        node["image"] = PANEL_SOFT
        node["color"] = PANEL_SOFT_COLOR
    else:
        return
    if name != "exit_confirm_overlay_bg":
        node["is_scale9_enable"] = True
        node["cap_insets"] = [8.0, 8.0, 8.0, 8.0]


def sync_children(ui_name: str, node: dict, parent_path: str) -> None:
    children = node.get("children", [])
    input_backgrounds = {
        child.get("name"): child
        for child in children
        if child.get("type") == 4 and child.get("name", "").startswith("image_input_")
    }
    rebuilt = []
    for child in children:
        name = child.get("name", "")
        child_path = f"{parent_path}.{name}" if parent_path else name
        if child.get("type") == 15:
            background_name = f"image_{name}_bg"
            background = input_backgrounds.get(background_name)
            if background is None:
                background = make_input_background(ui_name, child, parent_path)
            else:
                background.update(make_input_background(ui_name, child, parent_path))
                rebuilt = [item for item in rebuilt if item is not background]
            rebuilt.append(background)
        if child.get("type") == 4 and name.startswith("image_input_"):
            continue
        sync_node(child)
        sync_children(ui_name, child, child_path)
        rebuilt.append(child)
    node["children"] = rebuilt


def set_position(node: dict, x: float, y: float, x_percent: float, y_percent: float) -> None:
    node["pos_data"] = tuple_value([x, y, x_percent, y_percent, 1, 1])


def set_size(node: dict, width: float, height: float) -> None:
    if isinstance(node.get("size"), dict):
        node["size"] = tuple_value([width, height])
    else:
        node["size"] = [width, height]


def set_rect(
    node: dict,
    x: float,
    y: float,
    width: float,
    height: float,
    parent_width: float,
    parent_height: float,
) -> None:
    set_size(node, width, height)
    center_x = x + width / 2
    center_y = y + height / 2
    set_position(
        node,
        center_x,
        center_y,
        center_x / parent_width * 100,
        center_y / parent_height * 100,
    )


def set_text_value(node: dict, value: str) -> None:
    node["text"] = tuple_value([value, False])


def set_button_text(node: dict, value: str) -> None:
    for status in ("normal", "suspend", "press", "disabled"):
        node[f"{status}_text"] = tuple_value([value, False])


def set_font_size(node: dict, size: int) -> None:
    font = node.get("font")
    if isinstance(font, dict) and len(font.get("items", [])) >= 2:
        font["items"][1] = size


def direct_child(node: dict, name: str) -> dict:
    return next(child for child in node.get("children", []) if child.get("name") == name)


def optional_child(node: dict, name: str):
    return next((child for child in node.get("children", []) if child.get("name") == name), None)


def identify(ui_name: str, node: dict, path: str) -> None:
    node["uid"] = stable_uid(ui_name, path)
    for child in node.get("children", []):
        identify(ui_name, child, f"{path}.{child['name']}")


def clone_leaf(ui_name: str, template: dict, name: str, path: str) -> dict:
    node = copy.deepcopy(template)
    node["name"] = name
    node["children"] = []
    identify(ui_name, node, path)
    return node


def make_status_card(
    ui_name: str,
    template: dict,
    key: str,
    label: str,
    rect: tuple[float, float, float, float],
) -> dict:
    card = copy.deepcopy(template)
    card["name"] = f"status_{key}"
    x, y, width, height = rect
    set_rect(card, x, y, width, height, 1004, 120)

    image_template = next(child for child in card["children"] if child.get("type") == 4)
    text_templates = [child for child in card["children"] if child.get("type") == 3]
    value_template = next(
        (child for child in text_templates if "value" in child.get("name", "")),
        text_templates[0],
    )
    key_template = next(
        (child for child in text_templates if "key" in child.get("name", "")),
        text_templates[-1],
    )
    background = clone_leaf(
        ui_name,
        image_template,
        f"status_{key}_bg",
        f"status_panel.status_{key}.status_{key}_bg",
    )
    set_rect(background, 0, 0, width, height, width, height)
    value_node = clone_leaf(
        ui_name,
        value_template,
        f"label_{key}_value",
        f"status_panel.status_{key}.label_{key}_value",
    )
    set_rect(value_node, 10, 3, width - 20, 20, width, height)
    set_text_value(value_node, "-")
    set_font_size(value_node, 14)
    key_node = clone_leaf(
        ui_name,
        key_template,
        f"label_{key}_key",
        f"status_panel.status_{key}.label_{key}_key",
    )
    set_rect(key_node, 10, 23, width - 20, 15, width, height)
    set_text_value(key_node, label)
    set_font_size(key_node, 11)
    card["children"] = [background, key_node, value_node]
    identify(ui_name, card, f"status_panel.status_{key}")
    return card


def align_status_panel(ui_name: str, panel: dict) -> None:
    template = next(
        child for child in panel["children"] if child.get("name", "").startswith("status_") and child.get("type") == 7
    )
    background = direct_child(panel, "status_panel_bg")
    specs = [
        ("mode", "模式", (18, 58, 150, 42)),
        ("player", "玩家", (176, 58, 210, 42)),
        ("bob", "服务", (394, 58, 105, 42)),
        ("login", "连接", (507, 58, 105, 42)),
        ("aid", "AID", (620, 58, 366, 42)),
        ("team", "队伍", (18, 10, 210, 42)),
        ("count", "人数", (236, 10, 100, 42)),
        ("match", "匹配", (344, 10, 150, 42)),
        ("launch", "启动", (502, 10, 150, 42)),
    ]
    panel["children"] = [
        background,
        *(make_status_card(ui_name, template, key, label, rect) for key, label, rect in specs),
    ]


def align_member_rows(ui_name: str, team_panel: dict) -> None:
    rows = [
        child for child in team_panel["children"] if child.get("name", "").startswith("member_row_")
    ]
    for index, row in enumerate(rows, 1):
        set_rect(row, 16, 224 - (index - 1) * 64, 488, 56, 520, 494)
        background = next(child for child in row["children"] if child.get("type") == 4)
        source_text = next(child for child in row["children"] if child.get("type") == 3)
        transfer = next(child for child in row["children"] if child.get("name", "").startswith("button_transfer_"))
        kick = next(child for child in row["children"] if child.get("name", "").startswith("button_kick_"))
        set_rect(background, 0, 0, 488, 56, 488, 56)
        fields = [
            ("index", 12, 0, 30, 56, str(index), 14),
            ("name", 50, 0, 130, 56, "-", 14),
            ("aid", 188, 0, 100, 56, "-", 13),
            ("state", 296, 0, 66, 56, "-", 13),
            ("current", 368, 0, 106, 56, "当前玩家", 12),
        ]
        field_nodes = []
        for key, x, y, width, height, text, font_size in fields:
            name = f"label_member_{key}_{index}"
            node = clone_leaf(ui_name, source_text, name, f"team_panel.member_row_{index}.{name}")
            set_rect(node, x, y, width, height, 488, 56)
            set_text_value(node, text)
            set_font_size(node, font_size)
            if key == "current":
                node["visible"] = False
            field_nodes.append(node)
        set_rect(transfer, 358, 7, 60, 42, 488, 56)
        set_rect(kick, 426, 7, 50, 42, 488, 56)
        row["children"] = [background, *field_nodes, transfer, kick]
        identify(ui_name, row, f"team_panel.member_row_{index}")


def align_team_panel(ui_name: str, panel: dict) -> None:
    align_member_rows(ui_name, panel)
    text_template = next(child for child in panel["children"] if child.get("type") == 3)
    positions = {
        "label_team_title": (18, 452, 210, 26),
        "label_team_hint": (310, 452, 190, 26),
        "label_team_id": (18, 412, 120, 22),
        "input_team_id": (26, 368, 168, 38),
        "image_input_team_id_bg": (18, 366, 184, 42),
        "button_join_team": (212, 366, 92, 42),
        "button_create_team": (314, 366, 96, 42),
        "button_leave_team": (420, 366, 82, 42),
        "label_member_title": (18, 326, 180, 24),
        "button_dismiss_team": (384, 318, 118, 42),
    }
    for name, rect in positions.items():
        node = optional_child(panel, name)
        if node is not None:
            set_rect(node, *rect, 520, 494)
    title = direct_child(panel, "label_member_title")
    set_text_value(title, "队员列表")
    count = clone_leaf(ui_name, text_template, "label_member_count", "team_panel.label_member_count")
    set_rect(count, 302, 326, 70, 24, 520, 494)
    set_text_value(count, "0 / 0")
    columns = optional_child(panel, "label_member_columns")
    if columns is not None:
        set_rect(columns, 30, 294, 472, 20, 520, 494)
        set_text_value(columns, "序号      玩家                 AID                 状态                    操作")
    panel["children"] = [
        child for child in panel["children"] if child.get("name") != "label_member_count"
    ]
    insert_at = panel["children"].index(title) + 1
    panel["children"].insert(insert_at, count)
    identify(ui_name, panel, "team_panel")


def align_action_panel(panel: dict) -> None:
    state = optional_child(panel, "label_action_state") or direct_child(panel, "label_action_team")
    positions = {
        "button_match": (18, 270, 174, 42),
        "button_private_dungeon": (204, 270, 332, 42),
        "button_same_level_private_dungeon": (18, 220, 518, 42),
        "label_token": (18, 182, 160, 22),
        "image_input_token_bg": (18, 132, 340, 42),
        "input_token": (26, 134, 324, 38),
        "button_join_dungeon": (370, 132, 166, 42),
        "label_action_target": (18, 38, 518, 34),
        "label_action_title": (18, 348, 260, 26),
        "label_action_role": (350, 348, 186, 26),
    }
    for name, rect in positions.items():
        node = optional_child(panel, name)
        if node is not None:
            set_rect(node, *rect, 556, 390)
    set_rect(state, 18, 84, 518, 30, 556, 390)
    state["name"] = "label_action_team"
    set_text_value(state, "队伍状态等待刷新")


def align_chat_panel(ui_name: str, panel: dict, dungeon: bool) -> None:
    text_template = next(child for child in panel["children"] if child.get("type") == 3)
    positions = {
        "image_input_chat_bg": (18, 56, 414, 42),
        "input_chat": (26, 58, 398, 38),
        "label_chat_history": (18, 132, 664, 158),
        "label_chat_result": (108, 14, 574, 28),
        "button_team_chat": (444, 56, 112, 42),
        "button_world_chat": (568, 56, 114, 42),
    }
    for name, rect in positions.items():
        node = optional_child(panel, name)
        if node is not None:
            set_rect(node, *rect, 700, 390)
    additions = []
    labels = [
        ("label_chat_title", 18, 300, 180, 24, "最近聊天", 17),
        ("label_chat_limit", 520, 300, 162, 24, "最多保留 5 条", 12),
        ("label_chat_prompt", 18, 104, 120, 22, "发送消息", 13),
        ("label_chat_result_key", 18, 14, 86, 28, "操作结果", 12),
    ]
    if dungeon:
        labels.extend([
            ("label_token_key", 18, 354, 112, 22, "关卡口令", 13),
        ])
        token = direct_child(panel, "label_token_value")
        set_rect(token, 132, 346, 390, 34, 700, 390)
        copy_button = direct_child(panel, "button_copy_token")
        set_rect(copy_button, 542, 340, 140, 42, 700, 390)
    else:
        labels.extend([
            ("label_chat_context", 18, 354, 112, 22, "聊天上下文", 13),
            ("label_chat_scope", 132, 346, 390, 34, "组队大厅", 17),
            ("label_chat_channel", 542, 346, 140, 34, "队伍 / 世界", 12),
        ])
    replaced = {item[0] for item in labels}
    panel["children"] = [child for child in panel["children"] if child.get("name") not in replaced]
    for name, x, y, width, height, text, font_size in labels:
        node = clone_leaf(ui_name, text_template, name, f"{panel['name']}.{name}")
        set_rect(node, x, y, width, height, 700, 390)
        set_text_value(node, text)
        set_font_size(node, font_size)
        additions.append(node)
    panel["children"].extend(additions)
    identify(ui_name, panel, panel["name"])


def build_exit_confirm(ui_name: str, data: dict) -> None:
    overlay = direct_child(data, "exit_confirm_overlay")
    overlay["visible"] = False
    set_rect(overlay, 0, 0, 1920, 1080, 1920, 1080)
    overlay_bg = direct_child(overlay, "exit_confirm_overlay_bg")
    set_rect(overlay_bg, 0, 0, 1920, 1080, 1920, 1080)
    overlay_bg["swallow_touches"] = True

    source_panel = optional_child(data, "developer_panel")
    if source_panel is None:
        source_panel = next(child for child in data["children"] if child.get("type") == 7 and child is not overlay)
    text_template = next(
        child for child in source_panel.get("children", []) if child.get("type") == 3
    )
    button_template = next(
        child for child in data.get("children", []) if child.get("type") == 1
    )
    image_template = next(
        child for child in source_panel.get("children", []) if child.get("type") == 4
    )
    panel = copy.deepcopy(source_panel)
    panel["name"] = "exit_confirm_panel"
    panel["children"] = []
    set_rect(panel, 720, 400, 480, 280, 1920, 1080)
    background = clone_leaf(
        ui_name,
        image_template,
        "exit_confirm_panel_bg",
        "exit_confirm_overlay.exit_confirm_panel.exit_confirm_panel_bg",
    )
    background["image"] = PANEL_DEEP
    background["color"] = PANEL_DEEP_COLOR
    set_rect(background, 0, 0, 480, 280, 480, 280)
    title = clone_leaf(ui_name, text_template, "label_exit_title", "exit_confirm_overlay.exit_confirm_panel.label_exit_title")
    set_rect(title, 36, 204, 406, 40, 480, 280)
    set_text_value(title, "确认退出游戏？")
    set_font_size(title, 26)
    description = clone_leaf(ui_name, text_template, "label_exit_description", "exit_confirm_overlay.exit_confirm_panel.label_exit_description")
    set_rect(description, 36, 126, 406, 56, 480, 280)
    set_text_value(description, "退出后将清理当前匹配和组队状态。")
    set_font_size(description, 17)
    cancel = clone_leaf(ui_name, button_template, "button_exit_cancel", "exit_confirm_overlay.exit_confirm_panel.button_exit_cancel")
    set_rect(cancel, 42, 36, 180, 52, 480, 280)
    set_button_text(cancel, "取消")
    confirm = clone_leaf(ui_name, button_template, "button_exit_confirm", "exit_confirm_overlay.exit_confirm_panel.button_exit_confirm")
    set_rect(confirm, 258, 36, 180, 52, 480, 280)
    set_button_text(confirm, "确认退出")
    for status, image in zip(("normal", "suspend", "press", "disabled"), BUTTONS["danger"]):
        confirm[f"{status}_picture"] = image
    panel["children"] = [background, title, description, cancel, confirm]
    identify(ui_name, panel, "exit_confirm_overlay.exit_confirm_panel")
    overlay["children"] = [overlay_bg, panel]
    identify(ui_name, overlay, "exit_confirm_overlay")


def align_lobby(ui_name: str, data: dict) -> None:
    data["children"] = [
        child for child in data["children"]
        if child.get("name") not in {"developer_panel", "button_developer"}
    ]
    top_level = {
        "header_panel": (24, 936, 430, 120),
        "status_panel": (470, 936, 1004, 120),
        "team_panel": (24, 426, 520, 494),
        "chat_panel": (24, 24, 700, 390),
        "action_panel": (1340, 24, 556, 390),
        "button_exit": (1746, 1008, 150, 48),
    }
    for name, rect in top_level.items():
        set_rect(direct_child(data, name), *rect, 1920, 1080)
    header = direct_child(data, "header_panel")
    header["children"] = [child for child in header["children"] if child.get("name") != "label_context"]
    title = direct_child(header, "label_title")
    set_rect(title, 18, 42, 320, 38, 430, 120)
    set_text_value(title, "大厅服务测试系统")
    set_font_size(title, 24)
    subtitle = direct_child(header, "label_subtitle")
    set_rect(subtitle, 18, 16, 320, 22, 430, 120)
    align_status_panel(ui_name, direct_child(data, "status_panel"))
    align_team_panel(ui_name, direct_child(data, "team_panel"))
    align_action_panel(direct_child(data, "action_panel"))
    align_chat_panel(ui_name, direct_child(data, "chat_panel"), False)
    build_exit_confirm(ui_name, data)


def align_dungeon(ui_name: str, data: dict) -> None:
    top_level = {
        "dungeon_status_panel": (24, 856, 860, 200),
        "dungeon_chat_panel": (24, 24, 700, 390),
        "button_exit": (1746, 1008, 150, 48),
    }
    for name, rect in top_level.items():
        set_rect(direct_child(data, name), *rect, 1920, 1080)
    status = direct_child(data, "dungeon_status_panel")
    positions = {
        "label_context": (18, 170, 360, 18),
        "label_title": (18, 136, 420, 30),
        "label_status": (18, 14, 640, 110),
        "button_return_lobby": (680, 136, 160, 48),
    }
    for name, rect in positions.items():
        set_rect(direct_child(status, name), *rect, 860, 200)
    set_text_value(direct_child(status, "label_context"), "大厅服务测试 · 关卡上下文")
    set_text_value(direct_child(status, "label_title"), "大厅服务测试状态")
    align_chat_panel(ui_name, direct_child(data, "dungeon_chat_panel"), True)
    build_exit_confirm(ui_name, data)


def ensure_same_level_button(data: dict) -> None:
    if data.get("name") != "EcaLobbyExample":
        return

    action_panel = next(
        child for child in data["children"] if child.get("name") == "action_panel"
    )
    children = action_panel["children"]
    private_button = next(
        child for child in children if child.get("name") == "button_private_dungeon"
    )
    same_level_button = next(
        (child for child in children if child.get("name") == SAME_LEVEL_BUTTON),
        None,
    )
    if same_level_button is None:
        same_level_button = copy.deepcopy(private_button)
        private_index = children.index(private_button)
        children.insert(private_index + 1, same_level_button)

    same_level_button["name"] = SAME_LEVEL_BUTTON
    same_level_button["uid"] = stable_uid(
        data["name"], f"action_panel.{SAME_LEVEL_BUTTON}"
    )
    same_level_button["size"] = [520.0, 46.0]
    set_position(same_level_button, 278.0, 241.0, 50.0, 61.7949)
    for status in ("normal", "suspend", "press", "disabled"):
        same_level_button[f"{status}_text"] = tuple_value([SAME_LEVEL_TEXT, False])

    positions = {
        "label_token": (98.0, 190.0, 17.6259, 48.7179),
        "image_input_token_bg": (187.9997, 154.0, 33.8129, 39.4872),
        "input_token": (187.9997, 154.0, 33.8129, 39.4872),
        "button_join_dungeon": (454.0001, 154.0, 81.6547, 39.4872),
        "label_action_state": (278.0, 91.0, 50.0, 23.3333),
        "label_action_target": (278.0, 35.0, 50.0, 8.9744),
    }
    for child in children:
        position = positions.get(child.get("name"))
        if position is not None:
            set_position(child, *position)
        if child.get("name") == "label_action_target":
            child["text"] = tuple_value(
                ["跨关卡 1002 / 1003    同关卡 EntryMap / 1003", False]
            )


def sync_file(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    ui_name = data["name"]
    ensure_same_level_button(data)
    if ui_name == "EcaLobbyExample":
        align_lobby(ui_name, data)
    else:
        align_dungeon(ui_name, data)
    sync_children(ui_name, data, ui_name)
    data["children"] = [
        child for child in data["children"] if child.get("name") != "image_backdrop"
    ]
    data["children"].insert(0, make_backdrop(ui_name))
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=4, separators=(", ", ": ")) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    for path in UI_FILES:
        sync_file(path)
        print(f"synced {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
