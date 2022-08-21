#include <gtest/gtest.h>

namespace test_two {

class TestFixture : public ::testing::Test {
protected:
  void doFoo() {}
  void fail() { EXPECT_TRUE(false); }
};

TEST_F(TestFixture, TestError) {
  doFoo();
  ASSERT_TRUE(false);
}

TEST_F(TestFixture, TestOk) {
  doFoo();
  ASSERT_TRUE(true);
}

TEST_F(TestFixture, FailInFixture) {
  doFoo();
  fail();
}

} // namespace test_two
