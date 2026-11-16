#' Independently verify exported document-v2 results and archive integrity.
source("R/bootstrap.R")
source("R/document_pipeline.R")
args <- commandArgs(trailingOnly = TRUE)
run_dir <- normalizePath(args[1], mustWork = TRUE)
record <- read_json(file.path(run_dir,"run.json"))
stopifnot(record$protocol == "document-v2")
index <- read_csv(file.path(run_dir,"SHA256.csv"))
stopifnot(all(vapply(seq_len(nrow(index)),function(i)
  file_hash(safe_file(file.path(run_dir,index$path[i]),run_dir)) == index$sha256[i],logical(1))))
usage <- read_csv(file.path(run_dir,"usage.csv"))
if (isTRUE(record$offline)) stopifnot(sum(usage$physical_api_attempts)==0)
summary <- read_csv(file.path(run_dir,"summary.csv"))
stopifnot(all(summary$complete %in% c(0,1)))
for (i in seq_len(nrow(summary))) {
  row <- summary[i,]
  directory <- file.path(run_dir,"scenarios",row$id,row$method)
  if (row$complete == 0) {
    stopifnot(all(is.na(row[c("claimed_studies","correct_lower_bound_credit","global_discoveries",
      "true_global_discoveries","replicability_discoveries","true_replicability_discoveries","study_count_recovery")])))
    next
  }
  table <- read_csv(file.path(directory,"outcomes.csv"))
  r <- table$true_count
  l <- rowSums(table[c("q1","q2","q3")]<=.05/3)
  stopifnot(identical(as.numeric(l),as.numeric(table$claimed_count)),
    sum(l)==row$claimed_studies,sum(l*(l<=r))==row$correct_lower_bound_credit)
  q <- as.matrix(table[c("q1","q2","q3")])
  global <- pmin(1,3*apply(q,1,min))
  repl <- pmin(1,3*apply(q,1,function(x) sort(x)[2]))
  stopifnot(sum(global<=.05)==row$global_discoveries,
    sum(global<=.05 & r>0)==row$true_global_discoveries,
    sum(repl<=.05)==row$replicability_discoveries,
    sum(repl<=.05 & r>=2)==row$true_replicability_discoveries,
    abs(mean(ifelse(l<=r,l/pmax(r,1),0)[r>0])-row$study_count_recovery)<1e-12)
  stopifnot(isTRUE(all.equal(global,table$global_adjusted,check.attributes=FALSE,tolerance=1e-13)),
    isTRUE(all.equal(repl,table$replicability_adjusted,check.attributes=FALSE,tolerance=1e-13)))
}
archive <- file.path(project_root,"exports",paste0(basename(run_dir),".zip"))
destination <- ensure_dir(tempfile("document-archive-check-"))
utils::unzip(archive,exdir=destination)
copy <- file.path(destination,basename(run_dir))
stopifnot(all(vapply(seq_len(nrow(index)),function(i)
  file_hash(safe_file(file.path(copy,index$path[i]),copy))==index$sha256[i],logical(1))))
unlink(destination,recursive=TRUE)
cat("Verified",nrow(summary),"method/scenario summaries;",nrow(usage),
  "sessions;",nrow(index),"archive entries;",sum(usage$physical_api_attempts),"API attempts.\n")

marker_path <- file.path(run_dir,"package-complete.json")
if (file.exists(marker_path)) {
  marker <- read_json(marker_path)
  stopifnot(marker$sha256==file_hash(archive),marker$share_sha256==file_hash(marker$share))
  destination <- ensure_dir(tempfile("share-check-"))
  entries <- utils::unzip(marker$share,list=TRUE)$Name
  stopifnot(!any(grepl("(^|/)(private|input|work)/",entries)))
  utils::unzip(marker$share,exdir=destination)
  root <- file.path(destination,basename(run_dir))
  subset <- read_csv(file.path(root,"SHA256.csv"))
  stopifnot(all(vapply(seq_len(nrow(subset)),function(i)
    subset$sha256[i]==file_hash(safe_file(file.path(root,subset$path[i]),root)),logical(1))))
  unlink(destination,recursive=TRUE)
  cat("Verified compact share archive and absence of raw input/private/work directories.\n")
}
