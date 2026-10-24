## The same checks as test-flexiblas.R, but through the flexiblas R package
## instead of the test shim, for the OPENBLAS backend.
library(flexiblas)

failures <- character()
check <- function(ok, what) {
    cat(sprintf("%-55s %s\n", what, if (ok) "ok" else "FAILED"))
    if (!ok) failures <<- c(failures, what)
}

check(isTRUE(flexiblas_avail()), "flexiblas_avail()")
cat("FlexiBLAS", format(flexiblas_version()), "\n")
cat("configured backends:", paste(flexiblas_list(), collapse = ", "), "\n")
cat("current backend:", flexiblas_current_backend(), "\n")
cat("OMP_NUM_THREADS:", Sys.getenv("OMP_NUM_THREADS", "(unset)"), "\n")

B <- matrix(rnorm(3000^2), 3000)
ref <- B %*% B

id <- flexiblas_load_backend("OPENBLAS")
flexiblas_switch(id)
check(flexiblas_current_backend() == "OPENBLAS", "switch to OPENBLAS")
check(isTRUE(all.equal(B %*% B, ref)), "product agrees with NETLIB")

for (k in c(1L, 2L)) {
    flexiblas_set_num_threads(k)
    tm <- system.time(B %*% B)
    check(flexiblas_get_num_threads() == k,
          sprintf("%d thread(s) after a product (reports %d)", k, flexiblas_get_num_threads()))
    cat(sprintf("  elapsed %.3fs, user %.3fs\n", tm[["elapsed"]], tm[["user.self"]]))
}

flexiblas_switch(flexiblas_load_backend("NETLIB"))
check(flexiblas_current_backend() == "NETLIB", "switch back to NETLIB")

cat("\n")
if (length(failures)) {
    cat("FAILURES:\n", paste0("  ", failures, "\n"), sep = "")
    quit(status = 1)
}
cat("all checks passed\n")
