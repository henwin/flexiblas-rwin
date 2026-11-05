/* A program linked against libflexiblas.dll, as Rblas.dll and Rlapack.dll
   are, run under each backend of the bundle (FLEXIBLAS set by the caller):
     load-backends BACKEND DONEFILE
   checks that FlexiBLAS loaded BACKEND, that dgemm and dpotrf give the
   right result, and that an invalid argument to each reaches the XERBLA
   the program supplies, as R supplies its own, rather than the backend's,
   which would stop the program or say nothing.  Writes DONEFILE as its
   last act when all of it holds, so that a program ended early, even with
   status 0, cannot pass.
   Built with: gcc load-backends.c -LDIR -lflexiblas (clang on aarch64). */
#include <math.h>
#include <stdio.h>
#include <string.h>

int flexiblas_current_backend(char *name, size_t len);
void dgemm_(const char *, const char *, const int *, const int *, const int *,
            const double *, const double *, const int *, const double *, const int *,
            const double *, double *, const int *, size_t, size_t);
void dpotrf_(const char *, const int *, double *, const int *, int *, size_t);

static int xerbla_calls;
static char xerbla_name[7];

/* found by FlexiBLAS through the exports of the program */
__declspec(dllexport) void xerbla_(const char *name, const int *info, size_t len)
{
    (void) info;
    xerbla_calls++;
    snprintf(xerbla_name, sizeof xerbla_name, "%.*s", (int) (len < 6 ? len : 6), name);
}

int main(int argc, char **argv)
{
    if (argc < 3) return 2;
    int fails = 0, n = 2, info = 0;
    char cur[64] = "";
    flexiblas_current_backend(cur, sizeof cur);
    if (strcmp(cur, argv[1]) != 0) { printf("FAIL: backend %s, not %s\n", cur, argv[1]); fails++; }

    double a[4] = {1, 3, 2, 4}, b[4] = {5, 7, 6, 8}, c[4] = {0}, one = 1, zero = 0;
    dgemm_("N", "N", &n, &n, &n, &one, a, &n, b, &n, &zero, c, &n, 1, 1);
    double ce[4] = {19, 43, 22, 50};   /* [1 2; 3 4] %*% [5 6; 7 8], by column */
    for (int i = 0; i < 4; i++)
        if (c[i] != ce[i]) { printf("FAIL: dgemm c[%d] = %g, not %g\n", i, c[i], ce[i]); fails++; }

    double s[4] = {4, 2, 2, 3};
    dpotrf_("L", &n, s, &n, &info, 1);
    if (info != 0 || s[0] != 2 || s[1] != 1 || fabs(s[3] - sqrt(2)) > 1e-15) {
        printf("FAIL: dpotrf info %d, L = %g %g %g\n", info, s[0], s[1], s[3]); fails++;
    }

    dgemm_("X", "N", &n, &n, &n, &one, a, &n, b, &n, &zero, c, &n, 1, 1);
    if (xerbla_calls != 1 || strncmp(xerbla_name, "DGEMM", 5) != 0) {
        printf("FAIL: dgemm with TRANSA X: %d calls to the program's xerbla\n", xerbla_calls); fails++;
    }
    dpotrf_("X", &n, s, &n, &info, 1);
    if (xerbla_calls != 2 || strncmp(xerbla_name, "DPOTRF", 6) != 0) {
        printf("FAIL: dpotrf with UPLO X: %d calls to the program's xerbla\n", xerbla_calls); fails++;
    }

    printf("%s: %s\n", argv[1], fails ? "FAILED" : "ok (dgemm, dpotrf, xerbla)");
    if (fails) return 1;
    FILE *f = fopen(argv[2], "w");
    if (!f) return 1;
    fputs("ok\n", f);
    return fclose(f) != 0;
}
