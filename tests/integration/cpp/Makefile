SHELL := /bin/bash
pwd := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
.PHONY: build

build:
	cmake -S$(pwd) -DGTEST_VERSION=main -B$(pwd)/build && \
		cmake --build $(pwd)/build
