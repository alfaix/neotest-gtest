#pragma once
#include <gtest/gtest.h>

inline void fail() { EXPECT_EQ(0, 1); }
