.PHONY: unit-test

unit-test:
	nvim tests/unit/minimal_init.vim --headless -c "PlenaryBustedDirectory tests {minimal_init = \"tests/unit/minimal_init.vim\", sequential = false}"
