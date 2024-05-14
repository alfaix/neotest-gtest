GTEST_VERSION ?= main
.PHONY: build

build:
	cmake -S. -DGTEST_VERSION=$(GTEST_VERSION) -Bbuild && \
		cmake --build build
clean:
	rm -rf build
