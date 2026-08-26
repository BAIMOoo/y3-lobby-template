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
    "status_connection_bg",
    "status_team_bg",
    "status_match_bg",
    "status_launch_bg",
}
DANGER_BUTTONS = {
    "button_exit",
    "button_dismiss_team",
}
PRIMARY_BUTTONS = {"button_private_dungeon"}


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


def sync_file(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    ui_name = data["name"]
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
