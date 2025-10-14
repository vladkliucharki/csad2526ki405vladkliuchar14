@echo off
setlocal

if not exist build (
    mkdir build
)

cd build

cmake ..

cmake --build .

if "%OS%"=="Windows_NT" (
    ctest --output-on-failure
) else (
    ctest --output-on-failure
)

endlocal