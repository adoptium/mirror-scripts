import unittest

from skaraMirror import sort_jdk8_tags


class TestSortJDK8Tags(unittest.TestCase):
    def test_sorting_basic(self):
        # Test basic sorting with mixed versions and build numbers
        tags = ["jdk8u122-b11", "jdk8u412-b06", "jdk8u412-b07"]
        expected_sorted_tags = ["jdk8u122-b11", "jdk8u412-b06", "jdk8u412-b07"]
        self.assertEqual(sort_jdk8_tags(tags), expected_sorted_tags)

    def test_sorting_with_adopt_versions(self):
        # Test sorting with Adopt versions
        tags = ["jdk8u122-b11", "jdk8u412-b06", "jdk8u412-b07_adopt"]
        expected_sorted_tags = ["jdk8u122-b11", "jdk8u412-b06"]
        self.assertEqual(sort_jdk8_tags(tags), expected_sorted_tags)
