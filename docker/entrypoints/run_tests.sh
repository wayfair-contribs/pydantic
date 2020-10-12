#!/usr/bin/env bash
set -e

trap error_handler ERR

# pretty colours
SET_BLACK_TEXT="\e[30m"
SET_YELLOW_TEXT="\e[33m"
SET_RED_BACKGROUND="\e[101m"
SET_ERROR_TEXT="$SET_BLACK_TEXT$SET_RED_BACKGROUND"
RESET_FORMATTING="\e[0m"
ERROR_PREFIX="${SET_ERROR_TEXT}ERROR:${RESET_FORMATTING}"

error_handler() {
  exitcode=$?
  echo -e "$SET_ERROR_TEXT $BASH_COMMAND failed!!! $RESET_FORMATTING"
  # Some more clean up code can be added here before exiting
  exit $exitcode
}

echo "Starting test suite..."
if [[ $# == 0 ]]; then
  echo "${SET_YELLOW_TEXT}WARNING:${RESET_FORMATTING} No checks run!"
  echo usage
fi

# Stores all arguments passed to the script
SCRIPT_ARGS=("$@")

# Set default values
ACTIVATE_PYENV="true"
IS_CI="false"
IS_LOCAL="true"

# Set options accepted by the CLI and all steps in the test suite.
# This should be updated as additional options or steps are added.
VALID_CLI_OPTIONS=("--all" "--lint" "--unit-test" "--no-pyenv" "--ci" "--local" "--run" "--skip" "--extra-args" "--help" "-h")
LINT_STEPS=("bandit" "black" "flake8" "isort" "mypy")
TEST_STEPS=("pytest")

# Controls which steps will run as part of the test suite.
# By default, no steps run and no extra arguments are set.
declare -A STEPS_ACTIVE_MAP
declare -A STEP_EXTRA_ARGUMENTS

ALL_STEPS=("${TEST_STEPS[@]}" "${LINT_STEPS[@]}")
for step in "${ALL_STEPS[@]}"; do
  STEPS_ACTIVE_MAP["${step}"]="false"
  STEP_EXTRA_ARGUMENTS["${step}"]=""
done

####################################################################
# Determine if array contains value
# Globals:
#   None
# Arguments:
#   value: An arbitrary value
#   array: Array of values to check if contains `value`
####################################################################
array_contains() {
  local seeking=$1
  shift
  local in=1
  for element; do
    if [[ $element == "$seeking" ]]; then
      in=0
      break
    fi
  done
  return $in
}

####################################################################
# Sets extra arguments for a provided step
# Globals:
#   STEP_EXTRA_ARGUMENTS
# Arguments:
#   steps: string that must be keys in STEP_EXTRA_ARGUMENTS
#   arguments: arguments to pass to given
# Modifies:
#   STEP_EXTRA_ARGUMENTS
####################################################################
add_extra_arguments() {
  local step=$1
  shift
  if ! array_contains "${step}" "${!STEP_EXTRA_ARGUMENTS[@]}"; then
    printf "%b The specified step %s is invalid.\n" "${ERROR_PREFIX}" "${step}"
    usage
  fi
  STEP_EXTRA_ARGUMENTS["${step}"]="$*"
}

####################################################################
# Toggles a step between on (will run) and off (won't run)
# Globals:
#   STEPS_ACTIVE_MAP
# Arguments:
#   action: Either 'on' or 'off'
#   steps: string or array of strings that must be keys in STEPS_ACTIVE_MAP
# Modifies:
#   STEPS_ACTIVE_MAP
####################################################################
toggle_step() {
  local action=$1
  shift
  if [[ ${action} != "on" ]] && [[ ${action} != "off" ]]; then
    echo "Specified invalid step ${step}. Choose between on and off."
    exit 1
  fi
  for step; do
    if ! array_contains "${step}" "${!STEPS_ACTIVE_MAP[@]}"; then
      printf "%b The specified step %s is invalid.\n" "${ERROR_PREFIX}" "${step}"
      usage
    fi
    if [[ ${action} == "on" ]]; then
      STEPS_ACTIVE_MAP["${step}"]="true"
    else
      STEPS_ACTIVE_MAP["${step}"]="false"
    fi
  done
}

########################################
# Perform validation on script arguments
# Globals:
#   SCRIPT_ARGS
# Arguments:
#   None
########################################
validate_input() {
  # One of --ci or --local (but not both) must be set
  if array_contains "--ci" "${SCRIPT_ARGS[@]}" && array_contains "--local" "${SCRIPT_ARGS[@]}"; then
    printf "%b Only specify one of --ci or --local\n" "${ERROR_PREFIX}"
    usage
  fi
}

########################################
# Perform setup for running CI
# Globals:
#   STEPS_ACTIVE_MAP
# Arguments:
#   None
########################################
ci_prepare() {
  # CI is generally run in a base python image. Make sure all required dependencies
  # are installed
  local requirements=("-r" "requirements-test.txt")
  # All modules must be installed for isort to properly determine what is 3rd part
  # Pytest needs prod requirements to run the service
  if [[ ${STEPS_ACTIVE_MAP["isort"]} == "true" ]] || [[ ${STEPS_ACTIVE_MAP["pytest"]} == "true" ]] || [[ ${STEPS_ACTIVE_MAP["mypy"]} == "true" ]]; then
    requirements+=("-r" "requirements.txt")
  fi
  pip install "${requirements[@]}"
}

function usage() {
  echo "usage: entrypoint.sh test (--ci|--local) [--all] [--lint] [--unit-test] [--no-pyenv] [--run|--skip {step} <extra_args>]"
  echo ""
  echo "Valid steps: {${ALL_STEPS[*]}}"
  echo ""
  echo "Options:"
  echo " --ci/--local     : Current environment. When run locally, will attempt to fix errors."
  echo " --all            : Run both the unit test and linting suites"
  echo " --lint           : Run the full linting suite."
  echo " --unit-test      : Run the full unit test suite."
  echo " --no-pyenv       : Don't activate the pyenv virtualenv"
  echo " --run/--skip     : Specify a specific check to run/skip. --run optionally accepts extra"
  echo "                    arguments that are passed to the step. This option can be used multiple times."
  exit 1
}

###############################################
# Parse CLI flags and set variables accordingly
###############################################
function handle_input() {
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
      --all)
        toggle_step "on" "${ALL_STEPS[@]}"
        ;;
      --lint)
        toggle_step "on" "${LINT_STEPS[@]}"
        ;;
      --unit-test)
        toggle_step "on" "${TEST_STEPS[@]}"
        ;;
      --no-pyenv)
        ACTIVATE_PYENV="false"
        ;;
      --ci)
        IS_CI="true"
        IS_LOCAL="false"
        BLACK_ACTION="--check"
        ISORT_ACTION="--diff --check-only"
        true
        ;;
      --local)
        IS_LOCAL="true"
        IS_CI="false"
        BLACK_ACTION="--quiet"
        ISORT_ACTION="--apply"
        ;;
      --run)
        step="$2"
        toggle_step "on" "${step}"
        extra_args=()
        shift
        # Assume all subsequnt arguments should be passed as extra args to the previous
        # step, unless the array is a CLI option flag or there are no more arguments
        until array_contains "$2" "${VALID_CLI_OPTIONS[@]}" || [ -z "$2" ]; do
          extra_args+=(" $2")
          shift
        done
        add_extra_arguments "${step}" "${extra_args[@]}"
        ;;
      --skip)
        step="$2"
        toggle_step "off" "${step}"
        shift
        ;;
      -h | --help)
        usage
        ;;
      *)
        echo "Unexpected argument: ${arg}"
        usage
        ;;
    esac
    shift
  done
}

###############################################
# Run active steps
###############################################
function run_steps() {
  if [[ ${ACTIVATE_PYENV} == "true" ]]; then
    eval "$(pyenv init -)"
    if [[ ${IS_CI} != "true" ]]; then
      pyenv activate mep-pydantic
    fi
  fi

  if [[ ${IS_CI} == "true" ]]; then
    ci_prepare
  fi

  if [[ ${STEPS_ACTIVE_MAP[black]} == "true" ]]; then
    echo "Running black..."
    eval "black ${BLACK_ACTION} pydantic ${STEP_EXTRA_ARGUMENTS[black]} tests"
  fi

  if [[ ${STEPS_ACTIVE_MAP[isort]} == "true" ]]; then
    echo "Running isort..."
    eval "isort --recursive ${ISORT_ACTION} ${STEP_EXTRA_ARGUMENTS[isort]} ."
  fi

  if [[ ${STEPS_ACTIVE_MAP[pytest]} == "true" ]]; then
    echo "Running pytest..."
    eval "pytest ${STEP_EXTRA_ARGUMENTS[pytest]}"
  fi

  if [[ ${STEPS_ACTIVE_MAP[mypy]} == "true" ]]; then
    echo "Running mypy..."
    eval "mypy ${STEP_EXTRA_ARGUMENTS[mypy]} ."
  fi

  if [[ ${STEPS_ACTIVE_MAP[flake8]} == "true" ]]; then
    echo "Running flake8..."
    eval "flake8 ${STEP_EXTRA_ARGUMENTS[flake8]}"
  fi

  if [[ ${STEPS_ACTIVE_MAP[bandit]} == "true" ]]; then
    echo "Running bandit..."
    eval "bandit -r ${STEP_EXTRA_ARGUMENTS[bandit]} ."
  fi
}

validate_input
handle_input "$@"
run_steps
