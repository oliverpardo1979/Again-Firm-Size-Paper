# Independent equivalence test against individual-observation WLS with explicit FE.
.libPaths(c("build/inference_Rlib", "../CJC-Monitor/.Rlib", .libPaths()))
suppressPackageStartupMessages({library(fwildclusterboot);library(fixest)})
set.seed(1741)
d <- expand.grid(person=1:12, year=1:2, depto=1:5, sector=1:8)
d$cell <- interaction(d$year,d$depto,d$sector)
d$sector_depto <- interaction(d$depto,d$sector)
n <- nrow(d)
d$x <- rnorm(n)+d$depto/5
d$z <- rbinom(n,1,.4)
d$w <- exp(rnorm(n)/2)
d$y <- .3*d$x+.2*d$z+rnorm(nlevels(d$cell))[d$cell]+rnorm(n)+rnorm(8)[d$sector]*d$x
full <- lm(y ~ x+z+cell, data=d, weights=w)
X <- fixest::demean(as.matrix(d[c("x","z")]), f=d$cell, weights=d$w)*sqrt(d$w)
Y <- as.numeric(fixest::demean(d$y, f=d$cell, weights=d$w))*sqrt(d$w)
parts <- lapply(split(seq_len(n),d$sector_depto),function(ix) {
  q<-crossprod(X[ix,,drop=FALSE]); v<-crossprod(X[ix,,drop=FALSE],Y[ix])
  e<-eigen(q,symmetric=TRUE)
  xx<-sqrt(e$values)*t(e$vectors)
  yy<-as.numeric(t(e$vectors)%*%v)/sqrt(e$values)
  data.frame(x=xx[,1],z=xx[,2],y=yy,sector=d$sector[ix[1]],depto=d$depto[ix[1]])
})
cdata<-do.call(rbind,parts)
compressed<-lm(y~x+z-1,data=cdata)
stopifnot(max(abs(coef(full)[c("x","z")]-coef(compressed)))<1e-10)
checks<-list()
for (id in list("sector","depto",c("sector","depto"))) {
  answers<-lapply(list(full,compressed), function(fit) {
    set.seed(101);dqrng::dqset.seed(101)
    suppressWarnings(boottest(fit,param=c("x","z"),R=c(1,1),B=9999,clustid=id,
      bootcluster="min",conf_int=FALSE,impose_null=TRUE,type="rademacher",nthreads=2,
      ssc=boot_ssc(adj=FALSE,cluster.adj=TRUE,cluster.df="min")))
  })
  a<-answers[[1]];b<-answers[[2]]
  checks[[length(checks)+1]]<-data.frame(clustering=paste(id,collapse="+"),
    coefficient_error=a$point_estimate-b$point_estimate,t_error=a$t_stat-b$t_stat,
    p_error=a$p_val-b$p_val,bootstrap_t_error=max(abs(a$t_boot-b$t_boot),na.rm=TRUE))
}
result<-do.call(rbind,checks)
print(result)
stopifnot(max(abs(result$coefficient_error))<1e-8,max(abs(result$t_error))<1e-8,
          max(abs(result$p_error))<1e-8)
write.csv(result,"replication/inference_audit_output/compression_bootstrap_validation.csv",row.names=FALSE)
