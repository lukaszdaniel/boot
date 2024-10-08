# part of R package boot
# copyright (C) 1997-2001 Angelo J. Canty
# corrections (C) 1997-2011 B. D. Ripley
#
# Unlimited distribution is permitted

# empirical log likelihood ---------------------------------------------------------


EL.profile <- function(y, tmin = min(y) + 0.1, tmax = max(y) - 0.1, n.t = 25,
                       u = function(y, t) y - t )
{
#  Calculate the profile empirical log likelihood function
    EL.loglik <- function(lambda) {
        temp <- 1 + lambda * EL.stuff$u
        if (any(temp <= 0)) NA else - sum(log(1 + lambda * EL.stuff$u))
    }
    EL.paras <- matrix(NA, n.t, 3)
    lam <- 0.001
    for(it in 0:(n.t-1)) {
        t <- tmin + ((tmax - tmin) * it)/(n.t-1)
        EL.stuff <- list(u = u(y, t))
        EL.out <- nlm(EL.loglik, lam)
        i <- 1
        while (EL.out$code > 2 && (i < 20)) {
            i <- i+1
            lam <- lam/5
            EL.out <- nlm(EL.loglik, lam)
        }
        EL.paras[1 + it,  ] <- c(t, EL.loglik(EL.out$x), EL.out$x)
        lam <- EL.out$x
    }
    EL.paras[,2] <- EL.paras[,2]-max(EL.paras[,2])
    EL.paras
}


EEF.profile <- function(y, tmin = min(y)+0.1, tmax = max(y) - 0.1, n.t = 25,
                        u = function(y,t) y - t)
{
    EEF.paras <- matrix( NA, n.t+1, 4)
    for (it in 0:n.t) {
        t <- tmin + (tmax-tmin)*it/n.t
        psi <- as.vector(u( y, t ))
        fit <- glm(zero ~ psi -1,poisson(log))
        f <- fitted(fit)
        EEF.paras[1+it,] <- c(t, sum(log(f)-log(sum(f))), sum(f-1),
                              coefficients(fit))
    }
    EEF.paras[,2] <- EEF.paras[,2] - max(EEF.paras[,2])
    EEF.paras[,3] <- EEF.paras[,3] - max(EEF.paras[,3])
    EEF.paras
}


lik.CI <- function(like, lim ) {
#
#  Calculate an interval based on the likelihood of a parameter.
#  The likelihood is input as a matrix of theta values and the
#  likelihood at those points.  Also a limit is input.  Values of
#  theta for which the likelihood is over the limit are then used
#  to estimate the end-points.
#
#  Not that the estimate only works for unimodal likelihoods.
#
	L <- like[, 2]
	theta <- like[, 1]
	n <- length(L)
	i <- min(c(1L:n)[L > lim])
	if (is.na(i)) stop(gettextf("likelihood never exceeds %f", lim),
                           domain = "R-boot")
	j <- max(c(1L:n)[L > lim])
	if (i ==j )
            stop(gettextf("likelihood exceeds %f at only one point", lim),
                 domain = "R-boot")
	if (i == 1) bot <- -Inf
	else {
            i <- i + c(-1, 0, 1)
            x <- theta[i]
            y <- L[i]-lim
            co <- coefficients(lm(y ~ x + x^2))
            bot <- (-co[2L] + sqrt( co[2L]^2 - 4*co[1L]*co[3L]))/(2*co[3L])
	}
	if (j == n) top <- Inf
	else {
            j <- j + c(-1, 0, 1)
            x <- theta[j]
            y <- L[j] - lim
            co <- coefficients(lm(y ~ x + x^2))
            top <- (-co[2L] - sqrt(co[2L]^2 - 4*co[1L]*co[3L]))/(2*co[3L])
	}
	out <- c(bot, top)
	names(out) <- NULL
	out
}


nested.corr <- function(data,w,t0,M) {
    ## Statistic for the example nested bootstrap on the cd4 data.
    ## Indexing a bare matrix is much faster
    data <- unname(as.matrix(data))
    corr.fun <- function(d, w = rep(1, nrow(d))/nrow(d)) {
        x <- d[, 1L]; y <- d[, 2L]
        w <- w/sum(w)
        n <- nrow(d)
        m1 <- sum(x * w)
        m2 <- sum(y * w)
        v1 <- sum(x^2 * w) - m1^2
        v2 <- sum(y^2 * w) - m2^2
        rho <- (sum(x * y * w) - m1 * m2)/sqrt(v1 * v2)
        i <- rep(1L:n, round(n * w))
        us <- (x[i] - m1)/sqrt(v1)
        xs <- (y[i] - m2)/sqrt(v2)
        L <- us * xs - 0.5 * rho * (us^2 + xs^2)
        c(rho, sum(L^2)/nrow(d)^2)
    }
    n <- nrow(data)
    i <- rep(1L:n,round(n*w))
    t <- corr.fun(data,w)
    z <- (t[1L]-t0)/sqrt(t[2L])
    nested.boot <- boot(data[i,],corr.fun,R=M,stype="w")
    z.nested <- (nested.boot$t[,1L]-t[1L])/sqrt(nested.boot$t[,2L])
    c(z,sum(z.nested<z)/(M+1))
}


# part of R package boot
# copyright (C) 1997-2001 Angelo J. Canty
# corrections (C) 1997-2011 B. D. Ripley
# corrections (C) 2023 A. R. Brazzale
#
# Unlimited distribution is permitted

# importance sampling --------------------------------------------------------------


imp.weights <- function(boot.out, def = TRUE, q = NULL)
{
  #
  # Takes boot.out object and calculates importance weights
  # for each element of boot.out$t, as if sampling from multinomial
  # distribution with probabilities q.
  # If q is NULL the weights are calculated as if
  # sampling from a distribution with equal probabilities.
  # If def=T calculates weights using defensive mixture
  # distribution, if F uses weights knowing from which element of
  # the mixture they come.
  #
  R <- boot.out$R
  if (length(R) == 1L)
    def <- FALSE
  f <- boot.array(boot.out)
  n <- ncol(f)
  strata <- tapply(boot.out$strata,as.numeric(boot.out$strata))
  #    ns <- table(strata)
  if (is.null(q))  q <- rep(1,ncol(f))
  if (any(q == 0)) stop("0 elements not allowed in 'q'")
  p <- boot.out$weights
  if ((length(R) == 1L) && all(abs(p - q)/p < 1e-10))
    return(rep(1, R))
  np <- length(R)
  q <- normalize(q, strata)
  lw.q <- as.vector(f %*% log(q))
  if (!isMatrix(p))
    p <- as.matrix(t(p))
  p <- t(apply(p, 1L, normalize, strata))
  lw.p <- matrix(NA, sum(R), np)
  for(i in 1L:np) {
    zz <- seq_len(n)[p[i,  ] > 0]
    lw.p[, i] <- f[, zz] %*% log(p[i, zz])
  }
  if (def)
    w <- 1/(exp(lw.p - lw.q) %*% R/sum(R))
  else {
    i <- cbind(seq_len(sum(R)), rep(seq_along(R), R))
    w <- exp(lw.q - lw.p[i])
  }
  as.vector(w)
}


imp.moments <- function(boot.out=NULL, index=1, t=boot.out$t[,index],
                        w=NULL, def=TRUE, q=NULL )
{
  # Calculates raw, ratio, and regression estimates of mean and
  # variance of t using importance sampling weights in w.
  if (missing(t) && is.null(boot.out$t))
    stop("bootstrap replicates must be supplied")
  if (is.null(w))
    if (!is.null(boot.out))
      w <- imp.weights(boot.out, def, q)
  else	stop("either 'boot.out' or 'w' must be specified.")
  if ((length(index) > 1L) && missing(t)) {
    warning("only first element of 'index' used")
    t <- boot.out$t[,index[1L]]
  }
  fins <- seq_along(t)[is.finite(t)]
  t <- t[fins]
  w <- w[fins]
  if (!const(w)) {
    y <- t*w
    m.raw <- mean( y )
    m.rat <- sum( y )/sum( w )
    t.lm <- lm( y~w )
    m.reg <- mean( y ) - coefficients(t.lm)[2L]*(mean(w)-1)
    v.raw <- mean(w*(t-m.raw)^2)
    v.rat <- sum(w/sum(w)*(t-m.rat)^2)
    x <- w*(t-m.reg)^2
    t.lm2 <- lm( x~w )
    v.reg <- mean( x ) - coefficients(t.lm2)[2L]*(mean(w)-1)
  }
  else {	m.raw <- m.rat <- m.reg <- mean(t)
  v.raw <- v.rat <- v.reg <- var(t)
  }
  list( raw=c(m.raw,v.raw), rat = c(m.rat,v.rat),
        reg = as.vector(c(m.reg,v.reg)))
}


imp.reg <- function(w)
{
  #  This function takes a vector of importance sampling weights and
  #  returns the regression importance sampling weights.  The function
  #  is called by imp.prob and imp.quantiles to enable those functions
  #  to find regression estimates of tail probabilities and quantiles.
  R <- length(w)
  if (!const(w)) {
# ARB    R <- length(w)
    mw <- mean(w)
    s2w <- (R-1)/R*var(w)
    b <- (1-mw)/s2w
# ARB    w <- w*(1+b*(w-mw))/R
    w <- w*(1+b*(w-mw))
  }
# ARB  cumsum(w)/sum(w)
  #  ARB Returned weights sum to R.
  w   
}


imp.quantile <- function(boot.out=NULL, alpha=NULL, index=1,
                         t=boot.out$t[,index], w=NULL, def=TRUE, q=NULL )
{
  # Calculates raw, ratio, and regression estimates of alpha quantiles
  #  of t using importance sampling weights in w.
  if (missing(t) && is.null(boot.out$t))
    stop("bootstrap replicates must be supplied")
  if (is.null(alpha)) alpha <- c(0.01,0.025,0.05,0.95,0.975,0.99)
  if (is.null(w))
    if (!is.null(boot.out))
      w <- imp.weights(boot.out, def, q)
  else	stop("either 'boot.out' or 'w' must be specified.")
  if ((length(index) > 1L) && missing(t)){
    warning("only first element of 'index' used")
    t <- boot.out$t[,index[1L]]
  }
  fins <- seq_along(t)[is.finite(t)]
  t <- t[fins]
  w <- w[fins]
  o <- order(t)
  t <- t[o]  
  w <- w[o]
  cum <- cumsum(w) 
  cum.rat <- cum/mean(w)
  cum.reg <- cumsum(imp.reg(w))
  o <- rev(o)
  w.m <- w[o]
  t.m <- -rev(t)  
  cum.m <- cumsum(w.m)
  R <- length(w)
  raw <- rat <- reg <- rep(NA,length(alpha))
  for (i in seq_along(alpha)) {
    if (alpha[i]<=0.5) 
      raw[i] <-  max(t[cum<=(R+1)*alpha[i]])
    else 
      raw[i] <- -max(t.m[cum.m<=(R+1)*(1-alpha[i])])
    rat[i] <- max(t[cum.rat <= (R+1)*alpha[i]])
    reg[i] <- max(t[cum.reg <= (R+1)*alpha[i]])
  }
  list(alpha=alpha, raw=raw, rat=rat, reg=reg)
}


imp.prob <- function(boot.out=NULL, index=1, t0=boot.out$t0[index],
                     t=boot.out$t[,index], w=NULL,  def=TRUE, q=NULL)
{
  # Calculates raw, ratio, and regression estimates of tail probability
  #  pr( t <= t0 ) using importance sampling weights in w.
  is.missing <- function(x) length(x) == 0L || is.na(x)

  if (missing(t) && is.null(boot.out$t))
    stop("bootstrap replicates must be supplied")
  if (is.null(w))
    if (!is.null(boot.out))
      w <- imp.weights(boot.out, def, q)
  else	stop("either 'boot.out' or 'w' must be specified.")
  if ((length(index) > 1L) && (missing(t) || missing(t0))) {
    warning("only first element of 'index' used")
    index <- index[1L]
    if (is.missing(t)) t <- boot.out$t[,index]
    if (is.missing(t0)) t0 <- boot.out$t0[index]
  }
  fins <- seq_along(t)[is.finite(t)]
  t <- t[fins]
  w <- w[fins]
  o <- order(t)
  t <- t[o]
  w <- w[o]
  raw <- rat <- reg <- rep(NA,length(t0))
  cum <- cumsum(w)/sum(w)
# ARB  cum.r <- imp.reg(w)
  w.reg <- imp.reg(w)
  cum.r <- cumsum(w.reg)/sum(w.reg)
  for (i in seq_along(t0)) {
    raw[i] <- sum(w[t<=t0[i]])/length(w)
    if(raw[i] > 1L)  raw[i] = 1
# ARB    rat[i] <- max(cum[t<=t0[i]])
# ARB    reg[i] <- max(cum.r[t<=t0[i]])
    if(any(t<=t0[i]))
    {
      rat[i] <- max(cum[t<=t0[i]])
      reg[i] <- max(cum.r[t<=t0[i]])
    }
    else  
      rat[i] = reg[i] = 0
  }
  list(t0=t0, raw=raw, rat=rat, reg=reg )
}
