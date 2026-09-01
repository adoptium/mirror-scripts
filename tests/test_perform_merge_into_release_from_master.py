import unittest
from unittest.mock import MagicMock, PropertyMock, patch

import git

from skaraMirror import perform_merge_into_release_from_master
from tests.supress_print import SuppressPrint


class TestPerformMergeIntoReleaseFromMaster(unittest.TestCase):
    def setUp(self):
        self.mock_repo = MagicMock(spec=git.Repo)

        # Mock the master branch as initially the only branch
        self.mock_master_branch = MagicMock(spec=git.Head, name="master")

        # Prepare a mock for the repo's heads that supports item getting and iteration
        self.mock_heads = {"master": self.mock_master_branch}

        # Use PropertyMock to simulate the repo.heads dynamic nature
        type(self.mock_repo).heads = PropertyMock(side_effect=lambda: self.mock_heads)

        # Mock remotes setup
        self.mock_origin_remote = MagicMock(spec=git.Remote, name="origin")
        self.mock_repo.remotes = MagicMock()
        self.mock_repo.remotes.__getitem__.side_effect = (
            lambda x: self.mock_origin_remote if x == "origin" else None
        )

        # Mock fetching, pushing, and tag listing
        self.mock_origin_remote.fetch = MagicMock()
        self.mock_origin_remote.push = MagicMock()
        self.mock_tags = ["jdk-11.0.1+10", "jdk-11.0.2+9"]
        self.mock_repo.git.tag.return_value = "\n".join(self.mock_tags)

    @patch("skaraMirror.subprocess.run")
    @patch("skaraMirror.Repo")
    @patch("skaraMirror.tqdm")
    def test_release_branch_does_not_exist(
        self, mock_tqdm, mock_repo_class, mock_subprocess_run
    ):
        mock_repo_class.return_value = self.mock_repo

        # Assert setup: Verify initially no 'release' branch
        self.assertNotIn("release", self.mock_repo.heads)

        # Simulate the function's execution
        with SuppressPrint():
            perform_merge_into_release_from_master("/tmp/workspace", "jdk11u", "master")

        # verify that the patch was applied to the branch
        mock_subprocess_run.assert_called()

        # Dynamically add 'release' branch to simulate its creation during function execution
        self.mock_heads["release"] = MagicMock(spec=git.Head, name="release")

        # Verify 'release' branch creation logic was triggered
        self.assertIn("release", self.mock_repo.heads)
        self.mock_repo.git.checkout.assert_called_once_with(
            "-b", "release", "origin/release"
        )
        self.mock_repo.git.tag.assert_called()
