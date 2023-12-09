#include "gtest/gtest.h"
#include <gtest/gtest.h>

#include <iostream>
#include <stdexcept>

#include "test_utils.hpp"

namespace irrelevant {

void fillthisline() {} // so that automatically formatted code isn't ugly

TEST(TestOne, TestFailure) { // NODE:TestOne::TestFailure,failed
  fillthisline();
  std::cerr << "TODO display this in summary (somehow), not in json"
            << std::endl;
  ASSERT_FALSE(true); /* MESSAGE:
  Value of: true
    Actual: true
  Expected: false
  */
} // NODEEND

TEST(TestOne, TestEQFailure) { // NODE:TestOne::TestEQFailure,failed
  fillthisline();
  const int a = 0;
  const int b = 1;
  ASSERT_EQ(a, b); /* MESSAGE:
  Expected equality of these values:
    a
      Which is: 0
    b
      Which is: 1
  */
} // NODEEND

void fail() {
  EXPECT_EQ(0, 1); /* MESSAGE:TestOne::TestNestedFailure
  Expected equality of these values:
    0
    1
  */
}

TEST(TestOne, TestNestedFailure) { // NODE:TestOne::TestNestedFailure,failed
  fillthisline();
  ::irrelevant::fail();
} // NODEEND

TEST(TestOne, // NODE:TestOne::TestOtherFileFailure,failed
     TestOtherFileFailure) {
  fillthisline();
  /* MESSAGE:
     Expected equality of these values:
       0
       1
  */
  ::fail();
} // NODEEND

TEST(TestOne, // NODE:TestOne::TestExceptionFailure,failed
     TestExceptionFailure) {
  fillthisline();
  throw std::runtime_error("oh no!"); /* MESSAGE:NOLINE
  C++ exception with description "oh no!" thrown in the test body.
  */
} // NODEEND

TEST(TestOne, TestThrowInteger) { // NODE:TestOne::TestThrowInteger,failed
  fillthisline();
  throw 0; /* MESSAGE:NOLINE
   Unknown C++ exception thrown in the test body.
   */
} // NODEEND

// TODO death tests

TEST(TestOne, // NODE:TestOne::TestMultipleFailures,failed
     TestMultipleFailures) {
  EXPECT_TRUE(false); /* MESSAGE:
  Value of: false
    Actual: false
  Expected: true
  */
  EXPECT_FALSE(true); /* MESSAGE:
   Value of: true
     Actual: true
   Expected: false
   */
  EXPECT_EQ(1, 2);    /* MESSAGE:
   Expected equality of these values:
     1
     2
   */
} // NODEEND

TEST(TestOne, TestSkipMe) { // NODE:TestOne::TestSkipMe,skipped
  fillthisline();
  GTEST_SKIP() << "Skipped because why not";
} // NODEEND

TEST(TestOneMore, // NODE:TestOneMore::TestMultipleNamespaces,passed
     TestMultipleNamespaces) {
  fillthisline();
  ASSERT_TRUE(true);
} // NODEEND

} // namespace irrelevant
