# Sharing code and results

The public repository contains the current implementation, scientific prompt,
configuration, dependency locks, tests and reusable report sources. Saved runs
and report bundles are distributed separately. Rendering obtains findings and
usage from local CSV/JSON inputs; no saved-run values are embedded in the template.

## Publish source

Stage explicit code/documentation paths, then run:

```sh
Rscript --vanilla scripts/check_public_files.R
```

The check reads staged Git blobs, rejects private/generated paths, unusual modes,
oversized content and credential patterns, and prints filenames only on failure.
It never opens `.env`. Ignore rules do not protect files already tracked, so
inspect staged names as well. No credentials, results, report bundles, complete
PDFs or synthetic observation/truth matrices belong in public Git.

## Verify and share results

Completed runs produce an editable R Markdown report, rendered HTML, detailed
CSVs, frozen code/explanations/exploration and integrity records. The complete
local archive preserves reproducibility inputs. The compact share archive omits
raw observations, private truth matrices and mutable workspaces and has its own
subset hash index.

```sh
Rscript --vanilla analyses/validate_document_run.R results/my-live-run
```

The validator recomputes the six measures and recovery from saved outcome values,
checks incomplete scores and verifies full/compact archive hashes. It makes no
model calls. Further report formatting is documented in the workflow guide.

A share bundle can still contain agent explanations, exploratory summaries,
usage and execution audits. Share it directly with intended collaborators;
publishing it in a public GitHub release is a separate action. Agent text is
rendered literally, never executed as R Markdown.

Older source is retained in Git history. Cleanup of the current repository does
not delete or rewrite saved runs, frozen designs, private local reference PDFs
or existing ZIPs. A historical run must use its original source revision and
recorded execution image for exact continuation.
