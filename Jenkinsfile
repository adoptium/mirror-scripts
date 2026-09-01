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
                    if (!params.SKARA_REPO?.trim()) {
                        error('SKARA_REPO parameter is required.')
                    }
                    if (!(params.SKARA_REPO ==~ /[A-Za-z0-9._-]+/)) {
                        error('SKARA_REPO must be a valid GitHub repository name.')
                    }
                }
            }
        }

        stage('Determine Branches') {
            steps {
                script {
                    def upstreamRepo = params.SKARA_REPO == 'alpine-jdk8u' ? 'jdk8u' : params.SKARA_REPO
                    def skaraRepo = "https://github.com/openjdk/${upstreamRepo}"
                    echo "Upstream SKARA_REPO: ${skaraRepo}"

                    // Determine default branch via git ls-remote --symref (no API token needed)
                    def symrefOutput = sh(
                        script: "git ls-remote --symref '${skaraRepo}' HEAD",
                        returnStdout: true
                    ).trim()
                    def defaultBranchMatch = symrefOutput =~ /ref: refs\/heads\/(\S+)\s+HEAD/
                    if (!defaultBranchMatch) {
                        error("Could not determine default branch for ${skaraRepo} - git ls-remote --symref output was unexpected:\n${symrefOutput}")
                    }
                    def defaultBranch = defaultBranchMatch[0][1]
                    echo "Default branch: ${defaultBranch}"

                    // Do a temporary bare clone with --filter=blob:none to get branch refs and
                    // commit dates without downloading any file content.
                    def tmpBareClone = "${env.WORKSPACE}/tmp-bare-${params.SKARA_REPO}"
                    sh "rm -rf '${tmpBareClone}'"
                    sh "git clone --bare --filter=blob:none '${skaraRepo}' '${tmpBareClone}'"

                    try {
                        // Staleness threshold: 90 days ago as unix epoch
                        // GNU date (Linux): -d '90 days ago'; BSD date (macOS): -v-90d
                        def threeMonthsAgoStr = sh(
                            script: "date -d '90 days ago' +%s 2>/dev/null || date -v-90d +%s",
                            returnStdout: true
                        ).trim()
                        if (!threeMonthsAgoStr.isLong()) {
                            error("Failed to compute staleness threshold: unexpected output: '${threeMonthsAgoStr}'")
                        }
                        def threeMonthsAgoEpoch = threeMonthsAgoStr as long

                        // List all remote branches from the bare clone
                        def allBranchesRaw = sh(
                            script: "git -C '${tmpBareClone}' for-each-ref --format='%(refname:short)' refs/heads/",
                            returnStdout: true
                        ).trim()
                        if (!allBranchesRaw) {
                            error("No branches found in ${skaraRepo}")
                        }

                        // Filter to active branches by checking last commit date
                        def branches = [] as Set
                        for (branch in allBranchesRaw.split('\n')) {
                            branch = branch.trim()
                            if (!branch) continue
                            // Skip upstream PR branches — there can be hundreds and they are not mirrored
                            if (branch.startsWith('pr/')) continue
                            def commitEpochStr = withEnv(["BRANCH_TO_CHECK=${branch}"]) {
                                sh(
                                    script: "git -C '${tmpBareClone}' log -1 --format='%ct' \"refs/heads/\$BRANCH_TO_CHECK\"",
                                    returnStdout: true
                                ).trim()
                            }
                            if (!commitEpochStr.isLong()) {
                                error("Could not determine commit date for branch '${branch}': unexpected output: '${commitEpochStr}'")
                            }
                            def commitEpoch = commitEpochStr as long
                            if (commitEpoch >= threeMonthsAgoEpoch) {
                                echo "Active branch: ${branch} (epoch: ${commitEpoch})"
                                branches.add(branch)
                            } else {
                                echo "Stale branch (skipping): ${branch} (epoch: ${commitEpoch})"
                            }
                        }

                        // Ensure the default branch is always included
                        branches.add(defaultBranch)

                        echo "Active branches to mirror: ${branches.join(', ')}"
                        env.BRANCHES_TO_MIRROR = branches.join(' ')
                        env.DEFAULT_BRANCH     = defaultBranch
                    } finally {
                        // Always clean up the temporary bare clone
                        sh "rm -rf '${tmpBareClone}'"
                    }
                }
            }
        }

        stage('Clean Mirror Workspace') {
            when {
                expression { return params.CLEAN_MIRROR_WORKSPACE == true }
            }
            steps {
                script {
                    def workspaceDir = "${env.WORKSPACE}/workspace/${params.SKARA_REPO}"
                    echo "Cleaning mirror workspace: ${workspaceDir}"
                    sh "rm -rf '${workspaceDir}'"
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
                        withEnv([
                            "BRANCH=${branch}",
                            "SKARA_REPO_ARG=${params.SKARA_REPO}",
                            "MIRROR_REPO_ARG=${mirrorRepoArg}"
                        ]) {
                            def mirrorSteps = {
                                sh '''
                                    git --version
                                    bash ./skaraMirror.sh "$SKARA_REPO_ARG" "$MIRROR_REPO_ARG"
                                '''
                            }
                            if (params.SSH_CREDENTIAL_ID?.trim()) {
                                sshagent(credentials: [params.SSH_CREDENTIAL_ID]) {
                                    mirrorSteps()
                                }
                            } else {
                                mirrorSteps()
                            }
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
            script {
                // Only notify Slack during 09:00–11:59 UTC to avoid hourly spam.
                def utcHour = sh(script: "date -u +%H", returnStdout: true).trim().toInteger()
                if (utcHour >= 9 && utcHour < 12) {
                    slackSend(
                        channel: '#build',
                        color: 'danger',
                        message: "Skara mirror job *FAILED* for `${params.SKARA_REPO ?: 'unknown'}`" +
                                 (params.ADOPTIUM_MIRROR_REPO?.trim() ? " → `${params.ADOPTIUM_MIRROR_REPO}`" : '') +
                                 " (<${env.BUILD_URL}console|Console>)"
                    )
                } else {
                    echo "Outside Slack notification window (UTC hour: ${utcHour}) — skipping Slack alert."
                }
            }
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
