import unittest
from unittest.mock import patch, MagicMock

from skaraMirror import add_skara_upstream
from tests.supress_print import SuppressPrint


class TestAddSkaraUpstream(unittest.TestCase):
    @patch("skaraMirror.Repo")
    def test_add_skara_remote_not_exist(self, mock_repo):
        # Setup: Configure the mock repo object
        mock_repo.return_value.remotes = MagicMock()
        mock_repo.return_value.remotes.__iter__.return_value = []

        # Define your function parameters
        workspace = "/tmp/workspace"
        jdk_version = "jdk11u"
        skara_repo = "https://github.com/openjdk/skara"
        branch = "master"

        # Execute the function
        with SuppressPrint():
            add_skara_upstream(workspace, jdk_version, skara_repo, branch)

        # Assertions: Check if the remote was added
        mock_repo.return_value.create_remote.assert_called_once_with(
            "skara", skara_repo
        )

    @patch("skaraMirror.Repo")
    def test_skara_remote_already_exists(self, mock_repo):
        # Setup: Simulate existing 'skara' remote
        mock_remote = MagicMock()
        mock_remote.name = "skara"
        mock_repo.return_value.remotes = MagicMock()
        mock_repo.return_value.remotes.__iter__.return_value = [mock_remote]

        # Execute the function with the same parameters as before
        with SuppressPrint():
            add_skara_upstream(
                "/tmp/workspace", "jdk11u", "https://github.com/openjdk/skara", "master"
            )

        # Assertions: Ensure create_remote was not called since 'skara' exists
        mock_repo.return_value.create_remote.assert_not_called()
