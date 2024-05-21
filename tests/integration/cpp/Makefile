GTEST_TAG ?= main
.PHONY: build

build:
	cmake -S. -DCMAKE_EXPORT_COMPILE_COMMANDS=1 -DGTEST_TAG=$(GTEST_TAG) -Bbuild && \
		cmake --build build
clean:
	rm -rf build
