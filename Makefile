.PHONY: test unit-test integration-test submodules

MINIMAL_INIT = tests/unit/minimal_init.lua
PLENARY_OPTS = {minimal_init='${MINIMAL_INIT}', sequential=true, timeout=1000}
GTEST_VERSION ?= main
export GTEST_VERSION

test: unit-test integration-test ;

unit-test:
	nvim --headless -c "PlenaryBustedDirectory tests/unit ${PLENARY_OPTS}"

integration-test: build-tests
	nvim --headless -c "PlenaryBustedDirectory tests/integration ${PLENARY_OPTS}"

build-tests: tests/integration/cpp
	$(MAKE) -C tests/integration/cpp build

clean-tests: tests/integration/cpp
	$(MAKE) -C tests/integration/cpp clean
