/* Does dgemm finish when the thread count OpenBLAS asks OpenMP for is not
   what OpenMP gives?  The OpenMP build of OpenBLAS queues one piece of work
   per thread and the level-3 kernels synchronise across them, so a team
   smaller than requested hangs (patches/openblas).
     omp-team LIBOPENBLAS REQUESTED
   with OMP_NUM_THREADS, OMP_THREAD_LIMIT and OMP_DYNAMIC from the
   environment; prints what OpenBLAS reports before and after, and the
   time, or HANG after 5 s.  Built with: gcc -O2 -fopenmp omp-team.c -ldl
   (on Windows, without -ldl and with LoadLibrary in place of dlopen). */
#include <dlfcn.h>
#include <omp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void onalarm(int s) { (void) s; printf("HANG\n"); fflush(stdout); _exit(3); }

int main(int argc, char **argv)
{
    if (argc < 3) return 2;
    void *h = dlopen(argv[1], RTLD_NOW);
    if (!h) { fprintf(stderr, "%s\n", dlerror()); return 2; }
    void (*set)(int) = dlsym(h, "openblas_set_num_threads");
    int (*get)(void) = dlsym(h, "openblas_get_num_threads");
    void (*dgemm)(const char *, const char *, int *, int *, int *, double *, double *, int *,
                  double *, int *, double *, double *, int *) = dlsym(h, "dgemm_");
    int req = atoi(argv[2]), n = 1500, before, after;
    double *a = malloc(sizeof *a * n * n), *b = malloc(sizeof *b * n * n), *c = malloc(sizeof *c * n * n);
    for (long i = 0; i < (long) n * n; i++) { a[i] = (i % 7) * 0.1; b[i] = (i % 5) * 0.2; c[i] = 0; }
    double one = 1, zero = 0;
    before = get();
    set(req);
    int mid = get();
    signal(SIGALRM, onalarm);
    alarm(5);
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    dgemm("N", "N", &n, &n, &n, &one, a, &n, b, &n, &zero, c, &n);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    alarm(0);
    after = get();
    printf("ok %.2fs (reported %d, set %d -> %d, after %d; team max %d, limit %d, dynamic %d)\n",
           (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9, before, req, mid, after,
           omp_get_max_threads(), omp_get_thread_limit(), omp_get_dynamic());
    return 0;
}
