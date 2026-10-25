/* xerbla for the test DLLs built by blas-bitwise.sh (R's is in R.dll); the
   arguments blas-bitwise passes are valid, so it is never called. */
#include <stdio.h>
#include <stdlib.h>
void xerbla_(const char *name, int *info, size_t len)
{
    fprintf(stderr, "xerbla: %.*s %d\n", (int) len, name, *info);
    exit(3);
}
