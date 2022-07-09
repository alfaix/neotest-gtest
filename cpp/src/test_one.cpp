#include "gtest/gtest.h"
#include <gtest/gtest.h>

#include <iostream>
#include <stdexcept>

#include "test_utils.hpp"

namespace irrelevant {

void fillthisline() {}

TEST(TestOne, TestFailure) {
  fillthisline();
  std::cerr << "TODO display this in summary (somehow), not in json"
            << std::endl;
  ASSERT_FALSE(true);
}

TEST(TestOne, TestEQFailure) {
  fillthisline();
  const int a = 0;
  const int b = 0;
  ASSERT_EQ(&a, &b);
}

void fail() { EXPECT_EQ(0, 1); }

TEST(TestOne, TestNestedFailure) {
  fillthisline();
  ::irrelevant::fail();
}

TEST(TestOne, TestOtherFileFailure) {
  fillthisline();
  ::fail();
}

TEST(TestOne, TestExceptionFailure) {
  fillthisline();
  throw std::runtime_error("oh no!");
}

TEST(TestOne, TestMultipleFailures) {
  EXPECT_TRUE(false);
  EXPECT_FALSE(true);
  EXPECT_EQ(1, 2);
}

TEST(TestOne, TestSkipMe) {
  fillthisline();
  GTEST_SKIP() << "Skipped because why not";
}

TEST(TestOneMore, TestMultipleNamespaces) {
  fillthisline();
  ASSERT_TRUE(true);
}

/* class FixtureP : public ::testing::TestWithParam<int> {}; */

/* TEST_P(FixtureP, TestP) { */
/*   fillthisline(); */
/*   ASSERT_EQ(GetParam(), 2); */
/* } */

/* INSTANTIATE_TEST_SUITE_P(ParametrizedTest, FixtureP, testing::Values(1, 2,
 * 3)); */

} // namespace irrelevant
