#!/bin/bash
# Python Library Lint, Test, Build Pipeline
#
# This pipeline leverages Buildkite's Dynamic Pipelines to automatically
# create a pipeline based on what stage of development you are in.
#
# This pipeline will define the following Steps and based on a common Python library
# CI build workflow:
# - on all git pushes, on every branch, linting and tests will be ran
# - on git tag pushes, an sdist and a wheel will be built and uploaded to Artifactory
#
#
# Notes:
# - This Pipeline *does not* bump the version for you.  You must bump the version before you
# `git tag`.
# - setting the environment variable TEST_BUILD will also run the build portion of the pipeline,
# which is useful for testing
#
# Author: Brendan Smith <bresmith@wayfair.com>
# Maintainers: Python Platform Team <pythonplatforms@wayfair.com>
# Copyright: 2019 Wayfair, LLC

set -euo pipefail

function add_steps() {
    local step_yaml=$1
    sed 's/^/  /' < $step_yaml
    echo
}

if [[ "${BUILDKITE_MESSAGE:-}" == *"SKIP_LINT"* ]] ; then
    SKIP_LINT="true"
fi

if [[ "${BUILDKITE_MESSAGE:-}" == *"SKIP_TEST"* ]] ; then
    SKIP_TEST="true"
fi

if [[ "${BUILDKITE_MESSAGE:-}" == *"TEST_BUILD"* ]] ; then
    TEST_BUILD="true"
fi

if [[ "${BUILDKITE_MESSAGE:-}" == *"TEST_DEPLOY"* ]] ; then
    TEST_DEPLOY="true"
fi

if [[ "${BUILDKITE_MESSAGE:-}" == *"SKIP_DOCS"* ]] ; then
    SKIP_DOCS="true"
fi

cat .buildkite/common.yml
echo

echo "steps:"

# unless SKIP_TEST, run your tests. you do have tests, right?  :D
if [[ ! "${SKIP_TEST:-}" == "true" ]] ; then
    add_steps .buildkite/test.yml
fi

# The trigger to build and deploy via wheelhaus is the push of a Git Tag
if [[ "${BUILDKITE_TAG:-}" ]]; then
    BUILD_DEPLOY="true"
fi

# if there was a git tag pushed, build an sdist and wheel and deploy
if [[ "${BUILD_DEPLOY:-}" == "true" ]] ; then
    echo "  - wait"

    add_steps .buildkite/build.yml

    echo "  - wait"

    add_steps .buildkite/deploy.yml
fi

# Allow for overriding and testing the build pipeline, but skip deploying
if [[ "${TEST_BUILD:-}" == "true" ]] ; then
    echo "  - wait"

    add_steps .buildkite/build.yml
fi

# Allow for overriding and testing the deploy to test WHS
if [[ "${TEST_DEPLOY:-}" == "true" ]] ; then
    echo "  - wait"

    add_steps .buildkite/deploy.yml
fi
