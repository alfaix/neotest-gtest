cmake_minimum_required(VERSION 3.24)
project(neotest_gtest_tests)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(test-executable src/test_one.cpp src/test_two.cpp)
add_executable(test-executable2 src/subdirectory/test_three.cpp)

enable_testing()
include(FetchContent)
FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG ${GTEST_TAG})

if(${GTEST_TAG} STREQUAL "main")
  set(GTEST_VERSION "999.999")
else()
  string(REGEX MATCH "^(v|release-)([0-9]+)\.([0-9]+)\." GTEST_VERSION_MATCH
               ${GTEST_TAG})
  if(NOT ${GTEST_VERSION_MATCH} STREQUAL "")
    set(GTEST_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}")
  else()
    message(
      FATAL_ERROR
        "Tag ${GTEST_TAG} not supported: must be either `main` or `vX.Y.x`")
  endif()
endif()

if(${GTEST_TAG} STREQUAL "main" OR ${GTEST_VERSION} VERSION_GREATER_EQUAL
                                   "1.12")
  message(STATUS "Compiling against GTest::gtest_main")
  set(GTEST_TARGET GTest::gtest_main)
  FetchContent_MakeAvailable(googletest)
else()
  message(STATUS "Compiling against gtest_main")
  set(GTEST_TARGET gtest_main)
  FetchContent_Populate(googletest)
  add_subdirectory(${googletest_SOURCE_DIR} ${googletest_BINARY_DIR}
                   EXCLUDE_FROM_ALL)
endif()

target_link_libraries(test-executable ${GTEST_TARGET})
target_link_libraries(test-executable2 ${GTEST_TARGET})

include(GoogleTest)
gtest_discover_tests(test-executable)
gtest_discover_tests(test-executable2)
