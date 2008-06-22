#
# 	hm.R
#
#	$Revision: 1.16 $	$Date: 2008/06/23 06:06:14 $
#
################################################################
#
#  Haldane-type models
#
#

hm <- function(HalfT, M0=NULL, dM=NULL, ...,
               N2 = list(HalfT=HalfT, M0=M0, dM=dM),
               He = NULL,
               title="user-defined model",
               cnames=NULL,
               mixrule="N2") {
  if(length(list(...)) > 0)
    warning("Some unrecognised arguments were ignored")
  validate <- function(X, cnames) {
    Xname <- deparse(substitute(X))
    isnull <- unlist(lapply(X, is.null))
    X <- X[!isnull]
    ok <- unlist(lapply(X, function(z) { is.numeric(z) && all(z > 0) }))
    if(!all(ok))
      stop(paste("All", Xname, "data should be positive numbers"))
    if(!all(nzchar(names(X))))
      stop(paste("some components of", sQuote(Xname), "are not labelled"))
    else if(!all(names(X) %in% c("HalfT", "M0", "dM")))
      stop(paste("some components of", sQuote(Xname),
                 "are not labelled HalfT, M0 or dM"))
    if(with(X, is.null(M0) && !is.null(dM)))
      stop("If dM is provided, then M0 must be provided")
    X <- as.data.frame(X)
    if(!is.null(cnames)) {
      if(length(cnames) != nrow(X))
        stop(paste("length of cnames = ", length(cnames),
                   "!=", nrow(X), "= number of compartments"))
      rownames(X) <- cnames
    }
    return(X)
  }

  N2 <- validate(N2, cnames)
  pars <- list(N2=N2)
  nc <- nrow(N2)
  if(!is.null(He)) {
    He <- validate(He, cnames)
    if(nrow(He) != nc)
      stop("Data for He and N2 have different numbers of compartments")
    pars <- append(pars, list(He = He))
  }

  out <- list(title=title, pars=pars)
  
  mixtable <- c("interpolate", "N2")
  if(is.na(m <- pmatch(mixrule, mixtable)))
    stop(paste("Unrecognised option", dQuote(mixrule), "for mixrule"))
  out$mixrule <- mixtable[m]

  class(out) <- c("hm", class(out))
  return(out)
}

print.hm <- function(x, ...) {
  stopifnot(inherits(x, "hm"))
  cat("Haldane type decompression model\n")
  y <- summary(x)
  cat(paste("Name:", y$title, "\n"))
  cat(paste(y$nc, ngettext(y$nc, "compartment\n", "compartments\n")))
  species <- y$species
  cat(paste("inert", ngettext(length(species), "gas:", "gases:"),
            paste(species, collapse=", "), "\n"))
  print(as.data.frame(x))
  return(invisible(NULL))
}

summary.hm <- function(object, ...) {
  stopifnot(inherits(object, "hm"))
  pars <- object$pars
  # names of inert gas species 
  species <- names(pars)
  # compartments
  cnames <- rownames(pars[[1]])
  nc     <- nrow(pars[[1]])
  # modelling capability for each species: 1 = halftimes, 2 = ndl, 3 = deco
  capabil <- lapply(pars, ncol)
  # rule for deriving M-values for mixed gases
  mixrule <- object$mixrule
  out <- list(title   = object$title,
              species = species,
              cnames  = cnames,
              nc      = nc,
              capabil = capabil,
              mixrule = mixrule,
              df = as.data.frame(object))
  class(out) <- c("summary.hm", class(out))
  return(out)
}

print.summary.hm <- function(x, ...) {
  cat("Haldane type decompression model\n")
  cat(paste("Name:", x$title, "\n"))
  cat(paste(x$nc, ngettext(x$nc, "compartment\n", "compartments\n")))
  cat(paste("inert gas species:",
            paste(x$species, collapse=", "), "\n"))
  for(i in seq(length(x$capabil))) {
    cat(paste("Data for ", x$species[i], ":\t ", sep="" ))
    switch(x$capabil[[i]],
         cat("Halftimes only\n"),
         cat("Halftimes and Surfacing M-values\n"),
         cat("Halftimes and M-values for any depth\n"))
  }
  cat(paste("Rule for generating M-values of mixed gases:", x$mixrule, "\n"))
  print(x$df, ...)
  return(invisible(NULL))
}

as.data.frame.hm <- function(x, ...) {
  as.data.frame(x$pars, ...)
}

#################
#

# extracting properties/data

capable <- function(model, g="N2", what="HalfT") {
  stopifnot(inherits(model, "hm"))
  y <- summary(model)
  if(is.gas(g)) {
    ok <- TRUE
    if(g$fN2 > 0) ok <- capable(model, "N2", what)
    if(g$fHe > 0) ok <- ok && capable(model, "He", what)
    return(ok)
  }
  if(is.dive(g)) 
    return(capable(model, allspecies(g, inert=FALSE), what=what))
  if(!is.character(g))
    stop("Unrecognised format for argument g")
  # character string or character vector
  if(length(g) > 1) {
    g <- as.list(g)
    ok <- all(unlist(lapply(g, function(x, ...) { capable(g=x, ...) },
                            model=model, what=what)))
    return(ok)
  }
  # single character string
  if(g == "O2")
    return(TRUE)
  if(!(g %in% y$species))
    return(FALSE)
  k <- y$capabil[[g]]
  switch(what,
         HalfT=return(k >= 1),
         M0   =return(k >= 2),
         dM   =return(k >= 3))
  return(NA)
}

param <- function(model, species="N2", what="HalfT") {
  stopifnot(inherits(model, "hm"))
  return(model$pars[[species]][[what]])
}

#######
#

M0mix <- function(model, fN2, fHe) {
  stopifnot(inherits(model, "hm"))
  mixrule <- summary(model)$mixrule
  ntimes <- length(fN2)
  M0.N2 <- param(model, "N2", "M0")
  one <- rep(1, ntimes)
  if(all(fHe == 0))
    return(outer(one, M0.N2, "*"))
  # Helium is present
  if(!capable(model, "He", "M0"))
    stop("Model does not provide surfacing M-values for Helium")
  switch(mixrule,
         N2 = { 
           M0 <- outer(one, M0.N2, "*")
         },
         interpolate={
           dM.N2 <- param(model, "N2", "dM")
           M0.He <- param(model, "He", "M0")
           dM.He <- param(model, "He", "dM")
           # Buehlmann equivalent parameters
           aN2 <- M0.N2 - dM.N2
           bN2 <- 1/dM.N2
           aHe <- M0.He - dM.He
           bHe <- 1/dM.He
           # mixture fraction (time-dependent)
           fIG <- fN2+fHe
           denom <- ifelse(fIG > 0, fIG, 1)
           z <- fN2/denom
           # apply to Buehlmann parameters
           a <- outer(z, aN2, "*") + outer(1-z, aHe, "*")
           b <- outer(z, bN2, "*") + outer(1-z, bHe, "*")
           # convert back to M0
           M0 <- a + 1/b
         }
         )
  return(M0)
}

  
###################################################################
#
#  Haldane type models that are installed
#

pickmodel <- function(model) {
  if(missing(model)) {
    cat(paste("Available options are:",
              paste(sQuote(names(.scuba.models)), collapse=", "), "\n"))
    return(invisible(NULL))
  }
  
  stopifnot(is.character(model))

  k <- pmatch(model, names(.scuba.models))
  if(is.na(k))
    stop(paste("Unrecognised model", sQuote(model)))
  return(.scuba.models[[k]])
}

################################################################
#
#  Standard models
#
#

.buehlmannL16A <-
  list(tN2=c(4, 5, 8, 12.5, 18.5, 27, 38.3, 54.3, 77,
             109, 146, 187, 239, 305, 390, 498, 635),
       aN2=c(
         1.2599,
         1.1696,
         1.0000,
         0.8618,
         0.7562,	
         0.6667,	
         0.5933,
         0.5282,
         0.4701,	
         0.4187,
         0.3798,
         0.3497,
         0.3223,
         0.2971,
         0.2737,
         0.2523,
         0.2327),
       bN2=c(
         0.5050,
         0.5578,
         0.6514,
         0.7222,
         0.7825,
         0.8126,
         0.8434,
         0.8693,
         0.8910,
         0.9092,
         0.9222,
         0.9319,
         0.9403,
         0.9477,
         0.9544,
         0.9602,
         0.9653),
       tHe=c(
         1.51,
         1.88,
         3.02,
         4.72,
         6.99,
         10.21,
         14.48,
         20.53,
         29.11,
         41.20,
         55.19,
         70.69,
         90.34,
         115.29,
         147.42,
         188.24,
         240.03),
       aHe=c(
         1.7424,
         1.6189,
         1.3830,
         1.1919,
         1.0458,
         0.9220,
         0.8205,
         0.7305,
         0.6502,
         0.5950,
         0.5545,
         0.5333,
         0.5189,
         0.5181,
         0.5176,
         0.5172,
         0.5119),
       bHe=c(
         0.4245,
         0.4770,
         0.5747,
         0.6527,
         0.7223,
         0.7582,
         0.7957,
         0.8279,
         0.8553,
         0.8757,
         0.8903,
         0.8997,
         0.9073,
         0.9122,
         0.9171,
         0.9217,
         0.9267))

.scuba.models <-
  list(Haldane = hm(
         c(5, 10, 20, 40, 75),
         rep(2 * 0.79, 5),
         rep(2 * 0.79, 5),
         title="Haldane"),
       USN = hm(
         c(5, 10, 20, 40, 80, 120),
         c(104, 88, 72, 56, 52, 51)/32.646,
         c(2.27, 2.01, 1.67, 1.34, 1.26, 1.19),
         title="USN"),
       DSAT = hm(
         c(5, 10, 20, 30, 40, 60, 80, 120),
         c(99.08, 82.68, 66.89, 59.74, 55.73, 51.44, 49.21, 46.93)/32.646,
         title="DSAT"),
       Workman65 = hm(
         c(5, 10, 20, 40, 80, 120, 160, 200, 240),
         c(31.5, 26.7, 21.8, 17.0, 16.4, 15.8, 15.5, 15.5, 15.2)/10,
         c(1.8, 1.6, 1.5, 1.4, 1.3, 1.2, 1.2, 1.1, 1.1),
         title="Workman65"),
       "ZH-L16A"= {
           hm(with(.buehlmannL16A, tN2),
              with(.buehlmannL16A, aN2 + 1/bN2),
              with(.buehlmannL16A, 1/bN2),
              title="Buehlmann ZH-L16A",
              cnames=c("1", "1b", paste(2:16)),
              He=list(HalfT=with(.buehlmannL16A, tHe),
                      M0=with(.buehlmannL16A, aHe + 1/bHe),
                      dM=with(.buehlmannL16A, 1/bHe)),
              mixrule="interpolate")
         })