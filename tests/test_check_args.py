import unittest
from unittest.mock import patch

from skaraMirror import check_args


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
