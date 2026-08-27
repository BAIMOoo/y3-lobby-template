# -*- coding: utf-8 -*-
import sys
import tempfile
import unittest
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

import verify_skill


VALID_SKILL = """---
name: demo-skill
description: >
  A useful demo skill.
---

# Demo
"""


class VerifySkillTests(unittest.TestCase):
    def make_skill(self):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name) / "demo-skill"
        root.mkdir()
        (root / "SKILL.md").write_text(VALID_SKILL, encoding="utf-8")
        self.addCleanup(temporary.cleanup)
        return root

    def test_valid_frontmatter(self):
        self.assertEqual([], verify_skill.validate_frontmatter(self.make_skill()))

    def test_extra_frontmatter_key_is_rejected(self):
        root = self.make_skill()
        text = (root / "SKILL.md").read_text(encoding="utf-8")
        (root / "SKILL.md").write_text(
            text.replace("description: >", "metadata: invalid\ndescription: >"),
            encoding="utf-8",
        )
        self.assertTrue(verify_skill.validate_frontmatter(root))

    def test_missing_markdown_link_is_rejected(self):
        root = self.make_skill()
        (root / "SKILL.md").write_text(
            VALID_SKILL + "\n[Missing](references/missing.md)\n",
            encoding="utf-8",
        )
        errors = verify_skill.validate_markdown_links(root)
        self.assertEqual(1, len(errors))
        self.assertIn("references/missing.md", errors[0])

    def test_link_like_text_inside_inline_code_is_ignored(self):
        root = self.make_skill()
        (root / "SKILL.md").write_text(
            VALID_SKILL + "\n`Bind['name'](args[1], ...)`\n",
            encoding="utf-8",
        )
        self.assertEqual([], verify_skill.validate_markdown_links(root))


if __name__ == "__main__":
    unittest.main()
