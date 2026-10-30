/* An OpenMP loop whose every iteration calls dgemm, as a package with its
 * own parallelism does; built with R CMD SHLIB and the R OpenMP flags, so
 * on Windows it gets its own static libgomp, like a package. Used by
 * test-omp-caller.R. */
#include <stdlib.h>
#include <R.h>
#include <Rinternals.h>
#include <R_ext/BLAS.h>
#ifdef _OPENMP
#include <omp.h>
#endif

SEXP omp_caller(SEXP n_, SEXP m_, SEXP reps_)
{
    int n = asInteger(n_), m = asInteger(m_), reps = asInteger(reps_);
    double one = 1, zero = 0;
    double *A = (double *) R_alloc((size_t) n * n, sizeof(double));
    for (size_t i = 0; i < (size_t) n * n; i++) A[i] = (double) (i % 7) / 7;
    double sum = 0;
#pragma omp parallel for num_threads(m) reduction(+:sum)
    for (int r = 0; r < m * reps; r++) {
        double *C = (double *) malloc((size_t) n * n * sizeof(double));
        F77_CALL(dgemm)("N", "N", &n, &n, &n, &one, A, &n, A, &n, &zero, C, &n
                        FCONE FCONE);
        sum += C[0];
        free(C);
    }
    return ScalarReal(sum);
}
