import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import summarize  # noqa: E402


class SummarizeTest(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(summarize([3, 5, 2]), {"count": 3, "total": 10, "max": 5})

    def test_empty(self):
        self.assertEqual(summarize([]), {"count": 0, "total": 0, "max": 0})

    def test_rejects_negative(self):
        with self.assertRaises(ValueError):
            summarize([1, -2])

    def test_rejects_non_list(self):
        with self.assertRaises(ValueError):
            summarize("1,2,3")

    def test_rejects_bool(self):
        with self.assertRaises(ValueError):
            summarize([True, 2])


if __name__ == "__main__":
    unittest.main()
