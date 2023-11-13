.PHONY: unit-test

unit-test:
	nvim --headless -c "PlenaryBustedDirectory tests {minimal_init = \"tests/unit/minimal_init.lua\", sequential = false}"
