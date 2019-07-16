#!/bin/bash
set -euo pipefail

readonly results_dir="$1"
readonly consensus_dir="$2"
readonly implementation_dir="$3"
readonly implementation="$(basename "$implementation_dir")"

. src/shared.sh

all_query_results() {
    find "$results_dir" -type d -maxdepth 1 -mindepth 1 -print0 | xargs -0 -n1 basename | sort
}

unwrap_scalar_if_needed() {
    local query="$1"

    if [[ -f "./implementations/${implementation}/SINGLE_POSSIBLE_MATCH_RETURNED_AS_SCALAR" && -f "./queries/${query}/SCALAR_RESULT" ]]; then
        ./src/unwrap_scalar.py
    else
        cat
    fi
}

gold_standard() {
    local query="$1"
    local matching_implementations="${consensus_dir}/${query}"
    local first_matching_implementation
    first_matching_implementation="$(head -1 < "$matching_implementations")"

    query_result_payload "${results_dir}/${query}/${first_matching_implementation}"
}

query_entry() {
    local query="$1"
    local matching_implementations="${consensus_dir}/${query}"

    echo "  - id: ${query}"
    echo -n "    selector: "
    cat "./queries/${query}/selector"
    echo -n "    document: "
    ./src/oneliner_json.py < "./queries/${query}/document.json"

    if is_query_result_ok "${results_dir}/${query}/${implementation}"; then
        echo -n "    result: "
        query_result_payload "${results_dir}/${query}/${implementation}" | unwrap_scalar_if_needed "$query" | ./src/oneliner_json.py

        if [[ -s "$matching_implementations" ]]; then
            if grep "^${implementation}\$" < "$matching_implementations" > /dev/null; then
                echo "    status: pass"
            else
                echo "    status: fail"
                echo -n "    consensus: "
                gold_standard "$query" | unwrap_scalar_if_needed "$query" | ./src/oneliner_json.py
            fi
        else
            echo "    status: open"
        fi
    else
        echo "    status: error"
        if [[ -s "$matching_implementations" ]]; then
            echo -n "    consensus: "
            gold_standard "$query" | unwrap_scalar_if_needed "$query" | ./src/oneliner_json.py
        fi
    fi
}

main() {
    local query

    echo "# This file was generated by src/compile_regression_suite.sh from https://github.com/cburgmer/json-path-comparison/"
    echo "# You probably don't want to change this manually but rather trigger a rebuild in the upstream source."
    echo

    echo "implementation: ${implementation}"

    echo "queries:"
    while IFS= read -r query; do
        query_entry "$query"
    done <<< "$(all_query_results)"
}

main
