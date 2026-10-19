#!/usr/bin/env python3

import argparse
import logging
import os
import re
import subprocess

from git import GitCommandError, RemoteProgress, Repo
from tqdm import tqdm


class CloneProgress(RemoteProgress):
    def __init__(self):
        super().__init__()
        self.pbar = tqdm()

    def update(self, op_code, cur_count, max_count=None, message=""):
        self.pbar.total = max_count
        self.pbar.n = cur_count
        self.pbar.refresh()


def check_args():
    parser = argparse.ArgumentParser(
        description="Mirror OpenJDK GitHub repos to Adoptium."
    )
    parser.add_argument(
        "jdk_version", help="JDK version to mirror (e.g. jdk8u, jdk17u)", type=str
    )
    parser.add_argument(
        "repo_url",
        nargs="?",
        default="git@github.com:adoptium",
        help="URL of the repository to mirror (optional)",
        type=str,
    )
    parser.add_argument(
        "branch",
        nargs="?",
        default="master",
        help="Branch to mirror (optional)",
        type=str,
    )

    args = parser.parse_args()
    return args


def clone_github_repo(jdk_version, repo_url, workspace):
    """
    Clone the specified GitHub repository into the workspace.
    """
    repo_name = jdk_version
    local_repo_path = os.path.join(workspace, repo_name)

    # If we don't have a clone locally then clone it from adoptium/$repo_url.git
    if not os.path.isdir(local_repo_path):
        print(f"Cloning {repo_name} into {local_repo_path}...")
        try:
            Repo.clone_from(repo_url, local_repo_path, progress=CloneProgress())
            print(f"Repository {repo_name} cloned successfully.")
        except GitCommandError as error:
            print(f"Failed to clone repository: {error}")
            exit(1)
    else:
        print(f"Repository {repo_name} already exists at {local_repo_path}.")


def add_skara_upstream(workspace, jdk_version, skara_repo, branch):
    """
    Add the Skara repository as a remote and check out the specified branch.
    """
    local_repo_path = os.path.join(workspace, jdk_version)
    try:
        # Open the existing repository
        repo = Repo(local_repo_path)

        # Fetch origin
        repo.remotes.origin.fetch()

        # Check if the remote named 'skara' exists, add if not
        if "skara" not in [remote.name for remote in repo.remotes]:
            print(f"Initial setup of: {skara_repo}")
            repo.create_remote("skara", skara_repo)

        # Check out the specified branch
        if branch in repo.heads:
            # Branch exists locally, just check it out
            repo.heads[branch].checkout()
            # Reset the branch to match the upstream branch
            print(f"Resetting {branch} to match upstream...")
            repo.git.reset("--hard", f"origin/{branch}", with_exceptions=False)
        elif f"origin/{branch}" in repo.refs:
            # Branch exists on remote, create it locally
            repo.create_head(branch).checkout()
        else:
            # Branch does not exist in the remote repository
            print(
                f"Branch '{branch}' does not exist in the remote repository yet. Using Skara's default branch."
            )
            repo.remotes.skara.fetch()
            # Create master branch
            repo.create_head(branch, f"skara/{branch}").checkout()

    except GitCommandError as error:
        print(f"Git command failed: {error}")
        exit(1)
    except Exception as e:
        print(f"An error occurred: {e}")
        exit(1)


def perform_merge_from_skara_into_git(workspace, github_repo, branch):
    """
    Merge the changes from the Skara repository into the GitHub repository.
    """
    local_repo_path = os.path.join(workspace, github_repo)

    try:
        # Open the existing repository
        repo = Repo(local_repo_path)

        # Fetch from Skara remote
        print("Fetching updates from Skara remote...")
        repo.remotes.skara.fetch(**{"tags": True})

        # Rebase the current branch with Skara's branch
        print(f"Rebasing {branch} with Skara/{branch}...")
        repo.git.rebase(f"skara/{branch}")

        # Push the changes to origin
        print(f"Pushing {branch} to origin...")
        repo.remotes.origin.push(branch, follow_tags=True, progress=CloneProgress())

    except GitCommandError as error:
        print(f"Git command failed: {error}")
        exit(1)
    except Exception as e:
        print(f"An error occurred: {e}")
        exit(1)


def fetch_and_reset_repo(repo):
    """
    Abort any ongoing merge and reset the repository, then fetch all tags.
    """
    # Abort any ongoing merge and reset
    repo.git.merge("--abort", with_exceptions=False)
    repo.git.reset("--hard", with_exceptions=False)

    # Fetch all tags
    for remote in repo.remotes:
        print(f"Fetching latest from {remote}")
        remote.fetch(**{"tags": True})


def perform_merge_into_release_from_master(workspace, github_repo, branch):
    """
    Merge master(New tagged builds only) into release branch as we build
    off release branch at the Adoptium JDK Build farm for release builds
    release branch contains patches that Adoptium JDK has beyond upstream OpenJDK tagged builds.
    """
    local_repo_path = os.path.join(workspace, github_repo)

    try:
        # Open the existing repository
        repo = Repo(local_repo_path)

        fetch_and_reset_repo(repo)

        sorted_build_tags = fetch_and_sort_tags(
            local_repo_path, github_repo, f"origin/{branch}"
        )

        # Check if release branch exits
        if "release" not in repo.heads:
            if repo.git.rev_parse("--verify", "origin/release", with_exceptions=False):
                repo.git.checkout("-b", "release", "origin/release")
            else:
                # Get the currentBuildTag from sorted_tags
                currentBuildTag = sorted_build_tags[-1]
                print(f"Creating release branch from {currentBuildTag}")
                repo.git.checkout("-b", "release", currentBuildTag)
        else:
            print("Release branch already exists. Resetting to origin/release...")
            repo.heads["release"].checkout()
            repo.git.reset("--hard", "origin/release", with_exceptions=False)

        # Apply patches if required
        apply_patches_if_needed(workspace, github_repo)

        # Find the latest and previous release tags that is not in releaseTagExcludeList
        sortedReleaseTags = fetch_and_sort_tags(local_repo_path, github_repo, "release")
        currentReleaseTag = ""

        for tag in sortedReleaseTags:
            # Check if tag is in the env var releaseTagExcludeList, if so it can't be the current tag
            if tag in os.getenv("releaseTagExcludeList", "").split():
                print(f"Skipping excluded tag {tag} from current list")
                continue

            if tag.endswith("-b00") or tag.endswith("+0"):
                print(f"Skipping fork point tag {tag} from current list")
                continue

            currentReleaseTag = tag

        print(f"Current release build tag: {currentReleaseTag}")

        # Merge any new builds since current release build tag
        foundCurrentReleaseTag = False
        newAdoptTags = []

        for tag in sorted_build_tags:
            if not foundCurrentReleaseTag:
                if tag == currentReleaseTag:
                    foundCurrentReleaseTag = True

            else:
                # Check if tag is in the releaseTagExcludeList, if so do not bring it into the release branch
                # and do not create an _adopt tag
                if tag in os.getenv("releaseTagExcludeList", "").split():
                    print(f"Skipping excluded tag {tag} from merge")
                    continue
                if tag.endswith("-b00") or tag.endswith("+0"):
                    print(f"Skipping fork point tag {tag} from merge")
                    continue

                print(f"Merging build tag {tag} into release branch")
                repo.git.merge(
                    "-m", f"Merging build tag {tag} into release branch", tag
                )
                print(f"Tagging {tag} as {tag}_adopt")
                adoptTag = f"{tag}_adopt"
                repo.create_tag(
                    adoptTag, ref="release", message=f"Merged {tag} into release"
                )
                newAdoptTags.append(adoptTag)

        if repo.git.rev_parse(
            "-q", "--verify", "origin/release", with_exceptions=False
        ):
            print(repo.git.log("--oneline", "origin/release..release"))

        # Find the latest and previous release tags that is not in releaseTagExcludeList
        sortedReleaseTags = fetch_and_sort_tags(local_repo_path, github_repo, "release")
        for tag in sortedReleaseTags:
            # Check if tag is in the releaseTagExcludeList, if so it can't be the current tag
            if tag in os.getenv("releaseTagExcludeList", "").split():
                print(f"Skipping excluded tag {tag} from current list")
                continue

            if tag.endswith("-b00") or tag.endswith("+0"):
                print(f"Skipping fork point tag {tag} from current list")
                continue

            prevReleaseTag = currentReleaseTag
            currentReleaseTag = tag

        print(f"New release build tag: {currentReleaseTag}")
        repo.remotes.origin.push("release", follow_tags=True, progress=CloneProgress())

        # Check if the last two build tags are the same commit, and ensure we have tagged both _adopt tags
        if prevReleaseTag:
            prevCommit = repo.git.rev_list("-n", "1", prevReleaseTag)
            currentCommit = repo.git.rev_list("-n", "1", currentReleaseTag)

            if prevCommit == currentCommit:
                print(
                    "Current build tag commit is same as previous build tag commit: "
                    + f"{prevReleaseTag} == {currentReleaseTag}"
                )
                prevReleaseAdoptTag = f"{prevReleaseTag}_adopt"
                currentReleaseAdoptTag = f"{currentReleaseTag}_adopt"

                if repo.git.tag("-l", prevReleaseAdoptTag):
                    if not repo.git.tag("-l", currentReleaseAdoptTag):
                        print("here")
                        print(
                            f"Tagging new current release tag {currentReleaseAdoptTag} "
                            + f"which is same commit as the previous {prevReleaseAdoptTag}"
                        )
                        repo.create_tag(
                            currentReleaseAdoptTag,
                            ref=currentReleaseTag,
                            message=f"Merged {currentReleaseTag} into release",
                        )
                        newAdoptTags.append(currentReleaseAdoptTag)

        # Ensure all new _adopt tags are pushed in case no new commits were pushed, eg.multiple tags on same commit
        for tag in newAdoptTags:
            print(f"Pushing new tag: {tag}")
            repo.remotes.origin.push(tag)

        print("Merging complete.")

    except GitCommandError as error:
        print(f"Git command failed: {error}")
        exit(1)
    except Exception as e:
        print(f"An error occurred: {e}")
        exit(1)


def perform_merge_into_dev_from_master(workspace, github_repo, branch):
    """
    Merge master(HEAD) into dev as we build off dev at the Adoptium JDK Build farm for Nightlies
    dev contains patches that Adoptium JDK has beyond upstream OpenJDK
    """
    local_repo_path = os.path.join(workspace, github_repo)

    try:
        # Open the existing repository
        repo = Repo(local_repo_path)

        fetch_and_reset_repo(repo)

        # Check if dev branch exits
        if "dev" not in repo.heads:
            if repo.git.rev_parse("--verify", "origin/dev", with_exceptions=False):
                repo.create_head("dev", "origin/dev")
            else:
                repo.create_head("dev", f"origin/{branch}")
        else:
            print("dev branch already exists. Resetting to origin/dev...")
            # Checkout the dev branch
            release_branch = repo.heads["dev"].checkout()
            repo.git.reset("--hard", "origin/dev")

        # Checkout the dev branch
        release_branch = repo.heads["dev"]
        release_branch.checkout()

        sorted_tags = fetch_and_sort_tags(local_repo_path, github_repo, "dev")
        currentDevTag = sorted_tags[-1]
        print(f"Current dev tag: {currentDevTag}")

        # Merge master "HEAD"
        print(f"Merging origin/{branch} HEAD into dev branch")
        repo.git.merge(
            "-m", f"Merging origin/{branch} HEAD into dev", f"origin/{branch}"
        )

        # Merge latest patches from "release" branch
        print("Merging latest patches from release branch")
        repo.git.merge(
            "-m", "Merging latest patches from release branch", "origin/release"
        )

        if repo.git.rev_parse("-q", "--verify", "origin/dev", with_exceptions=False):
            print(repo.git.log("--oneline", "origin/dev..dev"))

        sorted_tags = fetch_and_sort_tags(local_repo_path, github_repo, "dev")
        currentDevTag = sorted_tags[-1]
        print(f"New dev tag: {currentDevTag}")

        # Push the changes to origin/dev
        repo.remotes.origin.push("dev", follow_tags=True, progress=CloneProgress())

    except GitCommandError as error:
        print(f"Git command failed: {error}")
        exit(1)
    except Exception as e:
        print(f"An error occurred: {e}")
        exit(1)


def apply_patches_if_needed(workspace, github_repo):
    """
    Apply patches if the repository meets certain conditions.
    """
    print(f"Checking if patches need to be applied for {github_repo}")

    # actions ignore branch patch is for > jdk11u
    if github_repo not in ["jdk8u", "aarch32-port-jdk8u", "jdk11u"]:
        main_workflow_file = os.path.join(
            workspace, github_repo, ".github", "workflows", "main.yml"
        )

        # Check if the file exists and the patch hasn't been applied yet
        if os.path.exists(main_workflow_file) and not is_patch_applied(
            main_workflow_file, "- dev"
        ):
            patch_file = os.path.join(
                os.getcwd(), "patches", "actions-ignore-branches.patch"
            )
            apply_patch(patch_file, os.path.join(workspace, github_repo))

    # README.JAVASE patch needed for all repos
    readme_file = os.path.join(workspace, github_repo, "README.JAVASE")
    if not os.path.exists(readme_file):
        patch_file = os.path.join(os.getcwd(), "patches", "readme-javase.patch")
        apply_patch(patch_file, os.path.join(workspace, github_repo))


def is_patch_applied(file_path, search_string):
    """
    Checks if a search string is present in a file.
    """
    with open(file_path, "r") as file:
        if search_string in file.read():
            return True
    return False


def apply_patch(patch_file, repo_path):
    """
    Apply a specified patch file to the repository.
    """
    if os.path.exists(patch_file):
        try:
            print(f"Applying patch: {patch_file}")
            subprocess.run(["git", "am", patch_file], check=True, cwd=repo_path)
            print("Patch applied successfully.")
        except subprocess.CalledProcessError as e:
            print(f"Failed to apply patch {patch_file}: {e}")
            subprocess.run(["git", "am", "--abort"], cwd=repo_path)
            exit(1)
    else:
        print(f"Patch file not found: {patch_file}")


def sort_jdk11plus_tags(tags):
    """
    JDK11+ tag sorting:
    We use sort and tail to choose the latest tag in case more than one refers the same commit.
    Versions tags are formatted: jdk-V[.W[.X[.P]]]+B; with V, W, X, P, B being numeric.
    Transform "-" to "." in tag so we can sort as: "jdk.V[.W[.X[.P]]]+B"
    Transform "+" to ".0.+" during the sort so that .P (patch) is defaulted to "0" for those
    that don't have one, and the trailing "." to terminate the 5th field from the +.
    """
    # Filter out tags with '_adopt' in their name
    tags = [tag for tag in tags if "_adopt" not in tag]

    # Preprocess tags for sorting
    # Replace 'jdk-' with 'jdk.' for consistency in splitting
    # Add a pseudo patch number '.0.0' before '+' to ensure proper sorting of tags without a patch number
    tags = ["jdk." + tag[4:].replace("+", ".0.0+") for tag in tags]

    def tag_sort_key(tag):
        # Split the tag into components for sorting
        # First, handle the version part, splitting by '.' and converting numbers to integers
        parts = tag.split(".")
        version_parts = [
            int(part) if part.isdigit() else part for part in parts[:-1]
        ]  # Exclude the build part for now

        # Extract and process the build number, which follows the last '+' symbol
        # Replace the pseudo '.99999+' used for sorting with a large number to ensure it sorts correctly
        build_part = parts[-1].split("+")
        build_number = (
            int(build_part[1]) if len(build_part) > 1 and build_part[1].isdigit() else 0
        )

        # Combine version parts and build number into one tuple for sorting
        return (*version_parts, build_number)

    # Sort the tags using the defined key
    tags.sort(key=tag_sort_key)

    # Post-process sorted tags to revert changes made for sorting
    # This involves replacing '.0.0+' back to '+', and 'jdk.' to 'jdk-'
    sorted_tags = [tag.replace(".0.0+", "+").replace("jdk.", "jdk-") for tag in tags]

    return sorted_tags


def sort_jdk8_tags(tags):
    """
    JDK8 tag sorting:
    We use sort and tail to choose the latest tag in case more than one refers the same commit.
    Versions tags are formatted: jdkVu[.W]-bB; with V, W, B being numeric.
    """
    # Filter out tags with '_adopt' in their name
    tags = [tag for tag in tags if "_adopt" not in tag]

    # First, sort on build number (B):
    tags = sorted(tags, key=lambda x: int(x.split("-b")[1]))

    # Add a number to the beginning of each tag for sorting
    tags = [f"{i:02d} {tag}" for i, tag in enumerate(tags, 1)]

    # # Second, (stable) sort on (V), (W)
    tags = sorted(tags, key=lambda x: int(x.split("jdk8u")[1].split("-b")[0]))

    # Remove the number from the beginning of each tag
    tags = [tag.split(" ", 1)[1] for tag in tags]

    return tags


def fetch_and_sort_tags(repo_path, version, branch):
    """
    Fetch tags from the repository and sort them according to the given command.
    """
    # convert version such as jdk22u to 22
    version = re.search(r"\d+", version).group()
    repo = Repo(repo_path)
    if version == "8":
        tag_search_cmd = f"jdk{version}*-*"
    else:
        tag_search_cmd = f"jdk-{version}*+*"

    tags = repo.git.tag("--merged", branch, tag_search_cmd).split("\n")

    if version == "8":
        sorted_tags = sort_jdk8_tags(tags)
    else:
        sorted_tags = sort_jdk11plus_tags(tags)

    return sorted_tags


def main():
    # Parse command line arguments
    args = check_args()

    # Set up logging
    logging.basicConfig(level=logging.INFO)

    # If WORKSPACE env var is set, use it, otherwise use the current directory/workspace
    workspace = os.getenv("WORKSPACE", os.path.join(os.getcwd(), "workspace"))

    skara_repo = f"https://github.com/openjdk/{args.jdk_version}"

    git_repo = f"{args.repo_url}/{args.jdk_version}"

    # Perform operations
    clone_github_repo(args.jdk_version, git_repo, workspace)
    add_skara_upstream(workspace, args.jdk_version, skara_repo, args.branch)
    perform_merge_from_skara_into_git(workspace, args.jdk_version, args.branch)
    perform_merge_into_release_from_master(workspace, args.jdk_version, args.branch)
    perform_merge_into_dev_from_master(workspace, args.jdk_version, args.branch)


if __name__ == "__main__":
    main()
