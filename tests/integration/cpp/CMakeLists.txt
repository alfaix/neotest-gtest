cmake_minimum_required(VERSION 3.14)
project(neotest_gtest_tests)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
enable_testing()

include(FetchContent)
FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG ${GTEST_VERSION})
FetchContent_MakeAvailable(googletest)

add_executable(test-executable src/test_one.cpp src/test_two.cpp)
target_link_libraries(test-executable GTest::gtest_main)
add_executable(test-executable2 src/subdirectory/test_three.cpp)
target_link_libraries(test-executable2 GTest::gtest_main)

include(GoogleTest)
gtest_discover_tests(test-executable)
gtest_discover_tests(test-executable2)
