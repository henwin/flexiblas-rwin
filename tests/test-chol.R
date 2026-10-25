## What chol() does with NaN, NA and Inf in its input, with the LAPACK in use.
## chol.default() reads only the upper triangle and, unlike eigen() and
## svd(), does not check all(is.finite(x)); whether non-finite input gives
## an error is then up to dpotrf. Reference LAPACK tests each pivot with
## disnan(); optimised dpotrf implementations need not.
##   Rscript test-chol.R [label]
label <- commandArgs(TRUE)[1]
if (is.na(label)) label <- if (nzchar(Sys.getenv("FLEXIBLAS"))) Sys.getenv("FLEXIBLAS") else "default"

set.seed(1)
S <- crossprod(matrix(rnorm(16), 4)) + diag(4)
put <- function(i, j, v) { S[i, j] <- v; S }
cases <- list(
    "NaN on the diagonal, [2,2]"    = put(2, 2, NaN),
    "NaN above the diagonal, [1,3]" = put(1, 3, NaN),
    "NaN below the diagonal, [3,1]" = put(3, 1, NaN),
    "NA on the diagonal, [2,2]"     = put(2, 2, NA),
    "Inf on the diagonal, [2,2]"    = put(2, 2, Inf),
    "Inf above the diagonal, [1,3]" = put(1, 3, Inf)
)
show <- function(x) tryCatch({
    R <- chol(x)
    sprintf("no error; %d NaN, %d NA, %d Inf in the factor",
            sum(is.nan(R)), sum(is.na(R) & !is.nan(R)), sum(is.infinite(R)))
}, error = function(e) paste("error:", conditionMessage(e)))

cat(sprintf("== %s (%s)\n", label, La_library()))
for (nm in names(cases)) cat(sprintf("  %-31s %s\n", nm, show(cases[[nm]])))
