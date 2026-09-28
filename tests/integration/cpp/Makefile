GTEST_TAG ?= main
.PHONY: build

build:
	GTEST_PATH=$(GTEST_PATH) cmake -S. -DCMAKE_EXPORT_COMPILE_COMMANDS=1 -DGTEST_TAG=$(GTEST_TAG) -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -Bbuild && \
		cmake --build build
clean:
	rm -rf build
