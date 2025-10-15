#include <gtest/gtest.h>
#include "../math_operations.h"

TEST(AddFunctionTests, PositiveNumbers) {
    EXPECT_EQ(add(1, 2), 3);
    EXPECT_EQ(add(100, 200), 300);
}

TEST(AddFunctionTests, NegativeNumbers) {
    EXPECT_EQ(add(-1, -2), -3);
    EXPECT_EQ(add(-100, -200), -300);
}

TEST(AddFunctionTests, MixedSignNumbers) {
    EXPECT_EQ(add(-1, 2), 1);
    EXPECT_EQ(add(1, -2), -1);
}

TEST(AddFunctionTests, Zero) {
    EXPECT_EQ(add(0, 0), 0);
    EXPECT_EQ(add(0, 5), 5);
    EXPECT_EQ(add(5, 0), 5);
}
