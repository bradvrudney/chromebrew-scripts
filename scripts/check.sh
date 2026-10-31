#!/usr/bin/env bash
# scripts/check.sh - run shellcheck and the bats suite (what CI runs)
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "== shellcheck"
shellcheck -x -P lib -P . bin/chromebrew bin/powerwash bin/rootfs bin/rw lib/*.sh install.sh \
  scripts/check.sh test/test_helper.bash test/stubs/stub.sh test/stubs/sudo test/stubs/crew test/stubs/curl
echo "shellcheck: ok"

echo "== bats"
bats --tap test/
