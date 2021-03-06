getBARTFitForSubset <- function(object, observedSubset) {
  z <- ifelse(observedSubset, 1, 0)
  object$yhat.obs * z + object$yhat.cf * (1 - z)
}

fitted.bartcFit <-
  function(object,
           value = c("est", "y", "y0", "y1", "indiv.diff", "p.score", "p.weights"),
           sample = c("inferential", "all"),
           ...)
{
  if (!is.character(value) || value[1L] %not_in% eval(formals(fitted.bartcFit)$value))
    stop("value must be in '", paste0(eval(formals(fitted.bartcFit)$value), collapse = "', '"), "'")
  value <- value[1L]
  
  if (!is.character(sample) || sample[1L] %not_in% eval(formals(fitted.bartcFit)$sample))
    stop("sample must be in '", paste0(eval(formals(fitted.bartcFit)$sample), collapse = "', '"), "'")
  sample <- sample[1L]
  
  if (value == "p.weights" && is.null(object$p.score))
    stop("p.score cannot be NULL to extract p.weights")
  
  if (value == "est")
    return(if (!is.null(object$group.by)) sapply(object$samples.est, mean) else mean(object$samples.est))
  
  weights <- object$data.rsp@weights
  if (!is.null(weights)) weights <- weights / sum(weights)
  
  result <-
    switch(value,
           y           = apply(flattenSamples(object$yhat.obs), 1L, mean),
           y0          = apply(flattenSamples(getBARTFitForSubset(object, !object$trt)), 1L, mean),
           y1          = apply(flattenSamples(getBARTFitForSubset(object,  object$trt)), 1L, mean),
           indiv.diff  = apply(flattenSamples((object$yhat.obs - object$yhat.cf) * ifelse(object$trt, 1, -1)), 1L, mean),
           p.score     = object$p.score,
           p.weights   = apply(flattenSamples(with(object, getPWeights(estimand, data.rsp@x[,name.trt], weights, if (!is.null(samples.p.score)) samples.p.score else p.score, fitPars$p.scoreBounds))), 1L, mean))
  
  if (is.null(result)) return(NULL)
  
  subset <- rep_len(TRUE, length(result))
  if (sample == "inferential") {
    if (object$estimand == "att") subset <- object$trt
    else if (object$estimand == "atc") subset <- !object$trt
  }
  
  result[subset]
}

extract.bartcFit <-
  function(object,
           value = c("est", "y", "y0", "y1", "indiv.diff", "p.score", "p.weights"),
           sample = c("inferential", "all"),
           combineChains = TRUE,
           ...)
{
  value <- value[1L]
  if (value %not_in% eval(formals(extract.bartcFit)$value))
    stop("value must be in '", paste0(eval(formals(extract.bartcFit)$value), collapse = "', '"), "'")
  
  sample <- sample[1L]
  if (sample %not_in% eval(formals(extract.bartcFit)$sample))
    stop("sample must be in '", paste0(eval(formals(extract.bartcFit)$sample), collapse = "', '"), "'")
  
  if (value == "p.weights" && is.null(object$p.score))
    stop("p.score cannot be NULL to extract p.weights")
  
  if (value == "est") {
    if (!is.null(object$group.by))
      return(if (combineChains) lapply(object$samples.est, as.vector) else object$samples.est)
    else
      return(if (combineChains) as.vector(object$samples.est) else object$samples.est)
  }
  
  weights <- object$data.rsp@weights
  if (!is.null(weights)) weights <- weights / sum(weights)
  
  result <-
    switch(value,
           y           = object$yhat.obs,
           y0          = getBARTFitForSubset(object, !object$trt),
           y1          = getBARTFitForSubset(object,  object$trt),
           indiv.diff  = (object$yhat.obs - object$yhat.cf) * ifelse(object$trt, 1, -1),
           p.score     = object$samples.p.score,
           p.weights   = with(object, getPWeights(estimand, data.rsp@x[,name.trt], weights, if (!is.null(samples.p.score)) samples.p.score else p.score, fitPars$p.scoreBounds)))
  
  if (is.null(result)) return(NULL)
  
  if (combineChains) result <- flattenSamples(result)
  
  subset <- rep_len(TRUE, dim(result)[1L])
  if (sample == "inferential") {
    if (object$estimand == "att") subset <- object$trt
    else if (object$estimand == "atc") subset <- !object$trt
  }
  
  if (length(dim(result)) > 2L)
    result[subset,,]
  else
    result[subset,]
}

extract <- function(object, ...) UseMethod("extract")


refit.bartcFit <- function(object, newresp = NULL,
                           commonSup.rule = c("none", "sd", "chisq"),
                           commonSup.cut  = c(NA_real_, 1, 0.05), ...)
{
  matchedCall <- match.call()
  if (!is.null(newresp)) warning("'newresp' argument ignored, provided only for generic signature compatibility")
  
  if (!is.null(matchedCall$commonSup.rule)) {
     if (is.null(matchedCall$commonSup.cut))
       commonSup.cut <- eval(formals(refit.bartcFit)$commonSup.cut)[match(commonSup.rule, eval(formals(refit.bartcFit)$commonSup.rule))]
    commonSup.rule <- commonSup.rule[1L]
    commonSup.cut <- commonSup.cut[1L]
  } else {
    commonSup.rule <- "none"
    commonSup.cut  <- NA_real_
  }
  
  object$commonSup.rule <- commonSup.rule
  object$commonSup.cut  <- commonSup.cut
  
  object$commonSup.sub <- with(object, getCommonSupportSubset(sd.obs, sd.cf, commonSup.rule, commonSup.cut, trt, missingRows))
  commonSup.sub <- object$commonSup.sub
  
  
  treatmentRows <- object$trt > 0
  weights <- object$data.rsp@weights
  if (!is.null(weights)) weights <- weights / sum(weights)
  
  if (object$method.rsp == "bart") {
    samples.indiv.diff <- (object$yhat.obs - object$yhat.cf) * ifelse(treatmentRows, 1, -1)
    
    if (is.null(object$group.by)) {
      object$samples.est <- with(object, getBartEstimates(treatmentRows, weights, estimand, samples.indiv.diff, commonSup.sub))
    } else {
      object$samples.est <- lapply(levels(object$group.by), function(level) {
        levelRows <- object$group.by == level
        if (!is.null(weights)) weights <- weights[levelRows]
        
        with(object, getBartEstimates(treatmentRows[levelRows], weights, estimand,
                                      addDimsToSubset(samples.indiv.diff[levelRows, drop = FALSE]), commonSup.sub[levelRows]))
      })
      names(object$samples.est) <- levels(object$group.by)
    }
  } else if (object$method.rsp == "p.weight") {
    yhat.1 <- with(object, yhat.obs * trt       + yhat.cf * (1 - trt))
    yhat.0 <- with(object, yhat.obs * (1 - trt) + yhat.cf * trt)
    p.score <- object$p.score
    
    if (is.null(object$group.by)) {
      if (any(object$commonSup.sub != TRUE)) {
        addDimsToSubset(yhat.0 <- yhat.0[commonSup.sub, drop = FALSE])
        addDimsToSubset(yhat.1 <- yhat.1[commonSup.sub, drop = FALSE])
           
        p.score <- addDimsToSubset(p.score[commonSup.sub, drop = FALSE])
      
        if (!is.null(weights)) weights <- weights[commonSup.sub]
      }
      
      object$samples.est <- with(object, getPWeightEstimates(data.rsp@y[commonSup.sub], trt[commonSup.sub], weights, estimand, yhat.0, yhat.1, p.score, fitPars$yBounds, fitPars$p.scoreBounds))
    } else {
      object$samples.est <- lapply(levels(object$group.by), function(level) {
        levelRows <- object$group.by == level & object$commonSup.sub
        
        addDimsToSubset(yhat.0 <- yhat.0[levelRows, drop = FALSE])
        addDimsToSubset(yhat.1 <- yhat.1[levelRows, drop = FALSE])
        addDimsToSubset(p.score <- p.score[levelRows, drop = FALSE])
      
        if (!is.null(weights)) weights <- weights[levelRows]
      
        with(object, getPWeightEstimates(data.rsp@y[levelRows], trt[levelRows], weights, estimand, yhat.0, yhat.1, p.score,
                                         fitPars$yBounds, fitPars$p.scoreBounds))
      })
      names(object$samples.est) <- levels(object$group.by)
    }
  } else if (object$method.rsp == "tmle") {
    yhat.1 <- with(object, yhat.obs * trt       + yhat.cf * (1 - trt))
    yhat.0 <- with(object, yhat.obs * (1 - trt) + yhat.cf * trt)
    p.score <- object$p.score
    
    if (is.null(object$group.by)) {
      if (any(object$commonSup.sub != TRUE)) {
        addDimsToSubset(yhat.0 <- yhat.0[commonSup.sub, drop = FALSE])
        addDimsToSubset(yhat.1 <- yhat.1[commonSup.sub, drop = FALSE])
           
        p.score <- addDimsToSubset(p.score[commonSup.sub, drop = FALSE])
      
        if (!is.null(weights)) weights <- weights[commonSup.sub]
      }
      
      object$samples.est <- with(object, getTMLEEstimates(data.rsp@y[commonSup.sub], trt[commonSup.sub], weights, estimand, yhat.0, yhat.1, p.score, fitPars$yBounds, fitPars$p.scoreBounds, fitPars$depsilon, fitPars))
    } else {
      object$samples.est <- lapply(levels(object$group.by), function(level) {
        levelRows <- object$group.by == level & object$commonSup.sub
        
        addDimsToSubset(yhat.0 <- yhat.0[levelRows, drop = FALSE])
        addDimsToSubset(yhat.1 <- yhat.1[levelRows, drop = FALSE])
        addDimsToSubset(p.score <- p.score[levelRows, drop = FALSE])
      
        if (!is.null(weights)) weights <- weights[levelRows]
      
        with(object, getTMLEEstimates(data.rsp@y[levelRows], trt[levelRows], weights, estimand, yhat.0, yhat.1, p.score,
                                      fitPars$yBounds, fitPars$p.scoreBounds, fitPars$depsilon, fitPars$maxIter))
      })
      names(object$samples.est) <- levels(object$group.by)
    }

  }
  
  invisible(object)
}

refit <- function(object, newresp, ...) UseMethod("refit")

