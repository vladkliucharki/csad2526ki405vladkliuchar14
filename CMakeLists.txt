cmake_minimum_required(VERSION 3.10)

project(MyProject LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Додаємо головний виконуваний файл
add_executable(${PROJECT_NAME} main.cpp math_operations.cpp)

# GoogleTest: автоматичне завантаження та підключення
include(FetchContent)
FetchContent_Declare(
    googletest
    URL https://github.com/google/googletest/archive/refs/heads/main.zip
)
# Для Windows: вимкнути встановлення тестів GoogleTest
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

enable_testing()

# Додаємо тестовий виконуваний файл
add_executable(unit_tests
    tests/unit_tests.cpp
    math_operations.cpp
)

target_link_libraries(unit_tests
    gtest_main
)

include(GoogleTest)
gtest_discover_tests(unit_tests)
