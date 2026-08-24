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

    parameters {
        string(
            name: 'JDK_VERSION',
            defaultValue: '',
            description: 'The OpenJDK repository name to mirror from https://github.com/openjdk/ (e.g. jdk21u, jdk, jdk8u)'
        )
        string(
            name: 'ADOPTIUM_MIRROR_REPO',
            defaultValue: '',
            description: '(Optional) Adoptium mirror GitHub repository name. Defaults to the JDK_VERSION value (e.g. adoptium/<JDK_VERSION>).'
        )
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
                    // "Active" branches are those not marked as stale by GitHub (i.e. they appear
                    // in the default branch listing without the --stale flag, equivalent to the
                    // summary shown on the GitHub branches page).
                    def apiBase = "https://api.github.com/repos/openjdk/${params.JDK_VERSION}"

                    // Retrieve default branch
                    def repoInfoJson = sh(
                        script: "curl -fsSL '${apiBase}'",
                        returnStdout: true
                    ).trim()
                    def repoInfo = readJSON text: repoInfoJson
                    def defaultBranch = repoInfo.default_branch
                    echo "Default branch: ${defaultBranch}"

                    // Retrieve all active (non-stale) branches — paginate until exhausted
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
                        pageBranches.each { b -> branches.add(b.name) }
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
