#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
# shellcheck source=scripts/ci/libraries/_script_init.sh
. "$( dirname "${BASH_SOURCE[0]}" )/../libraries/_script_init.sh"

: "${EXECUTOR:?You must set EXECUTOR to one of 'KubernetesExecutor', 'CeleryExecutor', 'CeleryKubernetesExecutor' }"

kind::make_sure_kubernetes_tools_are_installed
kind::get_kind_cluster_name

traps::add_trap kind::dump_kind_logs EXIT HUP INT TERM

interactive="false"

declare -a tests_to_run
declare -a pytest_args

tests_to_run=()

function parse_tests_to_run() {
    if [[ $# != 0 ]]; then
        if [[ $1 == "--help" || $1 == "-h" ]]; then
            echo
            echo "Running kubernetes tests"
            echo
            echo "    $0                      - runs all kubernetes tests"
            echo "    $0 TEST [TEST ...]      - runs selected kubernetes tests (from kubernetes_tests folder)"
            echo "    $0 [-i|--interactive]   - Activates virtual environment ready to run tests and drops you in"
            echo "    $0 [--help]             - Prints this help message"
            echo
            exit
        elif [[ $1 == "--interactive" || $1 == "-i" ]]; then
            echo
            echo "Entering interactive environment for kubernetes testing"
            echo
            interactive="true"
        else
            tests_to_run=("${@}")
        fi
        pytest_args=()
    else
        tests_to_run=("kubernetes_tests")
        pytest_args=(
            "--verbosity=1"
            "--strict-markers"
            "--durations=100"
            "--color=yes"
            "--maxfail=50"
            )

    fi
}

function create_virtualenv() {
    HOST_PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
    readonly HOST_PYTHON_VERSION

    local virtualenv_path="${BUILD_CACHE_DIR}/.kubernetes_venv/${KIND_CLUSTER_NAME}_host_python_${HOST_PYTHON_VERSION}_${EXECUTOR}"

    mkdir -pv "${BUILD_CACHE_DIR}/.kubernetes_venv/"
    if [[ ! -d ${virtualenv_path} ]]; then
        echo
        echo "Creating virtualenv at ${virtualenv_path}"
        echo
        python3 -m venv "${virtualenv_path}"
    fi

    . "${virtualenv_path}/bin/activate"

    pip install --upgrade "pip==${AIRFLOW_PIP_VERSION}" "wheel==${WHEEL_VERSION}"

    local constraints=(
        --constraint
        "https://raw.githubusercontent.com/${CONSTRAINTS_GITHUB_REPOSITORY}/${DEFAULT_CONSTRAINTS_BRANCH}/constraints-${HOST_PYTHON_VERSION}.txt"
    )
    if [[ ${CI:=} == "true" && -n ${GITHUB_REGISTRY_PULL_IMAGE_TAG=} ]]; then
        # Disable constraints when building in CI with specific version of sources
        # In case there will be conflicting constraints
        constraints=()
    fi

    pip install pytest freezegun "${constraints[@]}"

    pip install -e ".[cncf.kubernetes,postgres]" "${constraints[@]}"
}

function run_tests() {
    pytest "${pytest_args[@]}" "${tests_to_run[@]}"
}

cd "${AIRFLOW_SOURCES}" || exit 1

set +u
parse_tests_to_run "${@}"
set -u

create_virtualenv

if [[ ${interactive} == "true" ]]; then
    echo
    echo "Activating the virtual environment for kubernetes testing"
    echo
    echo "You can run kubernetes testing via 'pytest kubernetes_tests/....'"
    echo "You can add -s to see the output of your tests on screen"
    echo
    echo "The webserver is available at http://localhost:8080/"
    echo
    echo "User/password: admin/admin"
    echo
    echo "You are entering the virtualenv now. Type exit to exit back to the original shell"
    echo
    exec "${SHELL}"
else
    run_tests
fi
