#include <gtest/gtest.h>

namespace test_three {

void fillthisline() {}

TEST(TestThree, TestFailure) { // NODE:TestThree::TestFailure,failed
  fillthisline();
  ASSERT_TRUE(false); /* MESSAGE:
  Value of: false
    Actual: false
  Expected: true
  */
} // NODEEND

TEST(TestFixture, TestOk) { // NODE:TestFixture::TestOk,passed
  fillthisline();
  ASSERT_TRUE(true);
} // NODEEND

} // namespace test_three
