/* Call every routine of R's BLAS (the 76 in src/extra/blas/Rblas.def) in two
   DLLs built from the same sources with different flags, with the same
   arguments, and compare every output bit for bit.
     blas-bitwise ref.dll other.dll
   Arguments cover the sizes 0 to 33 (64 for level 1), unit, stride 2 and
   negative increments, every TRANS, UPLO, SIDE and DIAG, and alpha and beta
   in {0, 1, other}, which BLAS treat as special cases. Data are uniform on
   (-1, 1), with NA, NaN and Inf in every fourth case, and the same for both
   DLLs. Exit status 1 when routines differ, 2 on errors. */
#include <windows.h>
#include <complex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef double complex dcx;
#define NBUF 4096
static double X[NBUF], Y[NBUF], A[NBUF], B[NBUF], C[NBUF], P[8];
static double xs[2][NBUF], ys[2][NBUF], as[2][NBUF], bs[2][NBUF], cs[2][NBUF], ps[2][8];
static double res[2][2];                       /* scalar results */
static HMODULE lib[2];
static int cur;                                /* which DLL is being called */

static void *sym(const char *name)
{
    void *p = (void *)(INT_PTR) GetProcAddress(lib[cur], name);
    if (!p) { fprintf(stderr, "%s not found\n", name); exit(2); }
    return p;
}

static unsigned long long rs;
static double unif(void)                       /* xorshift64*, on (-1, 1) */
{
    rs ^= rs >> 12; rs ^= rs << 25; rs ^= rs >> 27;
    return ((rs * 2685821657736338717ULL) >> 11) * 0x1.0p-52 - 1.0;
}
/* Every fourth case also has R's NA (a NaN with payload 1954), NaN, Inf and
   -Inf in about one entry in 50, since which NaN survives an operation, NA
   or a plain NaN, may depend on the code the compiler generates. */
static double special(void)
{
    static const unsigned long long na = 0x7FF00000000007A2ULL;
    double v; int k = (int) ((unif() + 1) * 2);
    if (k == 0) memcpy(&v, &na, sizeof v);
    else v = k == 1 ? NAN : k == 2 ? INFINITY : -INFINITY;
    return v;
}
static void fill(unsigned long long seed)
{
    rs = seed * 0x9E3779B97F4A7C15ULL + 1;
    for (int i = 0; i < NBUF; i++) { X[i] = unif(); Y[i] = unif(); A[i] = unif(); B[i] = unif(); C[i] = unif(); }
    for (int i = 0; i < 8; i++) P[i] = unif();
    if (seed % 4 == 0) {
        double *v[] = {X, Y, A, B, C};
        for (int j = 0; j < 5; j++)
            for (int i = 0; i < NBUF; i++)
                if (unif() > 0.96) v[j][i] = special();
    }
}

/* the argument values a case is built from */
static const int S1[] = {0, 1, 2, 3, 4, 7, 8, 16, 17, 33, 64}, NS1 = 11;
static const int S2[] = {0, 1, 2, 3, 5, 8, 17, 33}, NS2 = 8;
static const int S3[] = {0, 1, 3, 8, 17, 33}, NS3 = 6;
static const int INC[] = {1, 2, -2}, NINC = 3;
static const char TR[] = "NTC", UL[] = "UL", SD[] = "LR", DG[] = "NU";
static const double AL[] = {0.7, 0.0, 1.0}, BE[] = {1.3, 0.0, 1.0};
static const dcx ZAL[] = {0.7 - 0.3 * I, 0.0, 1.0}, ZBE[] = {1.1 + 0.4 * I, 0.0, 1.0};
static const int KB[] = {0, 1, 3};
#define CL (size_t) 1                          /* hidden length of a CHARACTER*1 */

/* decode case number c into digits of the given radices */
static int dig(int *c, int r) { int d = *c % r; *c /= r; return d; }

typedef int (*test_fn)(int c);                 /* returns 0 when c is past the end */

/* ---- level 1 ---- */
static int t_dasum(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; if (c) return 0; if (ix < 0) return 1;
    res[cur][0] = ((double (*)(int *, double *, int *)) sym("dasum_"))(&n, X, &ix); return 1; }
static int t_dnrm2(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; if (c) return 0; if (ix < 0) return 1;
    res[cur][0] = ((double (*)(int *, double *, int *)) sym("dnrm2_"))(&n, X, &ix); return 1; }
static int t_idamax(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; if (c) return 0; if (ix < 0) return 1;
    res[cur][0] = ((int (*)(int *, double *, int *)) sym("idamax_"))(&n, X, &ix); return 1; }
static int t_dzasum(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; if (c) return 0; if (ix < 0) return 1;
    res[cur][0] = ((double (*)(int *, double *, int *)) sym("dzasum_"))(&n, X, &ix); return 1; }
static int t_dznrm2(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; if (c) return 0; if (ix < 0) return 1;
    res[cur][0] = ((double (*)(int *, double *, int *)) sym("dznrm2_"))(&n, X, &ix); return 1; }
static int t_izamax(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; if (c) return 0; if (ix < 0) return 1;
    res[cur][0] = ((int (*)(int *, double *, int *)) sym("izamax_"))(&n, X, &ix); return 1; }
static int t_dcabs1(int c) { if (c) return 0;
    res[cur][0] = ((double (*)(double *)) sym("dcabs1_"))(X); return 1; }
static int t_dscal(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; double a = AL[dig(&c, 3)]; if (c) return 0; if (ix < 0) return 1;
    ((void (*)(int *, double *, double *, int *)) sym("dscal_"))(&n, &a, X, &ix); return 1; }
static int t_zdscal(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; double a = AL[dig(&c, 3)]; if (c) return 0; if (ix < 0) return 1;
    ((void (*)(int *, double *, double *, int *)) sym("zdscal_"))(&n, &a, X, &ix); return 1; }
static int t_zscal(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)]; dcx a = ZAL[dig(&c, 3)]; if (c) return 0; if (ix < 0) return 1;
    ((void (*)(int *, dcx *, double *, int *)) sym("zscal_"))(&n, &a, X, &ix); return 1; }

#define XY(name) static int t_##name(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)], iy = INC[dig(&c, NINC)]; if (c) return 0; \
    ((void (*)(int *, double *, int *, double *, int *)) sym(#name "_"))(&n, X + 200, &ix, Y + 200, &iy); return 1; }
XY(dcopy) XY(dswap) XY(zcopy) XY(zswap)
static int t_ddot(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)], iy = INC[dig(&c, NINC)]; if (c) return 0;
    res[cur][0] = ((double (*)(int *, double *, int *, double *, int *)) sym("ddot_"))(&n, X + 200, &ix, Y + 200, &iy); return 1; }
static int t_zdot(int c, const char *name) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)], iy = INC[dig(&c, NINC)]; if (c) return 0;
    dcx r = ((dcx (*)(int *, double *, int *, double *, int *)) sym(name))(&n, X + 200, &ix, Y + 200, &iy);
    res[cur][0] = creal(r); res[cur][1] = cimag(r); return 1; }
static int t_zdotc(int c) { return t_zdot(c, "zdotc_"); }
static int t_zdotu(int c) { return t_zdot(c, "zdotu_"); }
static int t_daxpy(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)], iy = INC[dig(&c, NINC)]; double a = AL[dig(&c, 3)]; if (c) return 0;
    ((void (*)(int *, double *, double *, int *, double *, int *)) sym("daxpy_"))(&n, &a, X + 200, &ix, Y + 200, &iy); return 1; }
static int t_zaxpy(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)], iy = INC[dig(&c, NINC)]; dcx a = ZAL[dig(&c, 3)]; if (c) return 0;
    ((void (*)(int *, dcx *, double *, int *, double *, int *)) sym("zaxpy_"))(&n, &a, X + 200, &ix, Y + 200, &iy); return 1; }
static int t_drot(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)], iy = INC[dig(&c, NINC)]; if (c) return 0;
    double cc = 0.6, ss = 0.8;
    ((void (*)(int *, double *, int *, double *, int *, double *, double *)) sym("drot_"))(&n, X + 200, &ix, Y + 200, &iy, &cc, &ss); return 1; }
static int t_zdrot(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)], iy = INC[dig(&c, NINC)]; if (c) return 0;
    double cc = 0.6, ss = 0.8;
    ((void (*)(int *, double *, int *, double *, int *, double *, double *)) sym("zdrot_"))(&n, X + 200, &ix, Y + 200, &iy, &cc, &ss); return 1; }
static int t_drotm(int c) { int n = S1[dig(&c, NS1)], ix = INC[dig(&c, NINC)], iy = INC[dig(&c, NINC)]; int fl = dig(&c, 4); if (c) return 0;
    P[0] = fl - 2.0;                           /* the flags -2, -1, 0 and 1 */
    ((void (*)(int *, double *, int *, double *, int *, double *)) sym("drotm_"))(&n, X + 200, &ix, Y + 200, &iy, P); return 1; }
static int t_drotg(int c) { if (c >= 64) return 0; P[0] = X[c]; P[1] = Y[c];
    ((void (*)(double *, double *, double *, double *)) sym("drotg_"))(P, P + 1, P + 2, P + 3); return 1; }
static int t_zrotg(int c) { if (c >= 64) return 0; P[0] = X[2 * c]; P[1] = X[2 * c + 1]; P[2] = Y[2 * c]; P[3] = Y[2 * c + 1];
    ((void (*)(double *, double *, double *, double *)) sym("zrotg_"))(P, P + 2, P + 4, P + 5); return 1; }
static int t_drotmg(int c) { if (c >= 64) return 0; P[0] = 1 + X[c]; P[1] = 1 + Y[c]; P[2] = A[c]; P[3] = B[c];
    ((void (*)(double *, double *, double *, double *, double *)) sym("drotmg_"))(P, P + 1, P + 2, P + 3, P + 4); return 1; }

/* ---- level 2 ---- */
#define GE2(name, T, al, be) static int t_##name(int c) { int m = S2[dig(&c, NS2)], n = S2[dig(&c, NS2)]; char t = TR[dig(&c, 3)]; \
    int ix = INC[dig(&c, 2) * 2], iy = ix; T a = al[dig(&c, 3)], b = be[dig(&c, 3)]; if (c) return 0; int ld = (m > 0 ? m : 1) + 3; \
    ((void (*)(char *, int *, int *, T *, double *, int *, double *, int *, T *, double *, int *, size_t)) sym(#name "_")) \
        (&t, &m, &n, &a, A, &ld, X + 200, &ix, &b, Y + 200, &iy, CL); return 1; }
GE2(dgemv, double, AL, BE) GE2(zgemv, dcx, ZAL, ZBE)
#define GB2(name, T, al, be) static int t_##name(int c) { int m = S2[dig(&c, NS2)], n = S2[dig(&c, NS2)]; char t = TR[dig(&c, 3)]; \
    int kl = KB[dig(&c, 3)], ku = KB[dig(&c, 3)]; int ix = INC[dig(&c, 2) * 2], iy = ix; T a = al[dig(&c, 3)], b = be[dig(&c, 3)]; \
    if (c) return 0; int ld = kl + ku + 3; \
    ((void (*)(char *, int *, int *, int *, int *, T *, double *, int *, double *, int *, T *, double *, int *, size_t)) sym(#name "_")) \
        (&t, &m, &n, &kl, &ku, &a, A, &ld, X + 200, &ix, &b, Y + 200, &iy, CL); return 1; }
GB2(dgbmv, double, AL, BE) GB2(zgbmv, dcx, ZAL, ZBE)
#define GER(name, T, al) static int t_##name(int c) { int m = S2[dig(&c, NS2)], n = S2[dig(&c, NS2)]; int ix = INC[dig(&c, 2) * 2], iy = ix; \
    T a = al[dig(&c, 3)]; if (c) return 0; int ld = (m > 0 ? m : 1) + 3; \
    ((void (*)(int *, int *, T *, double *, int *, double *, int *, double *, int *)) sym(#name "_"))(&m, &n, &a, X + 200, &ix, Y + 200, &iy, A, &ld); return 1; }
GER(dger, double, AL) GER(zgerc, dcx, ZAL) GER(zgeru, dcx, ZAL)
#define SY2(name, T, al, be) static int t_##name(int c) { int n = S2[dig(&c, NS2)]; char u = UL[dig(&c, 2)]; int ix = INC[dig(&c, 2) * 2], iy = ix; \
    T a = al[dig(&c, 3)], b = be[dig(&c, 3)]; if (c) return 0; int ld = (n > 0 ? n : 1) + 3; \
    ((void (*)(char *, int *, T *, double *, int *, double *, int *, T *, double *, int *, size_t)) sym(#name "_")) \
        (&u, &n, &a, A, &ld, X + 200, &ix, &b, Y + 200, &iy, CL); return 1; }
SY2(dsymv, double, AL, BE) SY2(zhemv, dcx, ZAL, ZBE)
#define SB2(name, T, al, be) static int t_##name(int c) { int n = S2[dig(&c, NS2)]; char u = UL[dig(&c, 2)]; int k = KB[dig(&c, 3)]; \
    int ix = INC[dig(&c, 2) * 2], iy = ix; T a = al[dig(&c, 3)], b = be[dig(&c, 3)]; if (c) return 0; int ld = k + 3; \
    ((void (*)(char *, int *, int *, T *, double *, int *, double *, int *, T *, double *, int *, size_t)) sym(#name "_")) \
        (&u, &n, &k, &a, A, &ld, X + 200, &ix, &b, Y + 200, &iy, CL); return 1; }
SB2(dsbmv, double, AL, BE) SB2(zhbmv, dcx, ZAL, ZBE)
#define SP2(name, T, al, be) static int t_##name(int c) { int n = S2[dig(&c, NS2)]; char u = UL[dig(&c, 2)]; int ix = INC[dig(&c, 2) * 2], iy = ix; \
    T a = al[dig(&c, 3)], b = be[dig(&c, 3)]; if (c) return 0; \
    ((void (*)(char *, int *, T *, double *, double *, int *, T *, double *, int *, size_t)) sym(#name "_")) \
        (&u, &n, &a, A, X + 200, &ix, &b, Y + 200, &iy, CL); return 1; }
SP2(dspmv, double, AL, BE) SP2(zhpmv, dcx, ZAL, ZBE)
#define R1(name, T, al, packed) static int t_##name(int c) { int n = S2[dig(&c, NS2)]; char u = UL[dig(&c, 2)]; int ix = INC[dig(&c, 2) * 2]; \
    T a = al[dig(&c, 3)]; if (c) return 0; int ld = (n > 0 ? n : 1) + 3; \
    if (packed) ((void (*)(char *, int *, T *, double *, int *, double *, size_t)) sym(#name "_"))(&u, &n, &a, X + 200, &ix, A, CL); \
    else ((void (*)(char *, int *, T *, double *, int *, double *, int *, size_t)) sym(#name "_"))(&u, &n, &a, X + 200, &ix, A, &ld, CL); return 1; }
R1(dsyr, double, AL, 0) R1(dspr, double, AL, 1) R1(zher, double, AL, 0) R1(zhpr, double, AL, 1)
#define R2(name, T, al, packed) static int t_##name(int c) { int n = S2[dig(&c, NS2)]; char u = UL[dig(&c, 2)]; int ix = INC[dig(&c, 2) * 2], iy = ix; \
    T a = al[dig(&c, 3)]; if (c) return 0; int ld = (n > 0 ? n : 1) + 3; \
    if (packed) ((void (*)(char *, int *, T *, double *, int *, double *, int *, double *, size_t)) sym(#name "_"))(&u, &n, &a, X + 200, &ix, Y + 200, &iy, A, CL); \
    else ((void (*)(char *, int *, T *, double *, int *, double *, int *, double *, int *, size_t)) sym(#name "_"))(&u, &n, &a, X + 200, &ix, Y + 200, &iy, A, &ld, CL); return 1; }
R2(dsyr2, double, AL, 0) R2(dspr2, double, AL, 1) R2(zher2, dcx, ZAL, 0) R2(zhpr2, dcx, ZAL, 1)
/* triangular: full (TR), banded (TB) and packed (TP), multiply and solve */
#define TR2(name, kind) static int t_##name(int c) { int n = S2[dig(&c, NS2)]; char u = UL[dig(&c, 2)], t = TR[dig(&c, 3)], d = DG[dig(&c, 2)]; \
    int k = KB[dig(&c, 3)]; int ix = INC[dig(&c, 2) * 2]; if (c) return 0; \
    if (kind == 0) { if (k) return 1; int ld = (n > 0 ? n : 1) + 3; \
        ((void (*)(char *, char *, char *, int *, double *, int *, double *, int *, size_t, size_t, size_t)) sym(#name "_"))(&u, &t, &d, &n, A, &ld, X + 200, &ix, CL, CL, CL); } \
    else if (kind == 1) { int ld = k + 3; \
        ((void (*)(char *, char *, char *, int *, int *, double *, int *, double *, int *, size_t, size_t, size_t)) sym(#name "_"))(&u, &t, &d, &n, &k, A, &ld, X + 200, &ix, CL, CL, CL); } \
    else { if (k) return 1; \
        ((void (*)(char *, char *, char *, int *, double *, double *, int *, size_t, size_t, size_t)) sym(#name "_"))(&u, &t, &d, &n, A, X + 200, &ix, CL, CL, CL); } return 1; }
TR2(dtrmv, 0) TR2(dtrsv, 0) TR2(dtbmv, 1) TR2(dtbsv, 1) TR2(dtpmv, 2) TR2(dtpsv, 2)
TR2(ztrmv, 0) TR2(ztrsv, 0) TR2(ztbmv, 1) TR2(ztbsv, 1) TR2(ztpmv, 2) TR2(ztpsv, 2)

/* ---- level 3 ---- */
#define GEMM(name, T, al, be) static int t_##name(int c) { int m = S3[dig(&c, NS3)], n = S3[dig(&c, NS3)], k = S3[dig(&c, NS3)]; \
    char ta = TR[dig(&c, 3)], tb = TR[dig(&c, 3)]; T a = al[dig(&c, 3)], b = be[dig(&c, 3)]; if (c) return 0; \
    int lda = (ta == 'N' ? m : k) + 3, ldb = (tb == 'N' ? k : n) + 3, ldc = m + 3; \
    ((void (*)(char *, char *, int *, int *, int *, T *, double *, int *, double *, int *, T *, double *, int *, size_t, size_t)) sym(#name "_")) \
        (&ta, &tb, &m, &n, &k, &a, A, &lda, B, &ldb, &b, C, &ldc, CL, CL); return 1; }
GEMM(dgemm, double, AL, BE) GEMM(zgemm, dcx, ZAL, ZBE)
#define GEMMTR(name, T, al, be) static int t_##name(int c) { int n = S3[dig(&c, NS3)], k = S3[dig(&c, NS3)]; char u = UL[dig(&c, 2)]; \
    char ta = TR[dig(&c, 3)], tb = TR[dig(&c, 3)]; T a = al[dig(&c, 3)], b = be[dig(&c, 3)]; if (c) return 0; \
    int lda = (ta == 'N' ? n : k) + 3, ldb = (tb == 'N' ? k : n) + 3, ldc = n + 3; \
    ((void (*)(char *, char *, char *, int *, int *, T *, double *, int *, double *, int *, T *, double *, int *, size_t, size_t, size_t)) sym(#name "_")) \
        (&u, &ta, &tb, &n, &k, &a, A, &lda, B, &ldb, &b, C, &ldc, CL, CL, CL); return 1; }
GEMMTR(dgemmtr, double, AL, BE) GEMMTR(zgemmtr, dcx, ZAL, ZBE)
#define SYMM(name, T, al, be) static int t_##name(int c) { int m = S3[dig(&c, NS3)], n = S3[dig(&c, NS3)]; char s = SD[dig(&c, 2)], u = UL[dig(&c, 2)]; \
    T a = al[dig(&c, 3)], b = be[dig(&c, 3)]; if (c) return 0; int lda = (s == 'L' ? m : n) + 3, ldb = m + 3, ldc = m + 3; \
    ((void (*)(char *, char *, int *, int *, T *, double *, int *, double *, int *, T *, double *, int *, size_t, size_t)) sym(#name "_")) \
        (&s, &u, &m, &n, &a, A, &lda, B, &ldb, &b, C, &ldc, CL, CL); return 1; }
SYMM(dsymm, double, AL, BE) SYMM(zsymm, dcx, ZAL, ZBE) SYMM(zhemm, dcx, ZAL, ZBE)
/* SYRK and HERK; the transposes allowed are N and T (real, complex
   symmetric) or N and C (Hermitian) */
#define SYRK(name, T, U, al, be, t2) static int t_##name(int c) { int n = S3[dig(&c, NS3)], k = S3[dig(&c, NS3)]; char u = UL[dig(&c, 2)]; \
    char t = dig(&c, 2) ? t2 : 'N'; T a = al[dig(&c, 3)]; U b = be[dig(&c, 3)]; if (c) return 0; int lda = (t == 'N' ? n : k) + 3, ldc = n + 3; \
    ((void (*)(char *, char *, int *, int *, T *, double *, int *, U *, double *, int *, size_t, size_t)) sym(#name "_")) \
        (&u, &t, &n, &k, &a, A, &lda, &b, C, &ldc, CL, CL); return 1; }
SYRK(dsyrk, double, double, AL, BE, 'T') SYRK(zsyrk, dcx, dcx, ZAL, ZBE, 'T') SYRK(zherk, double, double, AL, BE, 'C')
#define SYR2K(name, T, U, al, be, t2) static int t_##name(int c) { int n = S3[dig(&c, NS3)], k = S3[dig(&c, NS3)]; char u = UL[dig(&c, 2)]; \
    char t = dig(&c, 2) ? t2 : 'N'; T a = al[dig(&c, 3)]; U b = be[dig(&c, 3)]; if (c) return 0; int ld = (t == 'N' ? n : k) + 3, ldc = n + 3; \
    ((void (*)(char *, char *, int *, int *, T *, double *, int *, double *, int *, U *, double *, int *, size_t, size_t)) sym(#name "_")) \
        (&u, &t, &n, &k, &a, A, &ld, B, &ld, &b, C, &ldc, CL, CL); return 1; }
SYR2K(dsyr2k, double, double, AL, BE, 'T') SYR2K(zsyr2k, dcx, dcx, ZAL, ZBE, 'T') SYR2K(zher2k, dcx, double, ZAL, BE, 'C')
#define TRMM(name, T, al) static int t_##name(int c) { int m = S3[dig(&c, NS3)], n = S3[dig(&c, NS3)]; char s = SD[dig(&c, 2)], u = UL[dig(&c, 2)]; \
    char t = TR[dig(&c, 3)], d = DG[dig(&c, 2)]; T a = al[dig(&c, 3)]; if (c) return 0; int lda = (s == 'L' ? m : n) + 3, ldb = m + 3; \
    ((void (*)(char *, char *, char *, char *, int *, int *, T *, double *, int *, double *, int *, size_t, size_t, size_t, size_t)) sym(#name "_")) \
        (&s, &u, &t, &d, &m, &n, &a, A, &lda, B, &ldb, CL, CL, CL, CL); return 1; }
TRMM(dtrmm, double, AL) TRMM(dtrsm, double, AL) TRMM(ztrmm, dcx, ZAL) TRMM(ztrsm, dcx, ZAL)

static int t_lsame(int c) { if (c >= 26 * 26) return 0; char a = 'A' + c % 26, b = 'a' + c / 26;
    res[cur][0] = ((int (*)(char *, char *, size_t, size_t)) sym("lsame_"))(&a, &b, CL, CL); return 1; }

#define T(name) { #name, t_##name }
static const struct { const char *name; test_fn f; } tests[] = {
    T(dasum), T(daxpy), T(dcabs1), T(dcopy), T(ddot), T(dgbmv), T(dgemm), T(dgemmtr), T(dgemv), T(dger),
    T(dnrm2), T(drot), T(drotg), T(drotm), T(drotmg), T(dsbmv), T(dscal), T(dspmv), T(dspr), T(dspr2),
    T(dswap), T(dsymm), T(dsymv), T(dsyr), T(dsyr2), T(dsyr2k), T(dsyrk), T(dtbmv), T(dtbsv), T(dtpmv),
    T(dtpsv), T(dtrmm), T(dtrmv), T(dtrsm), T(dtrsv), T(dzasum), T(dznrm2), T(idamax), T(izamax), T(lsame),
    T(zaxpy), T(zcopy), T(zdotc), T(zdotu), T(zdrot), T(zdscal), T(zgbmv), T(zgemm), T(zgemmtr), T(zgemv),
    T(zgerc), T(zgeru), T(zhbmv), T(zhemm), T(zhemv), T(zher), T(zher2), T(zher2k), T(zherk), T(zhpmv),
    T(zhpr), T(zhpr2), T(zrotg), T(zscal), T(zswap), T(zsymm), T(zsyr2k), T(zsyrk), T(ztbmv), T(ztbsv),
    T(ztpmv), T(ztpsv), T(ztrmm), T(ztrmv), T(ztrsm), T(ztrsv)
};

/* How two output arrays differ: 0 not at all; 1 only in which NaN, e.g. NA
   against a plain NaN; 2 in a value that is not NaN in both, or NaN in
   one only */
static int kind(const double *a, const double *b, int n)
{
    int k = 0;
    for (int i = 0; i < n; i++) {
        if (!memcmp(a + i, b + i, sizeof *a)) continue;
        if (isnan(a[i]) && isnan(b[i])) { if (!k) k = 1; }
        else return 2;
    }
    return k;
}

int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr, "usage: blas-bitwise ref.dll other.dll\n"); return 2; }
    for (int i = 0; i < 2; i++)
        if (!(lib[i] = LoadLibraryExA(argv[i + 1], NULL, LOAD_WITH_ALTERED_SEARCH_PATH))) { fprintf(stderr, "cannot load %s\n", argv[i + 1]); return 2; }
    int ntest = sizeof tests / sizeof tests[0], nbad = 0, nval = 0;
    long total = 0;
    for (int t = 0; t < ntest; t++) {
        long ncase = 0, ndiff = 0, nnan = 0;
        for (int c = 0;; c++) {
            int more = 1;
            for (cur = 0; cur < 2; cur++) {
                fill(c + 1);
                memset(res[cur], 0, sizeof res[cur]);
                more = tests[t].f(c);
                memcpy(xs[cur], X, sizeof X); memcpy(ys[cur], Y, sizeof Y); memcpy(as[cur], A, sizeof A);
                memcpy(bs[cur], B, sizeof B); memcpy(cs[cur], C, sizeof C); memcpy(ps[cur], P, sizeof P);
            }
            if (!more) break;
            ncase++;
            int k = kind(xs[0], xs[1], NBUF), k2;
            if ((k2 = kind(ys[0], ys[1], NBUF)) > k) k = k2;
            if ((k2 = kind(as[0], as[1], NBUF)) > k) k = k2;
            if ((k2 = kind(bs[0], bs[1], NBUF)) > k) k = k2;
            if ((k2 = kind(cs[0], cs[1], NBUF)) > k) k = k2;
            if ((k2 = kind(ps[0], ps[1], 8)) > k) k = k2;
            if ((k2 = kind(res[0], res[1], 2)) > k) k = k2;
            if (k) ndiff++;
            if (k == 1) nnan++;
        }
        total += ncase;
        if (ndiff) nbad++;
        if (ndiff > nnan) nval++;
        printf("%-8s %6ld cases, %6ld differ, %6ld of them only in which NaN\n", tests[t].name, ncase, ndiff, nnan);
    }
    printf("%d of %d routines differ (%ld cases), %d of them in more than which NaN\n", nbad, ntest, total, nval);
    return nbad > 0;
}
