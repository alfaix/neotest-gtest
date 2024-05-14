GTEST_TAG ?= main
.PHONY: build

build:
	cmake -S. -DGTEST_TAG=$(GTEST_TAG) -Bbuild && \
		cmake --build build
clean:
	rm -rf build
