import unittest
from unittest.mock import ANY, patch

from skaraMirror import clone_github_repo
from tests.supress_print import SuppressPrint


class TestCloneGitHubRepo(unittest.TestCase):
    @patch("skaraMirror.os.path.isdir")
    @patch("skaraMirror.Repo.clone_from")
    @patch("skaraMirror.tqdm")
    def test_clone_repo_not_exists(self, mock_tqdm, mock_clone_from, mock_isdir):
        """
        Test cloning a repository that does not already exist locally.
        """
        # Setup
        mock_isdir.return_value = False
        jdk_version = "jdk11u"
        repo_url = "git@github.com:adoptium/jdk11u.git"
        workspace = "/tmp/workspace"

        # Execute
        with SuppressPrint():
            clone_github_repo(jdk_version, repo_url, workspace)

        # Assert
        mock_isdir.assert_called_once_with("/tmp/workspace/jdk11u")
        mock_clone_from.assert_called_once_with(
            "git@github.com:adoptium/jdk11u.git", "/tmp/workspace/jdk11u", progress=ANY
        )

    @patch("skaraMirror.os.path.isdir")
    @patch("skaraMirror.Repo.clone_from")
    @patch("skaraMirror.tqdm")
    def test_clone_repo_exists(self, mock_tqdm, mock_clone_from, mock_isdir):
        """
        Test attempting to clone a repository that already exists locally.
        """
        # Setup
        mock_isdir.return_value = True
        jdk_version = "jdk11u"
        repo_url = "git@github.com:adoptium/jdk11u.git"
        workspace = "/tmp/workspace"

        # Execute
        with SuppressPrint():
            clone_github_repo(jdk_version, repo_url, workspace)

        # Assert
        mock_isdir.assert_called_once_with("/tmp/workspace/jdk11u")
        mock_clone_from.assert_not_called()  # Clone should not be called since repo exists
