# Pooled algorithm selection and study-count recovery: results package

Extract the ZIP and start with **[the concise summary](runs/{{PRIMARY_RUN}}/summary.html)**.
It explains the experiment, the pooled selection rule, the new score, results,
and limitations. The [full report](runs/{{PRIMARY_RUN}}/report.html) includes every
agent's frozen scientific explanation and the complete selection/evaluation tables.

## Reading order

1. Read `runs/{{PRIMARY_RUN}}/summary.html` for the primary results.
2. Open `selection-decisions.csv` in that run for each target's chosen algorithm.
3. Open `selection-candidates.csv` for the two pooled scores and any execution failures.
4. Inspect the selected source agent's `frozen/report.md`, `analysis.R`, and `hypotheses.csv`.
5. Use its `audit/exploration/` files and matching result JSON for the R exploration it performed.

HTML files open locally after extraction. CSV files can be read in R or a
spreadsheet; Markdown and R source open in a text editor. Reports do not execute
agent-provided code when opened or rendered.

## Directory map

| Directory | Contents |
|:---|:---|
| `runs/{{PRIMARY_RUN}}/` | New pooled-selection results; source designs are explicitly marked imported or generated. |
| Other directories under `runs/`, when included | Historical original/revised runs, retained as context. They use the original cyclic transfer and directional-power definition. |
| `methods/` | Methodological context, shared prompt templates, isolation notes, and curated references. Archived session prompts remain authoritative for each source design. |
| `examples/` | Editorial notes about two historical revised-agent examples, when those runs are included. |
| `MANIFEST.csv` | File sizes, SHA-256 hashes, source provenance, and copy/sanitization disposition; excludes its own hash. |

## Inside the new run

| Path | How to read it |
|:---|:---|
| `summary.Rmd`, `summary.html`, `summary.md` | Portable concise summary; the R Markdown reads included CSVs only. |
| `report.html` | Full report with frozen explanations and execution detail. |
| `scenarios.csv`, `planning.csv` | Settings and sample sizes. `c` is the planning target; `n` is observations per arm in each study. |
| `study-count-summary.csv` | Primary count recovery, overclaims, and all-null discoveries by scenario/method. |
| `global-scores.csv`, `scores.csv` | Secondary directional outcomes, plus the primary score in global results. |
| `selection-candidates.csv`, `selection-decisions.csv` | Pooled exploratory counts, failures, chosen sources, ties, and degraded comparisons. |
| `usage.csv` | New API usage; imported designs have zero new usage and separate historical attempts. |
| `exploration-index.csv` | Exact archived source calls, request/result paths, seeds, and hashes. |
| `scenarios/<scenario>/study-counts/<method>.csv` | Per-measurement true/claimed study counts, credit, and overclaim indicators. |
| `scenarios/<scenario>/evaluation-ledger.csv` | Target routing and exact hypothesis/result files used to calculate recovery. |
| `scenarios/<scenario>/selection/` | Pooled candidate outputs and container/cache audit records. These are selection scores, not confirmed discoveries. |
| `scenarios/<scenario>/evaluation/` | Held-out source/target results and full Welch/oracle baseline outputs. |
| `scenarios/<scenario>/agent-N/frozen/` | Final `analysis.R`, `hypotheses.csv`, `report.md`, and `frozen.json` hashes. |
| `scenarios/<scenario>/agent-N/audit/` | Exact prompts/history, exploration sources, requests/results, and session metadata. |
| `scenarios/<scenario>/agent-N/design-origin.json` | Whether a design was imported or generated, with reuse provenance. |
| `scenarios/<scenario>/agent-N/imported-check.json` | Offline source-data recheck of an imported frozen design. |

`agent_pooled_select` is the new procedure: for target i, compare the other two
source algorithms on their pooled observations at 0.05/3 and apply the winner
unchanged to i. `agent_cycle` retains the previous cyclic routing. Other method
IDs distinguish full Welch from known-variance z and BH from BY. All target
studies are tested separately. Agents do not receive pooled/target results.

For a measurement with r>0 truly affected studies and k claimed studies, recovery
is k/r when k<=r and zero otherwise. Average equally over measurements with r>0.
It is count-only and can award credit for incorrect study identities or directions;
directional errors are therefore reported separately. All-null measurements are
excluded from that average and their discoveries are counted separately. Missing
targets make the recovery score incomplete. One realization does not estimate
long-run FWER or FDR.

Imported frozen artifacts and exploratory R source retain their original bytes.
Historical usage is not new usage. Paths in other exported text are replaced with
placeholders. No credentials, input matrices, private truth RDS files, workspaces,
full PDFs, or internal proposal are included. Numerical summaries of synthetic
observations remain in audit outputs. This is a review package, not a resumable run.

To regenerate the concise summary, change into the primary run directory and use:

```r
rmarkdown::render("summary.Rmd")
```

This requires `rmarkdown`, `knitr`, and Pandoc, but makes no API calls and does not
execute agent code. The public implementation is at
[tfrostig/three-agent-cross-screening](https://github.com/tfrostig/three-agent-cross-screening).
