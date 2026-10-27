/* dgemm called from inside an OpenMP parallel region after an explicit
   openblas_set_num_threads(REQ), as a package's OpenMP loop calling the
   BLAS does: OpenBLAS must then run serially, whatever count was set
   (patches/openblas/0004).  omp-nested LIBOPENBLAS REQ, REQ 0 for none;
   prints ok; a hang is for the caller to time out (tests/omp-cases.sh).
   gcc -O2 -fopenmp omp-nested.c -ldl */
#include <dlfcn.h>
#include <omp.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    void *h = dlopen(argv[1], RTLD_NOW); if (!h) return 2;
    void (*set)(int) = dlsym(h, "openblas_set_num_threads");
    int (*get)(void) = dlsym(h, "openblas_get_num_threads");
    void (*dgemm)(const char *, const char *, int *, int *, int *, double *, double *, int *,
                  double *, int *, double *, double *, int *) = dlsym(h, "dgemm_");
    int req = atoi(argv[2]), n = 800;
    double *a = malloc(sizeof *a * n * n), *b = malloc(sizeof *b * n * n), *c = malloc(sizeof *c * n * n * 2);
    for (long i = 0; i < (long) n * n; i++) { a[i] = (i % 7) * 0.1; b[i] = (i % 5) * 0.2; }
    double one = 1, zero = 0;
    if (req > 0) set(req);
    #pragma omp parallel num_threads(2)
    {
        double *ct = c + (long) omp_get_thread_num() * n * n;
        dgemm("N", "N", &n, &n, &n, &one, a, &n, b, &n, &zero, ct, &n);
    }
    printf("ok (set %d, reports %d, in_parallel team 2)\n", req, get());
    return 0;
}
