# OpenJDK Mirror Scripts

These scripts are run at https://ci.adoptopenjdk.net/view/git-mirrors/ and are responsible for updating the Eclipse Adoptium clones of the various OpenJDK Skara github repositories that we are interested in building.

## For developers

OpenJDK Source Control repositories are now managed using the GitHub (project Skara). The Git repositories are mirrored at OpenJDK.

Examples of converted repositories are available at https://github.com/openjdk/.

# Skara repos and processes

Historical information about the migration to OpenJDK GitHub from Mercurial is available at https://openjdk.org/jeps/369


**Note For Developers:** Any Adoptium Patches must be done on the "release" branch, they will be auto-merged nightly into "dev".

The script merges the appropriate latest merged "master" branch code into both "dev" and "release", it also ensures all the
"Adoptium Patches" from the "release" branch are merged into the "dev" branch.

The flow for the merge process is:
```
"Skara upstream: https://github.com/openjdk/jdkNN(master)" ---> "Mirror: https://github.com/adoptium/jdkNN(master)" -BuildTag-> "release" ---> "dev"
```

# Remote trigger scripts and process

triggerReleasePipeline.sh runs in Jenkins and only run by scheduler "0 H 17-20 1,3,4,7,9,10 1-5"
It uses functions defined in common.sh and gets input from file releasePlan.cfg
So the release champion should preper before each release by set the expected version in releasePlan.cfg
