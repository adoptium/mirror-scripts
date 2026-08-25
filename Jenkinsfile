/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pipeline {
    agent { label 'worker' }

    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    triggers {
        cron('H * * * *')
    }

    stages {
        stage('Validate Parameters') {
            steps {
                script {
                    if (!params.JDK_VERSION?.trim()) {
                        error('JDK_VERSION parameter is required.')
                    }
                }
            }
        }

        stage('Determine Branches') {
            steps {
                script {
                    def skaraRepo = "https://github.com/openjdk/${params.JDK_VERSION}"
                    echo "Upstream SKARA_REPO: ${skaraRepo}"

                    // Fetch the default branch name and all active branches via the GitHub API.
                    // "Active" branches match GitHub's own definition: last commit within 3 months,
                    // which is the threshold used on the GitHub branches summary page.
                    def apiBase = "https://api.github.com/repos/openjdk/${params.JDK_VERSION}"

                    // Retrieve default branch
                    def repoInfoJson = sh(
                        script: "curl -fsSL '${apiBase}'",
                        returnStdout: true
                    ).trim()
                    def repoInfo = readJSON text: repoInfoJson
                    if (!repoInfo.default_branch) {
                        error("GitHub API did not return a default_branch for openjdk/${params.JDK_VERSION} - response may be malformed")
                    }
                    def defaultBranch = repoInfo.default_branch
                    echo "Default branch: ${defaultBranch}"

                    // Staleness threshold: unix timestamp 90 days ago, computed via shell (sandbox-safe)
                    def threeMonthsAgoStr = sh(
                        script: "date -d '90 days ago' +%s",
                        returnStdout: true
                    ).trim()
                    if (!threeMonthsAgoStr.isLong()) {
                        error("Failed to compute staleness threshold: 'date -d 90 days ago' returned unexpected output: '${threeMonthsAgoStr}'")
                    }
                    def threeMonthsAgoEpoch = threeMonthsAgoStr as long

                    // Retrieve all branches and filter to active (non-stale) ones — paginate until exhausted.
                    // For each branch we fetch the commit date via the /branches/<name> detail endpoint.
                    // Use a for loop (not .each{}) so that any curl/parse failure propagates immediately.
                    def branches = [] as Set
                    def page = 1
                    while (true) {
                        def pageJson = sh(
                            script: "curl -fsSL '${apiBase}/branches?per_page=100&page=${page}'",
                            returnStdout: true
                        ).trim()
                        def pageBranches = readJSON text: pageJson
                        if (pageBranches.isEmpty()) {
                            break
                        }
                        for (b in pageBranches) {
                            def branchDetailJson = sh(
                                script: "curl -fsSL '${apiBase}/branches/${b.name}'",
                                returnStdout: true
                            ).trim()
                            def branchDetail = readJSON text: branchDetailJson
                            if (!branchDetail?.commit?.commit?.committer?.date) {
                                error("GitHub API did not return commit date for branch '${b.name}' - response may be malformed")
                            }
                            def commitDate = branchDetail.commit.commit.committer.date  // ISO-8601
                            def commitEpochStr = sh(
                                script: "date -d '${commitDate}' +%s",
                                returnStdout: true
                            ).trim()
                            if (!commitEpochStr.isLong()) {
                                error("Failed to parse commit date for branch '${b.name}': 'date -d ${commitDate}' returned unexpected output: '${commitEpochStr}'")
                            }
                            def commitEpoch = commitEpochStr as long
                            if (commitEpoch >= threeMonthsAgoEpoch) {
                                echo "Active branch: ${b.name} (last commit: ${commitDate})"
                                branches.add(b.name)
                            } else {
                                echo "Stale branch (skipping): ${b.name} (last commit: ${commitDate})"
                            }
                        }
                        page++
                    }

                    // Ensure the default branch is always included
                    branches.add(defaultBranch)

                    echo "Active branches to mirror: ${branches.join(', ')}"
                    env.BRANCHES_TO_MIRROR = branches.join(' ')
                    env.DEFAULT_BRANCH     = defaultBranch
                }
            }
        }

        stage('Mirror Branches') {
            steps {
                script {
                    def mirrorRepoArg = params.ADOPTIUM_MIRROR_REPO?.trim() ?: ''
                    def branchList = env.BRANCHES_TO_MIRROR.tokenize(' ')

                    for (branch in branchList) {
                        echo "--- Mirroring branch: ${branch} ---"
                        withEnv(["BRANCH=${branch}"]) {
                            sh """
                                git --version
                                bash ./skaraMirror.sh '${params.JDK_VERSION}' ${mirrorRepoArg ? "'${mirrorRepoArg}'" : ''}
                            """
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            echo 'Mirror job finished.'
        }
        success {
            echo 'All branches mirrored successfully.'
        }
        unstable {
            echo 'Mirror job completed with an unstable result.'
        }
        failure {
            echo 'Mirror job failed.'
        }
        aborted {
            echo 'Mirror job was aborted.'
        }
        changed {
            echo 'Mirror job result has changed since the last run.'
        }
        fixed {
            echo 'Mirror job is back to success after a previous failure.'
        }
        regression {
            echo 'Mirror job was previously successful but is now failing.'
        }
        cleanup {
            echo 'Mirror job post-processing complete.'
        }
    }
}
