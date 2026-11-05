/* dgemm called from both threads of an OpenMP parallel region after an
   explicit openblas_set_num_threads(REQ), as a package's OpenMP loop
   calling the BLAS does; each thread's product must equal the one computed
   before the region.  Where the caller and OpenBLAS share one OpenMP
   runtime (Linux, LLVM's shared libomp on aarch64), OpenBLAS must run
   serially inside the region, or the level-3 kernels hang
   (patches/openblas/0004).  On x86_64 Windows each has its own static
   libgomp, OpenBLAS does not see the caller's region and opens a team of
   its own per call; the case then shows that such calls neither hang nor
   mix their results.  omp-nested LIBOPENBLAS REQ, REQ 0 for none; prints
   ok, or the largest difference and exits 1; a hang is for the caller to
   time out (tests/omp-cases.sh).  gcc -O2 -fopenmp omp-nested.c -ldl */
#include <dlfcn.h>
#include <math.h>
#include <omp.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    void *h = dlopen(argv[1], RTLD_NOW);
    if (!h) { fprintf(stderr, "%s\n", dlerror()); return 2; }
    void (*set)(int) = dlsym(h, "openblas_set_num_threads");
    int (*get)(void) = dlsym(h, "openblas_get_num_threads");
    void (*dgemm)(const char *, const char *, int *, int *, int *, double *, double *, int *,
                  double *, int *, double *, double *, int *) = dlsym(h, "dgemm_");
    if (!set || !get || !dgemm) { fprintf(stderr, "%s lacks an OpenBLAS function\n", argv[1]); return 2; }
    int req = atoi(argv[2]), n = 800;
    double *a = malloc(sizeof *a * n * n), *b = malloc(sizeof *b * n * n), *c = malloc(sizeof *c * n * n * 3);
    for (long i = 0; i < (long) n * n; i++) { a[i] = (i % 7) * 0.1; b[i] = (i % 5) * 0.2; }
    double one = 1, zero = 0, *ref = c + 2L * n * n, diff = 0;
    dgemm("N", "N", &n, &n, &n, &one, a, &n, b, &n, &zero, ref, &n);
    if (req > 0) set(req);
    #pragma omp parallel num_threads(2)
    {
        double *ct = c + (long) omp_get_thread_num() * n * n;
        dgemm("N", "N", &n, &n, &n, &one, a, &n, b, &n, &zero, ct, &n);
    }
    for (long i = 0; i < 2L * n * n; i++)
        diff = fmax(diff, fabs(c[i] - ref[i % ((long) n * n)]) / fmax(1, fabs(ref[i % ((long) n * n)])));
    if (diff > 1e-12) { printf("FAIL (set %d, largest relative difference %g)\n", req, diff); return 1; }
    printf("ok (set %d, reports %d, in_parallel team 2)\n", req, get());
    return 0;
}
