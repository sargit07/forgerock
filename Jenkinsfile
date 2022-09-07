/*
 * Copyright 2019-2022 ForgeRock AS. All Rights Reserved
 *
 * Use of this code requires a commercial software license with ForgeRock AS.
 * or with one of its affiliates. All use shall be exclusively subject
 * to such license between the licensee and ForgeRock AS.
 */

@Library([
    'forgerock-pipeline-libs@3475f82df20563edc6a67a90021bbb5f24d0f494',
    'java-pipeline-libs@7d909d2ffb9ab751dc96e9c7bc9d253d3d993dbb'
]) _

import com.forgerock.pipeline.reporting.PipelineRun
import com.forgerock.pipeline.reporting.PipelineRunLegacyAdapter

BASE_VERSION = '7.2.0'

buildDirectories = [
    [ name: 'ds-new', folder: 'ds', arguments: 'ds-new', forceBuild: false ],
    [ name: 'proxy', folder: 'ds', arguments: '-f proxy/Dockerfile .', forceBuild: false ],
]

def pipeline
def pipelineRun

node('gce-vm-forgeops-n1-standard-4') {
    stage('Clone repo') {
        checkout scm

        def jobLocation = "${env.WORKSPACE}/jenkins-scripts/pipelines/build"
        def libsLocation = "${env.WORKSPACE}/jenkins-scripts/libs"
        def stagesLocation = "${env.WORKSPACE}/jenkins-scripts/stages"

        localGitUtils = load("${libsLocation}/git-utils.groovy")
        commonModule = load("${libsLocation}/common.groovy")
        commonLodestarModule = load("${libsLocation}/lodestar-common.groovy")

        currentBuild.displayName = "#${BUILD_NUMBER} - ${commonModule.SHORT_GIT_COMMIT}"
        currentBuild.description = 'built:'

        // Load the QaCloudUtils dynamically based on Lodestar commit promoted to Forgeops
        library "QaCloudUtils@${commonModule.lodestarRevision}"

        if (env.TAG_NAME) {
            currentBuild.result = 'ABORTED'
            error 'This pipeline does not currently support building from a tag'
        } else {
            if (isPR()) {
                pipeline = load("${jobLocation}/pr.groovy")
                prTestsStage = load("${stagesLocation}/pr-tests.groovy")
            } else {
                pipeline = load("${jobLocation}/postcommit.groovy")
                createPlatformImagesPR = load("${stagesLocation}/create-platform-images-pr.groovy")
            }
            // Needed both for PR and postcommit
            postcommitTestsStage = load("${stagesLocation}/postcommit-tests.groovy")
        }

        builder = PipelineRun.builder(env, steps)
                .pipelineName('forgeops')
                .branch(commonModule.GIT_BRANCH)
                .commit(commonModule.GIT_COMMIT)
                .commits(["forgeops": commonModule.GIT_COMMIT])
                .committer(commonModule.GIT_COMMITTER)
                .commitMessage(commonModule.GIT_MESSAGE)
                .committerDate(dateTimeUtils.convertIso8601DateToInstant(commonModule.GIT_COMMITTER_DATE))
                .repo('forgeops')

        pipelineRun = new PipelineRunLegacyAdapter(builder.build())
    }

    pipeline.initialSteps()
    pipeline.buildDockerImages(pipelineRun)

    if (commonModule.branchSupportsPitTests()) {
        // Allow only one postcommit at a time accross all the branches
        withPostcommitLock((isPR() && !commonLodestarModule.doRunPostcommitTests()) ? null : 'postcommit-forgeops') {
            pipeline.postBuildTests(pipelineRun)
        }
    }

    if (commonModule.branchSupportsIDCloudReleases() && !isPR()) {
        pipeline.createPlatformImagesPR(pipelineRun)
    }

    pipeline.finalNotification()
}

def withPostcommitLock(String resourceName, Closure process) {
    if (resourceName) {
        lock(resource: resourceName) {
            process()
        }
    } else {
        process()
    }
}
