# Purpose        : Fit/predict distribution of soil types (via multinom);
# Maintainer     : Tomislav Hengl (tom.hengl@wur.nl)
# Contributions  : Bas Kempen (bas.kempen@wur.nl); 
# Dev Status     : Pre-Alpha
# Note           : if the regression model is difficult to fit, it might lead to artifacts (see also "mlogit" package);


## fit a multinomial logistic regression and make predictions:
setMethod("spmultinom", signature(formulaString = "formula", observations = "SpatialPointsDataFrame", covariates = "SpatialPixelsDataFrame"), function(formulaString, observations, covariates, class.stats = TRUE, predict.probs = TRUE, ...){

  require(plyr)
  ## generate formula if missing:
  if(missing(formulaString)) {  
    formulaString <- as.formula(paste(names(observations)[1], "~", paste(names(covariates), collapse="+"), sep=""))
  }
  ## check the formula string:
  if(!plyr::is.formula(formulaString)){
      stop("'formulaString' object of class 'formula' required")
  }
  
  ## selected variables:
  tv = all.vars(formulaString)[1]
  sel = names(covariates) %in% all.vars(formulaString)[-1]
  if(all(sel==FALSE)|length(sel)==0){
      stop("None of the covariates in the 'formulaString' matches the column names in the 'covariates' object")
  }

  ## over observations and covariates:
  ov <- over(observations, covariates[sel])  
  ov <- cbind(data.frame(observations[tv]), ov)
    
  require(nnet)
  message("Fitting a multinomial logistic regression model...")
  mout <- nnet::multinom(formulaString, ov, ...)
  cout <- as.factor(paste(predict(mout, newdata=covariates, na.action = na.pass)))

  ## predict probabilities if required:
  if(predict.probs == TRUE){
     probs <- predict(mout, newdata=covariates, type="probs", na.action = na.pass)
     mm <- covariates[1]
     mm@data <- data.frame(probs)
     pm <- covariates[1]
     pm@data[,tv] <- cout
     pm@data[,names(covariates)[1]] <- NULL    
     
     ## kappa statistics:
     require(mda)
     require(psych)
     cout.m <- as.factor(paste(predict(mout, newdata=ov, na.action = na.pass)))
     cf <- confusion(cout.m, as.character(ov[,tv]))
     ## remove missing classes:
     a = attr(cf, "dimnames")[[1]] %in% attr(cf, "dimnames")[[2]] 
     b = attr(cf, "dimnames")[[2]] %in% attr(cf, "dimnames")[[1]]
     c.kappa = cohen.kappa(cf[a,b])
     ac <- sum(diag(cf))/sum(cf)*100
     message(paste("Estimated Cohen Kappa (weighted):", signif(c.kappa$weighted.kappa, 4)))
     message(paste("Map purity:", signif(ac, 3)))
  }
  
  ## remove object class for consistency:
  class(mout) = "list"

  # estimate class centres using the results of multinom:
  if(class.stats == TRUE){
    ca <- aggregate(covariates@data[,sel], by=list(cout), FUN="mean")
    class.c <- as.matrix(ca[-1]); attr(class.c, "dimnames")[[1]] <- ca[,1]
    ca <- aggregate(covariates@data[,sel], by=list(cout), FUN="sd")
    class.sd <- as.matrix(ca[-1]); attr(class.sd, "dimnames")[[1]] <- ca[,1]
    # mask out classes that result in NA:
    for(c in row.names(class.c)){ 
        if(any(is.na(class.c[c,]))|any(is.na(class.sd[c,]))|any(class.sd[c,]==0)){ 
            class.c <- class.c[!(row.names(class.c) %in% c),]; class.sd <- class.sd[!(row.names(class.sd) %in% c),]
        } 
    }
    } else {
      class.c = NULL; class.sd = NULL
    }
    
  # create the output object:
  if(predict.probs == TRUE){
    if(all(!is.na(rowSums(mm@data, na.rm=TRUE)))){
      out <- new("SpatialMemberships", predicted = pm, model = mout, mu = mm, class.c = class.c, class.sd = class.sd, confusion = cf)
    } else {
      stop("Predicted probabilities contain missing values. Consider removing some classes or setting 'predict.probs == FALSE'") 
    }
  } else {  
    out <- list(model=mout, fit=cout, class.c=class.c, class.sd=class.sd)
  }
    
  return(out)
})

# end of script;