#include <gtest/gtest.h>

#include <string>
#include <tuple>

class PairFixture : public ::testing::TestWithParam<std::tuple<int, bool>> {};

TEST_P(PairFixture, Combined) {
  EXPECT_GE(std::get<0>(GetParam()), 1);
  EXPECT_FALSE(std::get<0>(GetParam()) == 2 && std::get<1>(GetParam()))
      << "expected only one pair to fail";
}

INSTANTIATE_TEST_SUITE_P(Pairs, PairFixture,
                         ::testing::Combine(::testing::Values(1, 2),
                                            ::testing::Bool()));

class NamedFixture : public ::testing::TestWithParam<int> {};

TEST_P(NamedFixture, Runs) {
  EXPECT_GT(GetParam(), 0);
}

TEST_P(NamedFixture, Skips) {
  GTEST_SKIP() << "inventory skip";
}

TEST_P(NamedFixture, DISABLED_NotRun) {
  FAIL() << "disabled case ran";
}

static std::string parameter_name(const ::testing::TestParamInfo<int>& info) {
  return info.param == 7 ? "Seven" : "Nine";
}

INSTANTIATE_TEST_SUITE_P(Custom, NamedFixture, ::testing::Values(7, 9),
                         parameter_name);

class EmptyFixture : public ::testing::TestWithParam<int> {};

TEST_P(EmptyFixture, NeverInstantiated) {
  FAIL() << "no instances expected";
}

GTEST_ALLOW_UNINSTANTIATED_PARAMETERIZED_TEST(EmptyFixture);
