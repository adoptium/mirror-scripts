import unittest
from unittest.mock import patch

from skaraMirror import fetch_and_sort_tags


class TestFetchAndSortTags(unittest.TestCase):
    @patch("skaraMirror.Repo")
    def test_fetch_and_sort_tags(self, mock_repo):
        # Mock git.tag() to return a list of tags
        mock_repo.return_value.git.tag.return_value = (
            "jdk-11.0.1+10\njdk-11.0.2+9\njdk-11.0.2+10"
        )

        # Assuming your sorting logic is correct and tested separately,
        # the expected result should reflect the sorted tags
        expected_sorted_tags = ["jdk-11.0.1+10", "jdk-11.0.2+9", "jdk-11.0.2+10"]

        # Adjust arguments as necessary for your function's parameters
        sorted_tags = fetch_and_sort_tags("/fake/repo/path", "jdk11", "master")

        self.assertEqual(sorted_tags, expected_sorted_tags)

    @patch("skaraMirror.Repo")
    def test_adopt_tags_excluded(self, mock_repo):
        # Mocking response with Adopt tags
        mock_repo.return_value.git.tag.return_value = "jdk-11.0.1+10\njdk-11.0.2_adopt"

        # Expected result with Adopt tags excluded
        expected_result = ["jdk-11.0.1+10"]
        result = fetch_and_sort_tags("/fake/repo/path", "jdk11", "master")
        self.assertEqual(result, expected_result)

    @patch("skaraMirror.Repo")
    def test_different_jdk_versions(self, mock_repo):
        # Mocking different responses based on JDK version
        mock_repo.return_value.git.tag.side_effect = [
            "jdk8u412-b07\njdk8u412-b06\njdk8u122-b11\njdk8u122-b11_adopt",  # JDK 8 tags
            "jdk-11.0.1+10\njdk-11.0.2+9",  # JDK 11 tags
        ]

        # JDK 8 expected result
        expected_jdk8 = ["jdk8u122-b11", "jdk8u412-b06", "jdk8u412-b07"]
        result_jdk8 = fetch_and_sort_tags("/fake/repo/path", "jdk8", "master")
        self.assertEqual(result_jdk8, expected_jdk8)

        # JDK 11 expected result
        expected_jdk11 = ["jdk-11.0.1+10", "jdk-11.0.2+9"]
        result_jdk11 = fetch_and_sort_tags("/fake/repo/path", "jdk11", "master")
        self.assertEqual(result_jdk11, expected_jdk11)
