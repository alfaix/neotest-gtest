.PHONY: test unit-test integration-test submodules

MINIMAL_INIT = tests/unit/minimal_init.lua
PLENARY_OPTS = {minimal_init='${MINIMAL_INIT}', sequential=true, timeout=1000}

test: unit-test integration-test ;

unit-test:
	nvim --headless -c "PlenaryBustedDirectory tests/unit ${PLENARY_OPTS}"

integration-test: submodules build-tests
	nvim --headless -c "PlenaryBustedDirectory tests/integration {$PLENARY_OPTS}"

submodules:
	git submodule update --init --recursive

build-tests: tests/integration/cpp
	$(MAKE) -C tests/integration/cpp
