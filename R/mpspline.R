# Purpose        : Fits a mass-preserving (equal area) spline to soil profile data;
# Maintainer     : Tomislav Hengl (tom.hengl@wur.nl); 
# Contributions  : B. Malone (brendan.malone@sydney.edu.au); T.F.A. Bishop (t.bishop@usyd.edu.au);
# Status         : experimental
# Note           : Mass-preserving spline explained in detail in [http://dx.doi.org/10.1016/S0016-7061(99)00003-8];
# Note 2         : This code needs to be cleaned up;


# Spline fitting for horizon data (created by Brandon Malone; adjusted by T. Hengl)
setMethod('mpspline', signature(obj = "SoilProfileCollection"), 
  function(obj, var.name, mxd = 200, lam = 0.1, d = t(c(0,5,15,30,60,100,200)), vlow = 0, vhigh = 1000){

  depthcols = obj@depthcols
  idcol = obj@idcol
  ## convert to a data frame:
  obj@horizons = obj@horizons[,c(idcol, depthcols, var.name)]
  ## TH: remove all horizons with negative depth!
  obj@horizons <- obj@horizons[!obj@horizons[,depthcols[1]]<0 & !obj@horizons[,depthcols[2]]<0,]
  objd <- .as.data.frame.SoilProfileCollection(x=obj)
  # organize the data:
  ndata <- nrow(objd)
  # Matrix in which the averaged values of the spline are fitted. The depths are specified in the (d) object:
  m_fyfit <- matrix(NA, ncol=length(c(0:mxd)), nrow=ndata)
  # Matrix in which the sum of square errors of each lamda iteration for the working profile are stored
  yave <- matrix(NA, ncol=length(d), nrow=ndata)
  # Matrix in which the sum of square errors for eac h lambda iteration for each profile are stored
  sse <- matrix(NA, ncol=length(lam), nrow=1)
  sset <- matrix(NA, ncol=length(lam), nrow=ndata)
  nl <- length(lam)  # Length of the lam matrix
  svar.lst <- grep(names(objd), pattern=glob2rx(paste(var.name, "_*", sep="")))
  s <- 0.05*sd(unlist(unclass(objd[,svar.lst])), na.rm=TRUE)  # 5% of the standard deviation of the target attribute 
  s2 <- s*s   # overall variance of soil attribute
  # reformat table (profile no, upper boundary, lower boundary, vars):
  upperb.lst <- grep(names(objd), pattern=glob2rx(paste(depthcols[1], "_*",sep="")))
  lowerb.lst <- grep(names(objd), pattern=glob2rx(paste(depthcols[2], "_*",sep="")))
  objd_m <- objd[,c(grep(names(objd), pattern=idcol), upperb.lst, lowerb.lst, svar.lst)]
  np <- length(svar.lst) # max number of horizons
  # Matrix in which the observed depth will be entered:
  obdep <- matrix(NA, ncol=np, nrow=ndata)
  # Matrix in which the averaged values of spline-fitted values at observed depths are entered:
  dave <- matrix(NA, ncol=np, nrow=ndata)

  if(np<2|is.na(np)){
      stop("Submitted soil profiles do not contain enough horizons (>2) for spline fitting.")
  }
  else { 
    svar.lst <- grep(names(objd_m), pattern=glob2rx(paste(var.name, "_*",sep="")))
    upperb.lst <- grep(names(objd_m), pattern=glob2rx(paste(depthcols[1], "_*",sep="")))
    lowerb.lst <- grep(names(objd_m), pattern=glob2rx(paste(depthcols[2], "_*",sep="")))
 
    ## if missing, fill in the depth of first horizon as "0"
    missing.A <- is.na(objd_m[,which(names(objd_m)==paste(depthcols[1], "_A",sep=""))])
    objd_m[missing.A,which(names(objd_m)==paste(depthcols[1], "_A",sep=""))] <- 0
  
    ## mask out all profiles with <2 horizons and with at least one of the first 3 horizons defined:
    sel <- !(is.na(objd_m[,which(names(objd_m)==paste(var.name, "_A",sep=""))]) & is.na(objd_m[,which(names(objd_m)==paste(var.name, "_B",sep=""))])) & 
              rowSums(!is.na(objd_m[,svar.lst]))>1 &
              rowSums(!is.na(objd_m[,upperb.lst]))>1 &
              rowSums(!is.na(objd_m[,lowerb.lst]))>1
              
    if(sum(sel)==0){
      stop("Submitted soil profiles do not contain enough horizons (>2) for spline fitting")
    }
  
    ## detect lowest horizon no:
    uw.hor <- rowSums(!is.na(objd_m[,upperb.lst]))
    lw.hor <- as.vector(which(rowSums(!is.na(objd_m[,lowerb.lst])) < rowSums(!is.na(objd_m[,upperb.lst]))&rowSums(!is.na(objd_m[,upperb.lst]))>1))  # profiles with un-even number of lower/upper depths
    message("Adding missing lower depths")
  
    ## add missing lower depth where necessary:
    for(lw in lw.hor){
      uwx <- objd_m[lw,upperb.lst[uw.hor[lw]]]
      if(!is.na(uwx)&sel[lw]==TRUE){
      if(uwx<150) { objd_m[lw,lowerb.lst[uw.hor[lw]]] <- 150 }
      else { 
        objd_m[lw,lowerb.lst[uw.hor[lw]]] <- 200 
      }
    } 
    }
    message("Fitting mass preserving splines per profile...")

    ## Fit splines profile by profile:
    pb <- txtProgressBar(min=0, max=length(sel), style=3)
    for(st in as.vector(which(sel))) {
      subs <- matrix(unlist(c(1:np, as.vector(objd_m[st, upperb.lst]), as.vector(objd_m[st, lowerb.lst]), as.vector(objd_m[st, svar.lst]))), ncol=4)
      d.ho <- rowMeans(data.frame(x=subs[,2], y=c(NA, subs[1:(nrow(subs)-1),3])), na.rm=TRUE) 
      # mask out missing values
      subs <- subs[!is.na(subs[,2])&!is.na(subs[,3])&!is.na(subs[,4]),]

      # manipulate the profile data to the required form
      ir <- c(1:length(subs[,1]))
      ir <- as.matrix(t(ir))
      u <- subs[ir,2]
      u <- as.matrix(t(u))   # upper 
      v <- subs[ir,3]
      v <- as.matrix(t(v))   # lower
      y <- subs[ir,4]
      y <- as.matrix(t(y))   # concentration 
      n <- length(y)       # number of observations in the profile
        
        ## routine for handling profiles with one observation
        if (n == 1){ 
          xfit <- as.matrix(t(c(0:mxd)))
          nj <- max(v)+1
          if (nj > mxd)
          {nj <- mxd+1}
          yfit <- xfit 
          yfit[,1:nj]<- y   # values extrapolated onto yfit
          if (nj <= mxd)
                  {yfit[,(nj+1):(mxd+1)]=NA}
                  m_fyfit[st,] <- yfit
                  nd <- length(d)-1  # number of depth intervals
              dl <- d+1     #  increase d by 1
              
              for (cj in 1:nd) {
                                xd1<- dl[cj]
                                xd2<- dl[cj+1]     
                                if (nj>xd1 & nj<xd2)
                                {xd2<- nj
                                yave[st,cj]<- mean(yfit[,xd1:xd2])}
                                else
                                {yave[st,cj]<- mean(yfit[,xd1:xd2])}   # average of the yfit at the specified depth intervals
                                yave[st,cj+1]<- max(v)
          }
        }
        # End of single observation profile routine
        
        # Start of routine for fitting spline to profiles with multiple observations         
        
        else  {    
        np1 <- n+1  # number of interval boundaries
        nm1 <- n-1
        delta <- v-u  # depths of each layer
        del <- c(u[2:n],u[n])-v   # del is (u1-v0,u2-v1, ...)
  
        # create the (n-1)x(n-1) matrix r; first create r with 1's on the diagonal and upper diagonal, and 0's elsewhere
        r <- matrix(0,ncol=nm1,nrow=nm1)
        for(dig in 1:nm1){
          r[dig,dig]<-1
        }
        for(udig in 1:nm1-1){
           r[udig,udig+1]<-1
        }
  
        #then create a diagonal matrix d2 of differences to premultiply the current r
        d2 <- matrix(0, ncol=nm1, nrow=nm1)
        diag(d2) <- delta[2:n]  # delta = depth of each layer
  
        # then premultiply and add the transpose; this gives half of r
        r <- d2 %*% r
        r <- r + t(r)
  
        # then create a new diagonal matrix for differences to add to the diagonal
        d1 <- matrix(0, ncol=nm1, nrow=nm1)
        diag(d1) <- delta[1:nm1]  # delta = depth of each layer
  
        d3 <- matrix(0, ncol=nm1, nrow=nm1)
        diag(d3) <- del[1:nm1]  # del =  differences
  
        r <- r+2*d1 + 6*d3
  
        # create the (n-1)xn matrix q
        q <- matrix(0,ncol=n,nrow=n)
        for (dig in 1:n){
           q[dig,dig]<- -1 
        }
        for (udig in 1:n-1){
           q[udig,udig+1]<-1 
        }
        q <- q[1:nm1,1:n]
        dim.mat <- matrix(q[],ncol=length(1:n),nrow=length(1:nm1))
  
        # inverse of r
        rinv <- try(solve(r), TRUE)
        
        # Note: in same cases this will fail due to singular matrix problems, hence you need to check if the object is meaningfull:
        if(is.matrix(rinv)){
        # identity matrix i
        ind <- diag(n)
  
        # create the matrix coefficent z
  
        pr.mat <- matrix(0,ncol=length(1:nm1),nrow=length(1:n))
        pr.mat[] <- 6*n*lam
        fdub <- pr.mat*t(dim.mat)%*%rinv
        z <- fdub%*%dim.mat+ind
  
        # solve for the fitted layer means
        sbar <- solve(z,t(y))
  
        # calculate the fitted value at the knots
        b <- 6*rinv%*%dim.mat%*% sbar
        b0 <- rbind(0,b) # add a row to top = 0
        b1 <- rbind(b,0) # add a row to bottom = 0
        gamma <- (b1-b0) / t(2*delta)
        alfa <- sbar-b0 * t(delta) / 2-gamma * t(delta)^2/3
  
  
        # fit the spline 
        xfit <- as.matrix(t(c(0:mxd))) # spline will be interpolated onto these depths (1cm res)
        nj <- max(v)+1
        if (nj > mxd)
        {nj <- mxd+1}
        yfit <- xfit
          for (k in 1:nj){
          xd <-xfit[k]
            for (its in 1:n) {
            if(its < n)
              {tf2=as.numeric(xd>v[its] & xd<u[its+1])} else {tf2 <- 0}
            if(xd>=u[its] & xd<=v[its]){
                p=alfa[its]+b0[its]*(xd-u[its])+gamma[its]*(xd-u[its])^2} 
                else if(tf2){
                   phi=alfa[its+1]-b1[its]*(u[its+1]-v[its])
                   p=phi+b1[its]*(xd-v[its])
                }
            }
            yfit[k]=p }
            
            if(nj <= mxd) { yfit[,nj:mxd+1] = NA }
            m_fyfit[st,] <- yfit
  
            # CALCULATION OF THE ERROR BETWEEN OBSERVED AND FITTED VALUES
            # calculate Wahba's estimate of the residual variance sigma^2
            ssq <- sum((t(y)-sbar)^2)
            g <- solve(z)
            ei <- eigen(g)
            ei <- ei$values
            df <- n-sum(ei)
            sig2w <- ssq/df
            # calculate the Carter and Eagleson estimate of residual variance
            dfc <- n-2*sum(ei)+sum(ei^2)
            sig2c <- ssq/dfc
            # calculate the estimate of the true mean squared error
            tmse <- ssq/n-2*s2*df/n+s2
            sset[st] <- tmse
          
            # Averages of the spline at specified depths
            nd <- length(d)-1  # number of depth intervals
            dl <- d+1     #  increase d by 1
            for (cj in 1:nd) {
                              xd1<- dl[cj]
                              xd2<- dl[cj+1]     
                              if (nj>xd1 & nj<xd2)
                              {xd2<- nj
                              yave[st,cj] <- mean(yfit[,xd1:xd2])}
                              else
                              {yave[st,cj] <- mean(yfit[,xd1:xd2])}   # average of the spline at the specified depth intervals
                              yave[st,cj+1] <- max(v)
  
                }         
          
            # Spline estimates at observed depths
            dl <- t(d.ho[!is.na(d.ho)])+1
            obdep[st,] <- as.vector(d.ho)
            nd <- length(dl) # number of depth intervals
            for (cj in 1:nd) {
              if(dl[cj]<202) {
                dave[st,cj] <- yfit[,dl[cj]]
              }
            }         

     }
     }
    
    setTxtProgressBar(pb, st)          
  }
  close(pb)
  cat(st, "\r")
  flush.console()

  yave <- ifelse(yave<vlow, vlow, yave) 
  dave <- ifelse(dave<vlow, vlow, dave) 
  dave <- ifelse(dave>vhigh, NA, dave)
  retval <- list(idcol=objd_m[,1], depths=obdep, var.fitted=dave, var.std=yave, var.1cm=t(m_fyfit))
  
  return(retval)
  }
  
})

# end of script;