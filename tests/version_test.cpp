#include "kv/version.hpp"

#include <gtest/gtest.h>

namespace {

TEST(VersionTest, ReportsTheCurrentVersion) { EXPECT_EQ(kv::version(), "0.1.0"); }

}  // namespace
