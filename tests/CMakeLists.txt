# GoogleTest comes prebuilt from the dev container image (Ubuntu's libgtest-dev).
find_package(GTest REQUIRED)
include(GoogleTest)

set(kv_test_sources version_test.cpp)
add_executable(kv_tests ${kv_test_sources})
# gtest_main supplies main(), so test files contain only tests.
target_link_libraries(kv_tests PRIVATE kv_core kv_build_flags GTest::gtest_main)
kv_relint_on_config_change(SOURCES ${kv_test_sources} CONFIGS "${CMAKE_SOURCE_DIR}/.clang-tidy")

# Registers every TEST() as its own CTest test, so results are reported per test and
# CTest can run them in parallel.
gtest_discover_tests(kv_tests)
