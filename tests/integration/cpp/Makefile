# Hacks I don't understand, courtesy of 
# https://stackoverflow.com/questions/18136918/how-to-get-current-relative-directory-of-your-makefile
SHELL := /bin/bash
pwd := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
build: test_one.cpp test_two.cpp
	c++ -Og build/test_one.cpp.o build/test_two.cpp.o \
		-lgtest_main -lgtest -lpthread \
		${CXXFLAGS} \
		${LDFLAGS} \
		-o build/test-executable  

test_one.cpp:
	c++ -Og -I${pwd}/src/ -o ${pwd}/build/test_one.cpp.o \
		${CXXFLAGS} \
		-c ${pwd}/src/test_one.cpp

test_two.cpp:
	c++ -Og -I${pwd}/src/ -o ${pwd}/build/test_two.cpp.o \
		${CXXFLAGS} \
		-c ${pwd}/src/test_two.cpp
