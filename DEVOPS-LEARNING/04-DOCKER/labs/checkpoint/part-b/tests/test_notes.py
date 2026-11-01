import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from notes import MAX_TITLE, validate_title  # noqa: E402


class ValidateTitleTest(unittest.TestCase):
    def test_strips_whitespace(self):
        self.assertEqual(validate_title("  mua sua  "), "mua sua")

    def test_rejects_empty(self):
        with self.assertRaises(ValueError):
            validate_title("   ")

    def test_rejects_non_string(self):
        with self.assertRaises(ValueError):
            validate_title(None)

    def test_rejects_too_long(self):
        with self.assertRaises(ValueError):
            validate_title("x" * (MAX_TITLE + 1))


if __name__ == "__main__":
    unittest.main()
