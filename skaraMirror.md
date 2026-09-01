# OpenJDK Mirroring Script

This script automates the process of mirroring OpenJDK repositories from GitHub to Adoptium. It is designed to clone specific JDK versions, add upstream Skara repositories, and perform merges as necessary to keep the Adoptium mirrors up to date with OpenJDK development.

## Features

- **Clone Repositories:** Clone OpenJDK repositories for specific JDK versions.
- **Add Skara Upstream:** Configure Skara repository as a remote upstream.
- **Merge Changes:** Merge changes from Skara into the GitHub repository and manage branch merges for release and development purposes.

## Prerequisites

Python 3.6 or higher
Ensure you have Git installed and configured on your system.

## Installation

Install the required Python dependencies:

```bash
 pip install -r requirements.txt
```

## Usage

The script supports various operations based on command-line arguments:

```bash
./skaraMirror.py <jdk_version> [repo_url] [branch]
```

- `<jdk_version>`: The JDK version to mirror (e.g., jdk8u, jdk17u).
- `[repo_url]`: (Optional) URL of the repository to mirror. Defaults to git@github.com:adoptium.
- `[branch]`: (Optional) Branch to mirror. Defaults to master.

## Examples

Mirror the JDK 17 repository:

```bash
./skaraMirror.py jdk17u
```

Mirror the JDK 8 repository from a specific repository and branch:

```bash
./skaraMirror.py jdk8u git@github.com:custom_org custom_branch
```

## Running tests

The tests for this codebase live in `/tests`. If you want to run them you can use the following command:

```bash
python -m unittest discover tests
```
