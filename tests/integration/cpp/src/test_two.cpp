#include <gtest/gtest.h>

namespace test_two {

class TestFixture : public ::testing::Test {
protected:
  void doFoo() {}
  void fail() {
    EXPECT_TRUE(false); /* MESSAGE:TestFixture::FailInFixture
    Value of: false
      Actual: false
    Expected: true
    */
  }
};

TEST_F(TestFixture, TestError) { // NODE:TestFixture::TestError,failed
  doFoo();
  ASSERT_TRUE(false); /* MESSAGE:
  Value of: false
    Actual: false
  Expected: true
  */
} // NODEEND

TEST_F(TestFixture, TestOk) { // NODE:TestFixture::TestOk,passed
  doFoo();
  ASSERT_TRUE(true);
} // NODEEND

TEST_F(TestFixture, FailInFixture) { // NODE:TestFixture::FailInFixture,failed
  doFoo();
  fail();
} // NODEEND

} // namespace test_two
