SHELL := /usr/bin/env bash

.PHONY: check lint test build clean

check: lint test

lint:
	tests/lint.sh

test:
	tests/run.sh

build:
	./build.sh

clean:
	rm -rf dist
