enable_testing()

add_executable(cmake_hello_tests test_main.c)

add_test(NAME cmake_hello_tests COMMAND cmake_hello_tests)
