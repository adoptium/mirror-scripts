# Upstream tag mirroring strategy

How [`skaraMirror.sh`](skaraMirror.sh) decides which upstream build tags to mirror, and into which Adoptium mirror branch each one goes.

Upstream branch names are not a reliable key for tags. For example, in jdk21u the tags `jdk-21.0.13.0.2+1` and `jdk-21.0.13.0.3+1` only appear on a branch named `jdk21.0.13.1`. So the **tag** chooses the mirror branch. The upstream branch being processed only decides which tags are visible.

## The process

The [`Jenkinsfile`](Jenkinsfile) runs `skaraMirror.sh` once per active upstream branch (a commit in the last three months, `pr/*` skipped), with the default branch last. For a given `BRANCH`:

1. **Target release branch.** `release` if `BRANCH` is the default branch, otherwise `release_$BRANCH`.
2. **Floor.**
   - If the target exists, the latest `_adopt` tag on it, with `_adopt` removed.
   - Otherwise (or if it has no `_adopt` tag), the latest build tag on `BRANCH`.
3. **Candidates.** Tags visible on `BRANCH` from the floor onwards, oldest first, with no `<tag>_adopt` anywhere in the mirror repo. For each one:
   - **Shape of the target release branch:** merge it into the target and tag it `<tag>_adopt`.
   - **Another shape:** work out its own release branch from the tag (see below).
     - If that branch exists and the tag is newer than its latest `_adopt` tag, merge and tag it.
     - If it does not exist, create it from the tag, apply the Adoptium patches, and tag it.
4. Push the branches and the new `_adopt` tags.

Building on that:

- **No candidates is not an error.** The job logs it and exits 0.
- **`tagAdopt` is strict.** A candidate has no `_adopt` tag, so finding one at tagging time is a bug. The job fails and lists the branches that contain it.
- **Default branch last.** A tag visible from both the default branch and a versioned branch (for example `jdk-27.0.1+9`, tagged on `jdk27.0.1` and later merged into `master`) is handled by the versioned branch's run first. The default-branch run sees its `_adopt` tag and skips it.
- **`releaseTagExcludeList`.** The optional env var of space separated tags that are never merged or `_adopt` tagged is honoured.

### Release branch name for a tag

| Tag | Release branch |
|---|---|
| Master shape, seen from the default branch | `release` |
| Master shape, seen from a branch with the same version (`jdk28` for `jdk-28+N`, `jdk27.0.2` for `jdk-27.0.2+N`, `openjdk8u512` for `jdk8u512-bN`) | `release_<BRANCH>` |
| Master shape, any other version, seen from another branch | not handled: the default-branch run owns it |
| Any other shape, for example `jdk-27.0.1.0.3+1` | `release_jdk27.0.1.0.3` (`release_` plus the version, without `+BB` or the `-` after `jdk`) |
| jdk8u, version not ending in `2`, for example `jdk8u504-b01` | `release_openjdk8u504` |

"Master shape" is the form the default branch uses in that repo. Only tags in the repo's family are eligible; the family is a strict regex, so tags of other families (for example head-style `jdk-27+35` in jdk27u) are never picked up.

| Repo | Family | Master shape |
|---|---|---|
| jdk (head) | `^jdk-[0-9]+\+[0-9]+$` | `jdk-MM+BB` |
| jdk11u to jdk27u, and any future `jdkMMu` | `^jdk-MM\.0\.[0-9]+(\.[0-9]+)*\+[0-9]+$` | `jdk-MM.0.V+BB` (exactly three components) |
| jdk8u | `^jdk8u[0-9]+-b[0-9]+$` | `jdk8uNN2-bBB` (version ends in `2`) |
| aarch32-port-jdk8u | jdk8u family plus `-aarch32-[0-9]+` | jdk8u master shape plus `-aarch32-<date>` |

`MM` is parsed from the repo name. `-ga` tags, `+0` / `-b00` fork point tags and `_adopt` tags are never candidates. There is no per-repo version logic apart from jdk8u, so a future repo such as jdk28u needs no script change.

### Creating a new release branch

A missing target is created **from the first tag that needs it**, with the Adoptium patches applied (gated on `README.JAVASE` not existing). Further tags for that branch are merged and tagged in order. The same applies to `release` in a brand new repo.

## Dev branches

- `dev` follows the latest commits of the default branch on every run, **whether or not there is a new tag**, merged with `release`.
- When `release_<B>` exists, `dev_<B>` follows the latest commits of upstream branch `B` in the same way.
- `dev_<suffix>` is created or advanced for every `release_<suffix>` created or advanced in the run, from the matching upstream branch if one exists (otherwise from the tag `release_<suffix>` was created from), merged with `release_<suffix>`.

## `-ga` tags and the release trigger

`-ga` tags are never mirrored or `_adopt` tagged. The build tag on the same commit is. [`triggerReleasePipeline.sh`](triggerReleasePipeline.sh) finds `<tag>_adopt` with `git ls-remote --tags` across the whole repo, and ignores `+0` / `-b00` tags when it picks the build tag at a `-ga` commit. Upstream puts the next version's fork point tag on the GA commit (for example `jdk-21.0.13.0.2+0` next to `jdk-21.0.13+9`), and that tag is never `_adopt` tagged.

## Consequences

- A new release branch starts at its first tag. Earlier tags on the same line are never back-filled.
- A first run starts at the floor, so old history (jdk8u below 8u212, old `.1` branches) is out of scope.
- A release branch with no `_adopt` tag at all (a new repo, or jdk27u today, where `_adopt` tags only live on `release_*`) takes only the newest tag on its first run.

## Examples

| Run | Result |
|---|---|
| jdk21u `BRANCH=master`, `release` last at `jdk-21.0.13+9_adopt`, then `jdk-21.0.14+1` appears | `jdk-21.0.14+1` is merged into `release` and `_adopt` tagged. |
| jdk21u `BRANCH=jdk21.0.13.1` | `jdk-21.0.13.0.2+1` creates `release_jdk21.0.13.0.2` from itself. |
| jdk27u `BRANCH=jdk27.0.1`, first run | `release_jdk27.0.1` is created from `jdk-27.0.1+9`. Later runs find nothing. |
| jdk27u `BRANCH=jdk27.0.2`, no tags yet | Quiet exit. |
| jdk8u `BRANCH=openjdk8u504` | `release_openjdk8u504` is created from the latest `jdk8u504-bNN` tag. |
| head `BRANCH=jdk27`, first run | `release_jdk27` is created from the latest `jdk-27+N` tag. |

## DRY_RUN

`DRY_RUN=true` prints "tag → target (create or merge)" for every tag and changes nothing in the mirror. Every push goes through `gitPush`, which only prints the push when `DRY_RUN=true`. The local workspace is still fetched. Run it against the live mirrors before the first real run.

## Tests

`tests/run.sh` (or `tests/run.sh <name-filter>`) runs the scenarios in `tests/scenarios/` against synthetic local bare repositories for the upstream and the mirror. No network access is needed. Each scenario asserts the exact set of `_adopt` tags per mirror branch. They cover:

- the `jdk-27.0.1+9` case (tag on `jdk27.0.1`, branch later merged into `master`) and the jdk21u shape;
- arbitrary upstream branch names, legacy `_adopt` tags, late patch branches and two tags on one commit;
- the head repo, jdk27u, jdk8u (including `-ga` and `-b00`), aarch32 and a synthetic future repo `jdk99u`;
- quiet exits, strict `tagAdopt`, `DRY_RUN`, `dev` following upstream, the `-ga` release trigger and a workspace origin mismatch.

[`skaraMirror.sh`](skaraMirror.sh) accepts the optional env vars `SKARA_REPO_URL` (upstream location), `MIRROR_WORKSPACE` and `MIRROR_PATCHES` for the tests. They are not used in production.
