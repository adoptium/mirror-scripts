import unittest

from skaraMirror import sort_jdk11plus_tags


class TestSortJDK11PlusTags(unittest.TestCase):
    def test_sorting_basic(self):
        # Test basic sorting with mixed versions and build numbers
        tags = ["jdk-11.0.2+9", "jdk-11.0.10+3", "jdk-11.0.1+13"]
        expected_sorted_tags = ["jdk-11.0.1+13", "jdk-11.0.2+9", "jdk-11.0.10+3"]
        self.assertEqual(sort_jdk11plus_tags(tags), expected_sorted_tags)

    def test_sorting_with_patch_numbers(self):
        # Test sorting with patch numbers
        tags = ["jdk-11.0.2+9", "jdk-11.0.2.1+9", "jdk-11.0.2+10"]
        expected_sorted_tags = ["jdk-11.0.2+9", "jdk-11.0.2+10", "jdk-11.0.2.1+9"]
        self.assertEqual(sort_jdk11plus_tags(tags), expected_sorted_tags)

    def test_sorting_with_mixed_versions(self):
        # Test sorting with completely mixed versions and builds
        tags = ["jdk-12.0.1+12", "jdk-11.0.2+9", "jdk-13+33", "jdk-11.0.1+13"]
        expected_sorted_tags = [
            "jdk-11.0.1+13",
            "jdk-11.0.2+9",
            "jdk-12.0.1+12",
            "jdk-13+33",
        ]
        self.assertEqual(sort_jdk11plus_tags(tags), expected_sorted_tags)

    def test_sorting_with_adopt_versions(self):
        # Test sorting with GA versions
        tags = ["jdk-11.0.2", "jdk-11.0.2+9", "jdk-11.0.2_adopt"]
        expected_sorted_tags = ["jdk-11.0.2", "jdk-11.0.2+9"]
        self.assertEqual(sort_jdk11plus_tags(tags), expected_sorted_tags)
