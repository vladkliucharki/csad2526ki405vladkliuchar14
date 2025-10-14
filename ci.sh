#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# This ensures the script stops if any step fails (e.g., compilation error).
set -e

# --- 1. Create build directory ---
# The '-p' flag prevents an error if the directory already exists.
echo "Creating build directory..."
mkdir -p build

# --- 2. Navigate into the build directory ---
cd build

# --- 3. Configure the project with CMake ---
echo "Configuring with CMake..."
cmake ..

# --- 4. Build the project ---
echo "Building project..."
cmake --build .

# --- 5. Run tests ---
# The logic in your .bat file runs the same command for both OS conditions,
# so we just need the command itself here.
echo "Running tests..."
ctest --output-on-failure

echo "Script finished successfully!"