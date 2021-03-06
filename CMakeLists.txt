
# Note set CUDA_BUILD_EMULATION to OFF to enable Device mode compilation.
cmake_minimum_required(VERSION 2.8.0)

project(MatrixTerminator)

set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/CMake/cuda" ${CMAKE_MODULE_PATH})
INCLUDE(CMake/cuda/FindCUDA.cmake)

# Turn off the annoying warning.
OPTION(CUDA_REMOVE_GLOBAL_MEMORY_SPACE_WARNING "Suppress the \"Advisory: Cannot tell what pointer points to, assuming global memory space\" warning nvcc makes." ON)

SET(CUDA_REMOVE_GLOBAL_MEMORY_SPACE_WARNING ON)

# find_package(CUDA)
find_package(CUDA QUIET REQUIRED)
# find_package(CUDA 2.1)
# find_package(CUDA 2.2)
# find_package(CUDA 2.3)
# find_package(CUDA 2.1 REQUIRED)
# find_package(CUDA 2.2 REQUIRED)
# find_package(CUDA 2.3 REQUIRED)
# find_package(CUDA 2.1 EXACT)
# find_package(CUDA 2.2 EXACT)
# find_package(CUDA 2.3 EXACT)
# find_package(CUDA 2.1 EXACT REQUIRED)
# find_package(CUDA 2.2 EXACT REQUIRED)
# find_package(CUDA 2.3 EXACT REQUIRED)
# find_package(CUDA 2.2 EXACT QUIET REQUIRED)

# if (CUDA_FOUND)
#   message("CUDA found")
# else()
#   message("CUDA not found")
# endif()

subdirs(
  src
)
