#!/usr/bin/R --silent -f
# -*- encoding: utf-8 -*-
# wdm.R
#
# (c) 2016 Dominik Wabersich <dominik.wabersich [aet] gmail.com>
# GPL 3.0+ or (cc) by-sa (http://creativecommons.org/licenses/by-sa/3.0/)
#
# created 2016-05-07
# last mod 2016-05-08 00:04 DW
#

wdm <- function(data, yvar=c("q", "resp"), alpha=NULL, tau=NULL, beta=NULL, delta=NULL,
               xvar=NULL, xvar.par=NULL, start=NULL) {
  # save original function call
  cl <- match.call()

  # prepare passed arguments
  verifydata(data)
  if (is.numeric(data) & is.null(xvar)) data <- reshape.wiener(data, yvar=yvar)
  else if (length(yvar)==1) {
    cbind(reshape.wiener(data[,yvar]),data)
    yvar <- c("q", "resp")
  }
  fpar <- c("alpha"=unname(alpha), "tau"=unname(tau), 
    "beta"=unname(beta), "delta"=unname(delta))

  # estimate parameters
  if (!is.null(xvar)) {
    if(length(xvar)==1) {
      if(class(data[,xvar]) == "factor"){
        res <- list()
        res$par <- fpar
        for (l in levels(data[,xvar])) {
          est <- mle(data[data[,xvar]==l,yvar], fpar, start)
          est$par <- est$par[!(names(est$par) %in% names(fpar))]
          names(est$par) <- paste(l,names(est$par), sep=":")
          res$par <- append(res$par, est$par)
          res$counts <- append(res$counts, est$counts)
          res$convergence <- append(res$convergence, est$convergence)
          res$message <- append(res$message, est$message)
          res$hessian <- append(res$hessian, est$hessian)
          res$loglik <- sum(res$loglik, est$loglik)
        }
      }
    }
  }
  else
    res <- mle(data[,yvar], fpar, start)

  # prepare return object
  res$n <- length(data[,1])
  res$npar <- length(res$par)
  res$data <- data
  res$yvar <- yvar
  res$estpar <- c("alpha"=is.null(alpha), "tau"=is.null(tau),
                   "beta"=is.null(beta), "delta"=is.null(delta))
  res$call <- cl
  class(res) <- c("wdm")
  return(res)
}

### mle function
## internal function
mle <- function(data, fpar=NULL, start=NULL) {

  if (is.null(start))
  {
    start <- c(runif(1,1,2),min(data[,1])/3,runif(1,.2,.8),runif(1,-1,1))
  }

  start <- esvec(start, fpar)

  if (length(fpar)==3)
    est <- optim(start,efn,data=data,fpar=fpar, method="Brent",
                 lower=-100, upper=100, hessian=TRUE)
  else
  {
    est <- tryCatch(optim(start,efn,data=data,fpar=fpar,
      method="BFGS",hessian=TRUE, control=list(maxit=2000)), 
      error=optim(start,efn,data=data,fpar=fpar, method="Nelder-Mead", control=list(maxit=2000)))
  }

  par <- eparvec(est$par, fpar)

  res <- list(
    par = par,
    loglik = -est$value,
    counts = est$counts,
    convergence = est$convergence,
    message = est$message,
    hessian = est$hessian
  )

  return(res)
}

## internal function
esvec <- function(x, fpar) {
  if (!is.null(fpar)) {
    if ("alpha" %in% names(fpar))
      x[1] <- NA
    if ("tau" %in% names(fpar)) 
      x[2] <- NA
    if ("beta" %in% names(fpar)) 
      x[3] <- NA
    if ("delta" %in% names(fpar)) 
      x[4] <- NA

    x <- as.numeric(na.omit(x))
  }

  return(x)
}

## internal function
efn <- function(x, data, fpar=NULL) {
  object <- list(data=data)
  par <- numeric(4)

  if (is.null(fpar)) {
    par <- x
  }
  else {
    if("alpha" %in% names(fpar))
      par[1] <- fpar["alpha"]
    else {
      par[1] <- x[1]
      x <- x[-1]
    }
    if("tau" %in% names(fpar)) 
      par[2] <- fpar["tau"]
    else {
      par[2] <- x[1]
      x <- x[-1]
    }
    if("beta" %in% names(fpar)) 
      par[3] <- fpar["beta"]
    else {
      par[3] <- x[1]
      x <- x[-1]
    }
    if("delta" %in% names(fpar)) 
      par[4] <- fpar["delta"]
    else {
      par[4] <- x[1]
      x <- x[-1]
    }
  }
  object$par <- par

  res <- nlogLik.wdm(object)
  return(res)
}

## internal function
eparvec <- function(x, fpar=NULL) {
  res <- numeric(4)
  names(res) <- c("alpha", "tau", "beta", "delta")

  if (!is.null(fpar)) {
    if ("alpha" %in% names(fpar))
      res[1] <- NA
    if ("tau" %in% names(fpar)) 
      res[2] <- NA
    if ("beta" %in% names(fpar)) 
      res[3] <- NA
    if ("delta" %in% names(fpar)) 
      res[4] <- NA
  }

  res[!is.na(res)] <- x
  res[is.na(res)] <- fpar

  return(res)
}

### empirical estimation function (score function) 

CERROR <- 1e-10

estfun <- function(x, ...) {
  UseMethod("estfun")
}

estfun.wdm <- function(object, ...) {
  y <- object$data[,object$yvar]

  alpha <- object$par["alpha"]
  tau <- object$par["tau"]
  beta <- object$par["beta"]
  delta <- object$par["delta"]

  n <- length(y[,1])
  res <- matrix(rep(NA,4*n), n,4)
  colnames(res) <- c("alpha", "tau", "beta", "delta")
  for (i in 1:n) {
    if (y[i,2] == "lower") {
      res[i,1] <- sclalpha(y[i,1], alpha, tau, beta, delta)
      res[i,2] <- scltau(y[i,1], alpha, tau, beta, delta)
      res[i,3] <- sclbeta(y[i,1], alpha, tau, beta, delta)
      res[i,4] <- scldelta(y[i,1], alpha, tau, beta, delta)
    }
    else if (y[i,2] == "upper") {
      res[i,1] <- sclalpha(y[i,1], alpha, tau, 1-beta, -delta)
      res[i,2] <- scltau(y[i,1], alpha, tau, 1-beta, -delta)
      res[i,3] <- sclbeta(y[i,1], alpha, tau, 1-beta, -delta)
      res[i,4] <- scldelta(y[i,1], alpha, tau, 1-beta, -delta)
    }
  }

  return(res)
}

## internal function
pow <- function(x,y) x^y

## internal function
kappaLT <- function(t, err=CERROR) {
  sqrt(2)*sqrt(-log(pi*err*t)/t)/pi
}

## internal function
kappaST <- function(t, err=CERROR) {
  sqrt(2)*sqrt(-t*log(2*sqrt(2)*sqrt(pi)*err*sqrt(t))) + 2
}

fl01LT <- function(t, beta, kappa) {
  res <- 0
  for (k in 1:kappa) {
    res <- res +  ( k*exp(-0.5*pow(pi, 2)*pow(k, 2)*t)*sin(pi*beta*k) )
  }
  res <- pi*res
  return(res)
}

## internal function
fl01ST <- function(t, beta, kappa) {
  res <- 0
  for (k in -kappa:kappa) {
    res <- res + ( (beta + 2*k)*exp(-0.5*pow(beta + 2*k, 2)/t) )
  }
  res <- 0.5*sqrt(2)*res/(sqrt(pi)*sqrt(pow(t, 3)))
  return(res)
}

## internal function
fl01 <- function(t, beta) {
  kst <- kappaST(t)
  klt <- kappaLT(t)
  wlam <- kst - klt
  if(wlam < 0) fl01ST(t, beta, kst)
  else fl01LT(t, beta, klt)
}

## internal function
sclalpha <- function(t, alpha, tau, beta, delta) {
  t <- t-tau

  res <- ( -beta*delta*fl01(t/alpha**2, beta) 
    * exp(-alpha*beta*delta 
    - 0.5*pow(delta, 2)*t)/pow(alpha, 2) 
    - 2*fl01(t/alpha**2, beta)*exp(-alpha*beta*delta 
    - 0.5*pow(delta, 2)*t)/pow(alpha, 3) 
    - 0 # 2*t*exp(-alpha*beta*delta - 0.5*pow(delta, 2)*t) * 0 
    / pow(alpha, 5) )

  return(res)
}

## internal function
scl01tauLT <- function(t, beta, kappa) {
  res <- 0
  for (k in 1:kappa) {
    res <- res + ( 0.5*pow(pi, 2)*pow(k, 3)*exp(-0.5*pow(pi, 2)*pow(k, 2)*t)*sin(pi*beta*k) )
  }
  res <- res * pi
  return(res)
}

## internal function
scl01tauST <- function(t, beta, kappa) {
  res1 <- 0
  res2 <- 0
  for (k in -kappa:kappa) {
    res1 <- ( -2*pow(beta + 2*k, 3)*exp(-pow(beta + 2*k, 2)
      / (2*t))/pow(2*t, 2) )
    res2 <- ( (beta + 2*k)*exp(-pow(beta + 2*k, 2)/(2*t)) )
  }
  res1 <- 0.5*sqrt(2)*res1/(sqrt(pi)*sqrt(pow(t, 3)))
  res2 <- 0.75*sqrt(2)*res2/(sqrt(pi)*(t)*sqrt(pow(t, 3)))
  return(res1+res2)
}

## internal function
scl01tau <- function(t, beta) {
  kst <- kappaST(t)
  klt <- kappaLT(t)
  wlam <- kst - klt
  if(wlam < 0) scl01tauST(t, beta, kst)
  else scl01tauLT(t, beta, klt)
}

## internal function
scltau <- function(t, alpha, tau, beta, delta) {
  t <- t-tau

  res <- ( 0.5*pow(delta, 2)*fl01(t/alpha**2, beta)
    * exp(-alpha*beta*delta - 0.5*pow(delta, 2)*t)/pow(alpha, 2) 
    - exp(-alpha*beta*delta - 0.5*pow(delta, 2)*t)
    * scl01tau((t/alpha**2), beta)
    / pow(alpha, 4) )

  return(res)
}

## internal function
scl01betaLT <- function(t, beta, kappa) {
  res <- 0
  for (k in 1:kappa) {
    res <- res + ( pi*pow(k, 2)*exp(-0.5*pow(pi, 2)*pow(k, 2)*t)*cos(pi*beta*k) )
  }
  res <- res * pi
  return(res)
}

## internal function
scl01betaST <- function(t, beta, kappa) {
  res <- 0
  for (k in -kappa:kappa) {
    res <- res + ( exp(-0.5*pow(beta + 2*k, 2)/t) - 0.5*(beta + 2*k)*(2*beta + 4*k)*exp(-0.5*pow(beta + 2*k, 2)/t)/t )
  }
  res <- 0.5*sqrt(2)*res/(sqrt(pi)*sqrt(pow(t, 3)))
  return(res)
}

## internal function
scl01beta <- function(t, beta) {
  kst <- kappaST(t)
  klt <- kappaLT(t)
  wlam <- kst - klt
  if(wlam < 0) scl01betaST(t, beta, kst)
  else scl01betaLT(t, beta, klt)
}

## internal function
sclbeta <- function(t, alpha, tau, beta, delta) {
  t <- t-tau

  res <- ( -delta*fl01(t/alpha**2, beta)*exp(-alpha*beta*delta 
    - 0.5*pow(delta, 2)*t)/alpha + exp(-alpha*beta*delta 
    - 0.5*pow(delta, 2)*t)
    * scl01beta(t, beta)
    / pow(alpha, 2) )

  return(res)
}

## internal function
scldelta <- function(t, alpha, tau, beta, delta) {
  t <- t-tau

  res <- ( (-alpha*beta - delta*t)*fl01(t/alpha**2, beta)
    * exp(-alpha*beta*delta - 0.5*pow(delta, 2)*t)
    / pow(alpha, 2) )

  return(res)
}