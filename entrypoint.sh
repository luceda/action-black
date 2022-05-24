#!/bin/bash
#set -e # Increase bash strictness
set -o pipefail

# find base commit:
if [[ -z "$GITHUB_EVENT_PATH" ]]; then
  echo "Set the GITHUB_EVENT_PATH env variable."
  exit 1
fi

find_base_commit() {
  BASE_COMMIT=$(
    jq \
      --raw-output \
      .pull_request.base.sha \
      "$GITHUB_EVENT_PATH"
  )
  # If this is not a pull request action it can be a check suite re-requested
  if [ "$BASE_COMMIT" == null ]; then
    BASE_COMMIT=$(
      jq \
        --raw-output \
        .check_suite.pull_requests[0].base.sha \
        "$GITHUB_EVENT_PATH"
    )
  fi
}

ACTION=$(
  jq --raw-output .action "$GITHUB_EVENT_PATH"
)
# First 2 actions are for pull requests, last 2 are for check suites.
ENABLED_ACTIONS='synchronize opened requested rerequested'

main() {
  if [[ $ENABLED_ACTIONS != *"$ACTION"* ]]; then
    echo -e "Not interested in this event: $ACTION.\nExiting..."
    exit
  fi
  find_base_commit

  git fetch -all

  STATUS=$(git diff --name-only "$BASE_COMMIT")
  echo $STATUS
  STATUS2=$(git diff --name-only --diff-filter=AM "$BASE_COMMIT")
  echo $STATUS2

  # Get files Added or Modified wrt base commit, filter for Python,
  # replace new lines with space.
  new_files_in_branch=$(
    git diff \
      --name-only \
      --diff-filter=AM \
      "$BASE_COMMIT"
  )
  new_files_in_branch1=$(echo $new_files_in_branch | tr '\n' ' ')

  echo "New files in branch: $new_files_in_branch1"
  # shellcheck disable=SC2086
  if [[ $new_files_in_branch =~ .*".py".* ]]; then
    new_python_files_in_branch=$(
      git diff \
        --name-only \
        --diff-filter=AM \
        "$BASE_COMMIT" | grep '\.py$' | tr '\n' ' '
    )
    echo "New python files in branch: $new_python_files_in_branch"
  fi

  # If no arguments are given use current working directory
  black_args=("$new_python_files_in_branch")
  if [[ "$#" -eq 0 && "${INPUT_BLACK_ARGS}" != "" ]]; then
    black_args+=(${INPUT_BLACK_ARGS})
  elif [[ "$#" -ne 0 && "${INPUT_BLACK_ARGS}" != "" ]]; then
    black_args+=($* ${INPUT_BLACK_ARGS})
  elif [[ "$#" -ne 0 && "${INPUT_BLACK_ARGS}" == "" ]]; then
    black_args+=($*)
  else
    # Default (if no args provided).
    black_args+=("--check" "--diff")
  fi

  # Check if formatting was requested
  regex='\s+(--diff|--check)\s?'
  if [[ "${black_args[*]}" =~ $regex ]]; then
    formatting="false"
    black_print_str="Checking"
  else
    formatting="true"
    black_print_str="Formatting"
  fi

  # Check if '-q' or `--quiet` flags are present
  quiet="false"
  black_args_tmp=()
  for item in "${black_args[@]}"; do
    if [[ "${item}" != "-q" && "${item}" != "--quiet" ]]; then
      black_args_tmp+=("${item}")
    else
      # Remove `quiet` related flags
      # NOTE: Prevents us from checking if files were formatted
      if [[ "${formatting}" != 'true' ]]; then
        black_args_tmp+=("${item}")
      fi
      quiet="true"
    fi
  done

  black_exit_val="0"
  echo "[action-black] ${black_print_str} python code using the black formatter..."
  black_output="$(black ${black_args_tmp[*]} 2>&1)" || black_exit_val="$?"
  if [[ "${quiet}" != 'true' ]]; then
    echo "${black_output}"
  fi

  # Check for black errors
  if [[ "${formatting}" != "true" ]]; then
    echo "::set-output name=is_formatted::false"
    if [[ "${black_exit_val}" -eq "0" ]]; then
      black_error="false"
    elif [[ "${black_exit_val}" -eq "1" ]]; then
      black_error="true"
    elif [[ "${black_exit_val}" -eq "123" ]]; then
      black_error="true"
      echo "[action-black] ERROR: Black found a syntax error when checking the" \
        "files (error code: ${black_exit_val})."
    else
      echo "[action-black] ERROR: Something went wrong while trying to run the" \
        "black formatter (error code: ${black_exit_val})."
      exit 1
    fi
  else
    # Check if black formatted files
    regex='\s?[0-9]+\sfiles?\sreformatted(\.|,)\s?'
    if [[ "${black_output[*]}" =~ $regex ]]; then
      echo "::set-output name=is_formatted::true"
    else
      echo "::set-output name=is_formatted::false"
    fi

    # Check if error was encountered
    if [[ "${black_exit_val}" -eq "0" ]]; then
      black_error="false"
    elif [[ "${black_exit_val}" -eq "123" ]]; then
      black_error="true"
      echo "[action-black] ERROR: Black found a syntax error when checking the" \
        "files (error code: ${black_exit_val})."
    else
      echo "::set-output name=is_formatted::false"
      echo "[action-black] ERROR: Something went wrong while trying to run the" \
        "black formatter (error code: ${black_exit_val})."
      exit 1
    fi
  fi

  # Throw error if an error occurred and fail_on_error is true
  if [[ "${INPUT_FAIL_ON_ERROR,,}" = 'true' && "${black_error}" = 'true' ]]; then
    exit 1
  fi
}

main "$@"
