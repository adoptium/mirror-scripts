# OpenJDK Mirror Scripts

These scripts are run at https://ci.adoptopenjdk.net/view/git-mirrors/ and are responsible for updating the AdoptOpenJDK clones of the various OpenJDK mecurial forests that we are interested in building.

## For developers

OpenJDK Source Control repositories are now managed using the GitHub (project Skara). The scripts within the projects that use Mercurial repositories
from github.com/adoptium/jdk\<NN\>u , would not be invalidated but would be converted to Git. The existing master Mercurial repos will at least be kept as read-only archives for a defined transition period. Longer term, a Mercurial URL to Git URL translator might be put into place.

There is a program put in place to convert OpenJDK Mercurial repositories to a Git repository. It uses the git-fast-import protocol to import Mercurial changesets into Git, and it adjusts existing commit messages to align with Git best practices. A commit message for the Mercurial jdk/jdk repository has this structure:

JdkHgCommitMessage : BugIdLine+ SummaryLine? ReviewersLine ContributedByLine?

BugIdLine : /[0-9]{8}/ ": " Text

SummaryLine : "Summary: " Text

ReviewersLine : "Reviewed-by: " Username (", " Username)* "\n"

ContributedByLine : "Contributed-by: " Text

Username : /[a-z]+/

Text : /[^\n]+/ "\n"
A commit message for the Git jdk/jdk repository will have a somewhat different structure:

JdkGitCommitMessage : BugIdLine+ Body? Trailers

BugIdLine : /[0-9]{8}/ ": " Text

Body : BlankLine Text*

Trailers : BlankLine Co-authors? Reviewers

Co-authors : (BlankLine Co-author )+

Co-author : "Co-authored-by: " Real-name <Email>

Reviewers : "Reviewed-by: " Username (", " Username)* "\n"

BlankLine = "\n"

Username : /[a-z]+/

Text : /[^\n]+/ "\n"

Examples of converted repositories are available at https://github.com/openjdk/.

# JDK8 Update Repositories
jdk8u/... scripts

TBD

# JDK11+ Update, JDK "next" Repositories
The **mercurialToGit.sh** script mirrors and merges the corresponding Mercurial repository into the matching Adoptium mirror:
```
hg.openjdk.java.net/jdk-updates/jdk<NN>u     --->    github.com/adoptium/jdk<NN>u (master)
hg.openjdk.java.net/jdk/jdk                  --->    github.com/adoptium/jdk(master)
```
This mirroring utilizes the "git-remote-hg" Mercurial fast importer plugin (https://github.com/felipec/git-remote-hg), and mirrors
the Mercurial "default" branch to the "master" branch in the git repo.

The Adoptium mirrors also have two vendor branches for AdoptOpenJDK to apply any extra patches needed:
  - "dev"      = "master"(HEAD) + "Adoptium Patches"
  - "release"  = "master"(latest build tag) + "Adoptium Patches"

**Note For Developers:** Any Adoptium Patches must be done on the "release" branch, they will be auto-merged nightly into "dev".

The script merges the appropriate latest merged "master" branch code into both "dev" and "release", it also ensures all the
"Adoptium Patches" from the "release" branch are merged into the "dev" branch.

The flow for the merge process is:
```
"Mercurial(default)" ---> "github.com(master)" -BuildTag-> "release" ---> "dev"
                                               -HEAD-> "dev"
```

