.PHONY: test unit-test integration-test submodules

test: unit-test integration-test ;

unit-test:
	nvim --headless -c "PlenaryBustedDirectory tests/unit {minimal_init = \"tests/unit/minimal_init.lua\", sequential = false}"

integration-test: submodules build-tests
	nvim --headless -c "PlenaryBustedDirectory tests/integration {minimal_init = \"tests/unit/minimal_init.lua\", sequential = false}"

submodules:
	git submodule update --init --recursive

build-tests: tests/integration/cpp
	$(MAKE) -C tests/integration/cpp
