#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
bash -n pg-dba-toolkit.sh
[[ $(bash pg-dba-toolkit.sh --version) == 1.0.0 ]]
bash pg-dba-toolkit.sh --help
if bash pg-dba-toolkit.sh invalid; then exit 1; fi
printf '0\n' | bash pg-dba-toolkit.sh interactive
