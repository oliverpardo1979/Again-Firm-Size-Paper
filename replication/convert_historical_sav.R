args <- commandArgs(trailingOnly=TRUE)
root <- normalizePath(args[1],winslash="/")
years <- as.integer(args[-1])
out <- normalizePath(Sys.getenv("GEIH_RAW_DIR"), winslash="/", mustWork=TRUE)
.libPaths(c(file.path(root,"CJC-Monitor/.Rlib"),.libPaths()))
suppressPackageStartupMessages({library(haven);library(dplyr)})
wanted <- c("DIRECTORIO","SECUENCIA_P","ORDEN","MES","FEX_C_2011","FEX_C18","FEX_C","DPTO",
  "OCI","INGLABO","RAMA2D_R4","RAMA2D","P6430","P6920","P3069","P6870","P6800","P7040",
  "P7070","P6020","P3271","P6040","EDAD","P6210","P3042","NIVEL_MAS_ALTO",
  "P550","P6610S1","P6620S1","P6500","P6590S1","P6600S1","P6750")
key <- c("MES","DIRECTORIO","SECUENCIA_P","ORDEN")
for (year in years) {
  manifest <- read.csv(file.path(out,sprintf("sav_manifest_%d.csv",year)))
  result <- list()
  for (month in 1:12) {
    archive <- file.path(out,sprintf("SAV_GEIH_%d_%02d.zip",year,month))
    stopifnot(file.exists(archive))
    members <- manifest[manifest$month==month,]
    occupied <- members$path[members$role=="occ"]
    stopifnot(length(occupied)==2)
    for (name in occupied) {
      domain <- if(grepl("cabecera",name,ignore.case=TRUE)) "cabecera" else "resto"
      characteristics <- members$path[members$domain==domain & members$role=="char"]
      stopifnot(length(characteristics)==1L)
      read_member <- function(member) {
        file <- member
        h <- names(read_sav(file,n_max=0))
        cols <- h[toupper(h)%in%wanted]
        x <- as.data.frame(read_sav(file,col_select=all_of(cols)))
        names(x) <- toupper(names(x))
        x[] <- lapply(x,function(v) as.numeric(zap_labels(v)))
        if (!"MES"%in%names(x)) x$MES <- month
        stopifnot(all(x$MES==month),!anyDuplicated(x[key]))
        x
      }
      o <- read_member(name)
      c <- read_member(characteristics)
      cols <- c(key,setdiff(names(c),names(o)))
      joined <- left_join(o,c[cols],by=key,relationship="one-to-one")
      stopifnot(nrow(joined)==nrow(o),all(do.call(paste,joined[key])%in%do.call(paste,c[key])))
      joined$source_archive <- basename(archive)
      joined$source_module <- name
      result[[length(result)+1L]] <- joined
    }
    cat(year,month,"converted\n")
  }
  raw <- bind_rows(result)
  stopifnot(!anyDuplicated(raw[key]))
  write.csv(raw,file.path(out,sprintf("historical_raw_%d_private.csv",year)),row.names=FALSE,na="")
}
