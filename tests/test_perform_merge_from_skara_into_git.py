import unittest
from unittest.mock import ANY, MagicMock, patch

import git

from skaraMirror import perform_merge_from_skara_into_git
from tests.supress_print import SuppressPrint


class TestPerformMergeFromSkaraIntoGit(unittest.TestCase):
    @patch("skaraMirror.Repo")
    @patch("skaraMirror.tqdm")
    def test_successful_merge_from_skara(self, mock_tqdm, mock_repo):
        """
        Test successful fetching, rebasing, and pushing from the Skara remote.
        """
        # Setup
        workspace = "/tmp/workspace"
        github_repo = "jdk11u"
        branch = "master"

        # Mock remotes and methods
        mock_skara_remote = MagicMock()
        mock_repo.return_value.remotes.skara = mock_skara_remote
        mock_repo.return_value.git.rebase = MagicMock()
        mock_repo.return_value.remotes.origin.push = MagicMock()

        # Execute
        with SuppressPrint():
            perform_merge_from_skara_into_git(workspace, github_repo, branch)

        # Assert
        mock_skara_remote.fetch.assert_called_once()
        mock_repo.return_value.git.rebase.assert_called_once_with(f"skara/{branch}")
        mock_repo.return_value.remotes.origin.push.assert_called_once_with(
            branch, follow_tags=True, progress=ANY
        )

    @patch("skaraMirror.Repo")
    def test_git_command_error_during_fetch(self, mock_repo):
        """
        Test handling of GitCommandError during fetch operation from Skara remote.
        """
        # Setup to raise GitCommandError on fetch
        mock_repo.return_value.remotes.skara.fetch.side_effect = (
            git.exc.GitCommandError("fetch", "error")
        )

        workspace = "/tmp/workspace"
        github_repo = "jdk11u"
        branch = "master"

        # Expect the function to handle the exception and not crash
        with SuppressPrint():
            with self.assertRaises(SystemExit) as cm:
                perform_merge_from_skara_into_git(workspace, github_repo, branch)

        self.assertEqual(cm.exception.code, 1)
