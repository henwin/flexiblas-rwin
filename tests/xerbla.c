/* BLAS and LAPACK calls with an invalid first argument, for
   tests/test-xerbla.R: the routine reports it through xerbla, which in R
   is R's own and signals an R error.  Linked with $(LAPACK_LIBS)
   $(BLAS_LIBS) as a package is, so that it also checks that a package
   links against Rblas.dll and Rlapack.dll. */
#define USE_FC_LEN_T
#include <Rinternals.h>
#include <R_ext/BLAS.h>
#include <R_ext/Lapack.h>
#ifndef FCONE
# define FCONE
#endif

SEXP bad_dgemm(void)
{
    double a = 1, b = 1, c = 0, one = 1, zero = 0;
    int n = 1;
    F77_CALL(dgemm)("X", "N", &n, &n, &n, &one, &a, &n, &b, &n, &zero, &c, &n FCONE FCONE);
    return R_NilValue;
}

SEXP bad_dpotrf(void)
{
    double a = 1;
    int n = 1, info = 0;
    F77_CALL(dpotrf)("X", &n, &a, &n, &info FCONE);
    return ScalarInteger(info);
}
