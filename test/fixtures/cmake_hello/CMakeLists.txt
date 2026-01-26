cmake_minimum_required(VERSION 3.10)
project(cmake_hello C)

add_executable(cmake_hello src/main.c)

option(BUILD_TESTING "Build tests" OFF)
if(BUILD_TESTING)
  add_subdirectory(test)
endif()
