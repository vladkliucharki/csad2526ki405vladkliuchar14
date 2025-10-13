cmake_minimum_required(VERSION 3.10)

# Назва проекту та мова
project(MyProject LANGUAGES CXX)

# Встановити стандарт C++
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Додати головний вихідний файл
add_executable(${PROJECT_NAME} main.cpp)
