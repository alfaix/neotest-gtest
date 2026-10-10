#include <gtest/gtest.h>

#include <cstdlib>
#include <vector>

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

class ParamFixture : public ::testing::TestWithParam<int> {};

TEST_P(ParamFixture, Positive) { // NODE:ParamFixture::Positive,passed
  EXPECT_GE(GetParam(), 0);

  if (std::getenv("NEOTEST_GTEST_FAIL_PARAM") && GetParam() == 1) {
    FAIL() << "selected parameter failed";
  }
} // NODEEND

TEST_P(ParamFixture, Small) { // NODE:ParamFixture::Small,passed
  EXPECT_LE(GetParam(), 2);
} // NODEEND

static std::vector<int> second_values() { return {2}; }

INSTANTIATE_TEST_SUITE_P(First, ParamFixture, ::testing::Values(0, 1));

INSTANTIATE_TEST_SUITE_P(Second, ParamFixture,
                         ::testing::ValuesIn(second_values()));

} // namespace test_two
