#' Verify the saved oracle against original observations, signs and unit variances.
if (!exists("project_root")) source("R/bootstrap.R")

#' Reconstruct one study's oracle p-values and adjustment from the stated formula.
#' @param row Scenario metadata.
#' @param setting Original observations and effects.
#' @param target One saved study result.
#' @param study Study index.
audit_oracle_study <- function(row, setting, target, study) {
  pair <- setting$observations[[study]]
  ids <- colnames(pair$exposed)
  d <- do.call(rbind, lapply(target$directional_results, as.data.frame))
  stopifnot(nrow(d)==length(ids),!anyDuplicated(d$measurement_id),
    setequal(d$measurement_id,ids),nrow(pair$exposed)==nrow(pair$unexposed))
  d <- d[match(ids,d$measurement_id),]
  direction <- ifelse(setting$effects[study,]<0,-1L,1L)
  se <- sqrt(1/nrow(pair$exposed)+1/nrow(pair$unexposed))
  z <- (colMeans(pair$exposed)-colMeans(pair$unexposed))/se
  expected <- pnorm(direction*z,lower.tail=FALSE)
  adjusted <- p.adjust(expected,if(row$criterion=="FWER")"holm" else "BH")
  stopifnot(identical(as.integer(d$direction),as.integer(direction)),
    isTRUE(all.equal(d$p_value,expected,tolerance=1e-13,check.attributes=FALSE)),
    isTRUE(all.equal(d$adjusted_p_value,adjusted,tolerance=1e-13,check.attributes=FALSE)),
    identical(d$reject,unname(adjusted<=.05/3)))
  data.frame(id=row$id,regime=row$regime,criterion=row$criterion,m=row$m,c=row$c,study=study,
    tested_outcomes=nrow(d),true_nulls_tested=sum(setting$effects[study,]==0),
    max_raw_p_difference=max(abs(d$p_value-expected)),
    max_adjusted_p_difference=max(abs(d$adjusted_p_value-adjusted)),verified=TRUE)
}

#' Audit complete oracle scenarios without rerunning agents or changing saved outputs.
#' @param run_dir Sealed completed live run.
#' @param output_dir Destination for oracle-verification.csv.
audit_oracle <- function(run_dir, output_dir) {
  stopifnot(doc_package_valid(run_dir))
  summary <- read_csv(file.path(run_dir,"summary.csv"))
  summary <- summary[summary$method=="oracle_z_secondary" & summary$complete==1,]
  grid <- read_csv(file.path(run_dir,"scenarios.csv"))
  rows <- lapply(seq_len(nrow(summary)),function(i) {
    row <- summary[i,]
    data_id <- grid$data_id[match(row$id,grid$id)]
    setting <- readRDS(file.path(run_dir,"private",paste0(data_id,".rds")))
    targets <- jsonlite::read_json(file.path(run_dir,"scenarios",row$id,
      "oracle_z_secondary/target-results.json"))
    do.call(rbind,lapply(1:3,function(j) audit_oracle_study(row,setting,targets[[j]],j)))
  })
  table <- do.call(rbind,rows)
  write_csv(table,file.path(output_dir,"oracle-verification.csv"))
  cat("Verified exact oracle tests, signs and corrections in",nrow(table),"study evaluations.\n")
  invisible(table)
}

if (sys.nframe()==0L) {
  args <- commandArgs(trailingOnly=TRUE)
  audit_oracle(normalizePath(cli_value(args,"--run-dir"),mustWork=TRUE),
    ensure_dir(cli_value(args,"--output")))
}
