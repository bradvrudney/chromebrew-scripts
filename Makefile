SHELL := /usr/bin/env bash
SHELLCHECK ?= shellcheck
BATS ?= bats

SH_FILES := bin/chromebrew bin/powerwash bin/rootfs bin/rw lib/*.sh install.sh \
            scripts/check.sh test/test_helper.bash test/stubs/stub.sh \
            test/stubs/sudo test/stubs/crew test/stubs/curl

.PHONY: check lint test

check: lint test

lint:
	$(SHELLCHECK) -x -P lib -P . $(SH_FILES)

test:
	$(BATS) --tap test/
