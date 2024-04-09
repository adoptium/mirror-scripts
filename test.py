import unittest
from unittest.mock import patch

from skaraMirror import (
    check_args,
    fetch_and_sort_tags,
    sort_jdk8_tags,
    sort_jdk11plus_tags,
)


class TestCheckArgs(unittest.TestCase):
    @patch("sys.argv", ["script_name", "jdk8u", "https://example.com/repo", "dev"])
    def test_with_full_arguments(self):
        args = check_args()
        self.assertEqual(args.jdk_version, "jdk8u")
        self.assertEqual(args.repo_url, "https://example.com/repo")
        self.assertEqual(args.branch, "dev")

    @patch("sys.argv", ["script_name", "jdk11u"])
    def test_with_minimum_arguments(self):
        args = check_args()
        self.assertEqual(args.jdk_version, "jdk11u")
        self.assertEqual(args.repo_url, "git@github.com:adoptium")
        self.assertEqual(args.branch, "master")


class TestFetchAndSortTags(unittest.TestCase):
    @patch(
        "skaraMirror.Repo"
    )  # Adjust the patch path according to your script's structure
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


if __name__ == "__main__":
    unittest.main()
