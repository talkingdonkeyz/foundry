#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int test_addition() {
    int result = 2 + 2;
    if (result != 4) {
        fprintf(stderr, "FAIL: test_addition - expected 4, got %d\n", result);
        return 1;
    }
    printf("PASS: test_addition\n");
    return 0;
}

int test_string() {
    const char* hello = "hello from c";
    if (strstr(hello, "hello") == NULL) {
        fprintf(stderr, "FAIL: test_string - expected 'hello' in string\n");
        return 1;
    }
    printf("PASS: test_string\n");
    return 0;
}

int main() {
    int failures = 0;
    failures += test_addition();
    failures += test_string();

    if (failures > 0) {
        printf("\n%d test(s) failed\n", failures);
        return 1;
    }
    printf("\nAll tests passed!\n");
    return 0;
}
