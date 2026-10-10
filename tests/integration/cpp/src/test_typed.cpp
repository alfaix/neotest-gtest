#include <gtest/gtest.h>

#include <cstdlib>
#include <string>
#include <type_traits>

template <typename T> class TypedFixture : public ::testing::Test {};

using TypedTypes = ::testing::Types<int, long>;

class TypeNames {
public:
  template <typename T> static std::string GetName(int) {
    return std::is_same<T, int>::value ? "Small" : "Large";
  }
};

TYPED_TEST_SUITE(TypedFixture, TypedTypes, TypeNames);

TYPED_TEST(TypedFixture, Passes) { // NODE:TypedFixture::Passes,passed
  TypeParam value = 1;
  EXPECT_GT(value, 0);
} // NODEEND

TYPED_TEST(TypedFixture, FailsWhenRequested) { // NODE:TypedFixture::FailsWhenRequested,passed
  TypeParam value = 1;
  EXPECT_GT(value, 0);

  if (std::getenv("NEOTEST_GTEST_FAIL_TYPED") && sizeof(TypeParam) == sizeof(long)) {
    FAIL() << "selected typed case failed";
  }
} // NODEEND

template <typename T> class PatternFixture : public ::testing::Test {};

TYPED_TEST_SUITE_P(PatternFixture);

TYPED_TEST_P(PatternFixture, Passes) { // NODE:PatternFixture::Passes,passed
  TypeParam value = 1;
  EXPECT_GT(value, 0);
} // NODEEND

TYPED_TEST_P(PatternFixture, FailsWhenRequested) { // NODE:PatternFixture::FailsWhenRequested,passed
  TypeParam value = 1;
  EXPECT_GT(value, 0);

  if (std::getenv("NEOTEST_GTEST_FAIL_TYPED") && std::is_same<TypeParam, long>::value) {
    FAIL() << "selected type pattern failed";
  }
} // NODEEND

REGISTER_TYPED_TEST_SUITE_P(PatternFixture, Passes, FailsWhenRequested);

using FirstPatternTypes = ::testing::Types<int, long>;
using SecondPatternTypes = ::testing::Types<short, int>;

INSTANTIATE_TYPED_TEST_SUITE_P(First, PatternFixture, FirstPatternTypes);
INSTANTIATE_TYPED_TEST_SUITE_P(Second, PatternFixture, SecondPatternTypes);
