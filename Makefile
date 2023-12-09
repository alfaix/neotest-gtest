.PHONY: unit-test integration-test

unit-test:
	nvim --headless -c "PlenaryBustedDirectory tests/unit {minimal_init = \"tests/unit/minimal_init.lua\", sequential = false}"

integration-test:
	nvim --headless -c "PlenaryBustedDirectory tests/integration {minimal_init = \"tests/unit/minimal_init.lua\", sequential = false}"
