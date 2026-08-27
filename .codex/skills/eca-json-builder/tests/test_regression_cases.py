# -*- coding: utf-8 -*-
import json
import sys
import unittest
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
CASE_DIR = Path(__file__).resolve().parent / "regressions"
sys.path.insert(0, str(SKILL_DIR))

import gen_trigger


def resolve_pointer(value, pointer):
    if pointer == "":
        return value
    if not pointer.startswith("/"):
        raise ValueError(f"JSON pointer must start with '/': {pointer!r}")
    current = value
    for raw_part in pointer[1:].split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        current = current[int(part)] if isinstance(current, list) else current[part]
    return current


class RegressionCaseTests(unittest.TestCase):
    def test_json_regression_cases(self):
        paths = sorted(CASE_DIR.glob("*.json"))
        self.assertTrue(paths, "tests/regressions must contain at least one JSON case")

        for path in paths:
            with self.subTest(case=path.name):
                case = json.loads(path.read_text(encoding="utf-8-sig"))
                self.assertEqual("build_arg", case["kind"])
                actual = gen_trigger.build_arg(
                    case["value"],
                    case["expected_type"],
                    case["index"],
                    gen_trigger.eid_factory(100),
                )
                for assertion in case["assertions"]:
                    self.assertEqual(
                        assertion["equals"],
                        resolve_pointer(actual, assertion["pointer"]),
                        assertion["pointer"],
                    )


if __name__ == "__main__":
    unittest.main()
