# Hacks I don't understand, courtesy of 
# https://stackoverflow.com/questions/18136918/how-to-get-current-relative-directory-of-your-makefile
SHELL := /bin/bash
pwd := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))

build: gtest test_one.cpp test_two.cpp test_three.cpp
	c++ -Og build/test_one.cpp.o build/test_two.cpp.o \
		-g \
		-L${pwd}/googletest/build/lib \
		-lgtest_main \
		-lgtest \
		-lpthread \
		-o build/test-executable  

	c++ -Og build/test_three.cpp.o \
		-g \
		-L${pwd}/googletest/build/lib \
		-lgtest_main \
		-lgtest \
		-lpthread \
		-o build/test-executable2


gtest: googletest
	cmake -S ${pwd}/googletest -B ${pwd}/googletest/build -DCMAKE_BUILD_TYPE=Release && \
		cmake --build ${pwd}/googletest/build

test_one.cpp:
	mkdir -p build/ && c++ -Og -I${pwd}/src/ -isystem ${pwd}/googletest/googletest/include -o ${pwd}/build/test_one.cpp.o \
		-g -c ${pwd}/src/test_one.cpp

test_two.cpp:
	mkdir -p build/ && c++ -Og -I${pwd}/src/ -isystem ${pwd}/googletest/googletest/include -o ${pwd}/build/test_two.cpp.o \
		-g -c ${pwd}/src/test_two.cpp

test_three.cpp:
	mkdir -p build/ && c++ -Og -I${pwd}/src/ -isystem ${pwd}/googletest/googletest/include -o ${pwd}/build/test_three.cpp.o \
		-g -c ${pwd}/src/subdirectory/test_three.cpp
