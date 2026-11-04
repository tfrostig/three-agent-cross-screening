# Sharing code and results

For the current pooled-selection extension, package the new run and historical
comparisons with `--run-dir results/live-pooled-20261104 --output-dir exports/pooled-results-2026-11-04`.
The reading guide points to its primary study-count recovery summary. Counts are
derived from the included scenario grid rather than assuming eight scenarios or
24 designs. Use `--standalone --run-dir DIR` to package a single offline fixture.
See [the extension guide](https://github.com/tfrostig/three-agent-cross-screening/blob/main/docs/pooled-selection.md) for imports and selection provenance.

The public repository contains implementation, current prompts, configuration,
lockfiles, offline checks, curated references, and report templates. Saved runs
are distributed separately so that credentials, synthetic input matrices, private
simulation truth, and local runtime files cannot enter an initial Git commit.
Nothing is deleted from the working project by the sharing scripts.

## Results bundle

From the project root, with both completed runs present:

```sh
Rscript --vanilla scripts/build_results_bundle.R
```

The default destination is `exports/three-agent-cross-screening-results-2026-11-02/`
and the adjacent ZIP. Use `--output-dir <new-directory>` for a different export.
Existing destinations are rejected to prevent accidental replacement.

The packager uses an explicit allowlist. It copies the original and revised run
reports, score tables, per-hypothesis evaluations, frozen designs, exploration
scripts/results, prompts, session metadata, and conversation records. A separate
directory records the revised run's single infrastructure failure and recovery.
It also supplies a portable R Markdown comparison and two annotated examples.

Copied audit records replace local home/project paths with placeholders. Frozen
analyses, hypothesis lists, scientific explanations, and exploration source remain
byte-identical to their originals; a local path in one of those files causes a
failure instead of silently changing the artifact. SHA-256 inventory entries say
which files were copied unchanged, path-sanitized, or generated. The script
verifies frozen hashes and exported exploration code against original requests.
It scans allowed files for common credential formats without opening `.env`.

Input matrices, private truth files, workspaces, execution caches, raw controller
logs, temporary render files, full PDFs, and the proposal are omitted. Audit
records include summaries of synthetic observations; they are research outputs,
not an archive stripped of all observed numerical values. References and prompt
text are evidence of what agents received, not instructions to the reader.

The portable `summary/summary.Rmd` reads only the included CSV files. It does not
execute agent code or call OpenAI. Original run report HTML files are already
rendered; their source-specific report builders still require the full local
project and omitted data. A new model run is stochastic and need not reproduce
the frozen designs even with the same simulation seed.

## Public Git checks

After staging an explicit list of code directories and lockfiles, run:

```sh
Rscript --vanilla scripts/check_public_files.R
```

The check reads staged blobs, rejects private/generated paths, links, unusually
large files, and common secret formats, and prints only offending filenames.
It never reads `.env` or compares against actual credential values. A Git ignore
rule is a convenience, not protection for a file already tracked. Inspect staged
filenames before committing and rerun this check for later publications.

Only source files belong in the public repository. Share the results ZIP directly
with collaborators; uploading it to a public GitHub release is a separate action.
