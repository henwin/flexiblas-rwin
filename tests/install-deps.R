## Every dependency of the packages, Suggests included, as CRAN's binaries,
## from CRAN and the Bioconductor release that goes with this R, for
## R CMD check of their sources:  Rscript install-deps.R PACKAGE...
setRepositories(ind = 1:4)
repos <- getOption("repos")
repos["CRAN"] <- "https://cloud.r-project.org"
pkgs <- commandArgs(TRUE)
deps <- unique(unlist(tools::package_dependencies(pkgs, db = available.packages(repos = repos),
                                                  which = "most")))
base <- rownames(installed.packages(priority = "base"))
install.packages(setdiff(deps, c(base, rownames(installed.packages()))), repos = repos, dependencies = c("Depends", "Imports", "LinkingTo"))
