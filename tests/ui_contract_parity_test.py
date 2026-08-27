# -*- coding: utf-8 -*-
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_ROOT = ROOT / "contracts" / "ui"


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def node_size(node):
    value = node.get("size", [0, 0])
    if isinstance(value, dict):
        value = value["items"]
    return [float(value[0]), float(value[1])]


def build_ui_index(root):
    result = {}

    def visit(node, path, origin):
        width, height = node_size(node)
        if path:
            center = node.get("pos_data", {}).get("items", [width / 2, height / 2])
            left = origin[0] + float(center[0]) - width / 2
            bottom = origin[1] + float(center[1]) - height / 2
            result[path] = (node, [left, bottom, width, height])
        else:
            left, bottom = 0.0, 0.0
        for child in node.get("children", []):
            child_path = f"{path}.{child['name']}" if path else child["name"]
            visit(child, child_path, (left, bottom))

    visit(root, "", (0.0, 0.0))
    return result


class UIContractParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = load_json(CONTRACT_ROOT / "manifest.json")
        cls.lobby = load_json(CONTRACT_ROOT / "lobby.json")
        cls.dungeon = load_json(CONTRACT_ROOT / "dungeon.json")
        cls.lobby_ui = build_ui_index(load_json(ROOT / "maps" / "EntryMap" / "ui" / "EcaLobbyExample.json"))
        cls.dungeon_ui = build_ui_index(load_json(ROOT / "maps" / "EntryMap" / "ui" / "EcaDungeonExample.json"))
        cls.lobby_dsl = load_json(ROOT / "tools" / "eca" / "lobby_ui_entry_map.json")
        cls.dungeon_dsl = load_json(ROOT / "tools" / "eca" / "lobby_ui_dungeon_map.json")
        cls.lua = (ROOT / "maps" / "EntryMap" / "script" / "test_ui.lua").read_text(encoding="utf-8")

    def assert_contract_geometry(self, contract, index):
        for semantic_id, spec in contract["required_nodes"].items():
            with self.subTest(flow=contract["flow"], semantic_id=semantic_id):
                self.assertIn(spec["path"], index)
                actual = index[spec["path"]][1]
                self.assertEqual(spec["rect"], [round(value) for value in actual])

    def test_manifest_pins_the_formal_lua_v22_baseline(self):
        self.assertEqual(1, self.manifest["contract_version"])
        self.assertEqual("main", self.manifest["baseline"]["branch"])
        self.assertEqual(22, self.manifest["baseline"]["ui_layout_version"])
        self.assertIn("local UI_LAYOUT_VERSION = 22", self.lua)

    def test_required_geometry_matches_contract(self):
        self.assert_contract_geometry(self.lobby, self.lobby_ui)
        self.assert_contract_geometry(self.dungeon, self.dungeon_ui)

    def test_lobby_has_all_nine_status_cards(self):
        for key, label, rect in self.lobby["status_cards"]:
            path = f"status_panel.status_{key}"
            with self.subTest(key=key):
                self.assertIn(path, self.lobby_ui)
                self.assertEqual(rect, [round(value) for value in self.lobby_ui[path][1]])
                card = self.lobby_ui[path][0]
                texts = [child.get("text", {}).get("items", [None])[0] for child in card.get("children", [])]
                self.assertIn(label, texts)

    def test_member_rows_expose_semantic_fields_and_management_actions(self):
        fields = self.lobby["member_rows"]["fields"]
        actions = self.lobby["member_rows"]["management_actions"]
        for index in range(1, self.lobby["member_rows"]["count"] + 1):
            base = f"team_panel.member_row_{index}"
            for field in fields:
                self.assertIn(f"{base}.label_member_{field}_{index}", self.lobby_ui)
            for action in actions:
                self.assertIn(f"{base}.button_{action}_{index}", self.lobby_ui)

    def test_formal_lobby_has_no_developer_ui(self):
        for path in self.lobby["forbidden_paths"]:
            self.assertNotIn(path, self.lobby_ui)
        serialized = json.dumps(self.lobby_dsl, ensure_ascii=False)
        self.assertNotIn("developer", serialized.lower())
        self.assertNotIn("开发面板", serialized)

    def test_action_parameters_match_lua(self):
        serialized = json.dumps(self.lobby_dsl, ensure_ascii=False)
        self.assertIn('"args": [2]', serialized)
        self.assertGreaterEqual(serialized.count('"max_player", 2'), 2)
        self.assertIn("local EXPECTED_PRIVATE_PLAYERS = 2", self.lua)

    def test_permission_rules_are_declared_in_generated_logic(self):
        serialized = json.dumps(self.lobby_dsl, ensure_ascii=False)
        for field in ["connected", "has_team", "is_captain", "matching", "launching", "aid"]:
            self.assertIn(field, serialized)
        for path in [
            "team_panel.button_leave_team",
            "team_panel.button_dismiss_team",
            "action_panel.button_private_dungeon",
            "action_panel.button_same_level_private_dungeon",
            "action_panel.button_match",
            "chat_panel.button_team_chat",
            "chat_panel.button_world_chat",
        ]:
            self.assertGreaterEqual(serialized.count(path), 2, path)
        self.assertIn("启动中", serialized)
        self.assertIn("取消匹配", serialized)
        self.assertIn("开始匹配", serialized)
        self.assertIn("INTEGER_COMPARE", serialized)

    def test_exit_is_confirmed_before_request_on_both_flows(self):
        for dsl in [self.lobby_dsl, self.dungeon_dsl]:
            serialized = json.dumps(dsl, ensure_ascii=False)
            self.assertIn("button_exit_cancel", serialized)
            self.assertIn("button_exit_confirm", serialized)
            self.assertIn("exit_confirm_overlay", serialized)

    def test_dungeon_hides_backdrop_and_copies_real_token_text(self):
        serialized = json.dumps(self.dungeon_dsl, ensure_ascii=False)
        self.assertIn("image_backdrop", serialized)
        self.assertIn("COPY_UI_TEXT_TO_CLIPBOARD", serialized)
        self.assertIn("button_copy_token", serialized)
        self.assertIn("关卡口令已复制到剪贴板", serialized)


if __name__ == "__main__":
    unittest.main()
