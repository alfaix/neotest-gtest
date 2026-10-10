#include <gtest/gtest.h>

#include <cstdlib>

namespace {

int process_local_state = 0;

TEST(Isolation, AWriteState) { // NODE:Isolation::AWriteState,passed
  process_local_state = 1;
} // NODEEND

TEST(Isolation, BObserveFreshState) { // NODE:Isolation::BObserveFreshState,failed
  EXPECT_EQ(0, process_local_state); /* MESSAGE:
  Expected equality of these values:
    0
    process_local_state
      Which is: 1
  */
} // NODEEND

TEST(Isolation, CFail) { // NODE:Isolation::CFail,passed
  if (std::getenv("NEOTEST_GTEST_ISOLATION_FAILURE")) {
    FAIL() << "isolated assertion failed";
  }
} // NODEEND

TEST(Isolation, DCrash) { // NODE:Isolation::DCrash,passed
  if (std::getenv("NEOTEST_GTEST_ISOLATION_CRASH")) {
    std::abort();
  }
} // NODEEND

TEST(Isolation, EAfterCrash) { // NODE:Isolation::EAfterCrash,passed
  SUCCEED();
} // NODEEND

} // namespace
