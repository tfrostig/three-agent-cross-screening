# Current three-study workflow

There is one scientific prompt, `prompts/system.txt`, and one default configuration,
`config/pilot.yml`. The prompt preserves Section 2.1 of the approved specification;
`prompts/system.provenance.json` records its source and SHA-256. Older source is
available in Git history, not as a second executable workflow.

## Code ownership and model input

| Responsibility | Code |
|:--|:--|
| Generation and sample-size planning | `R/simulation.R`, `R/config.R` |
| Current orchestration, freeze/checkpoints and scoring | `R/document*.R` |
| PydanticAI agent and typed tools | `agents/document.py` |
| Provider lifecycle and conversation audit | `agents/runtime.py`, `agents/transport.py` |
| Restricted R bridge and containers | `agents/runner.py`, `R/sandbox.R`, `R/document_sandbox.R`, `docker/` |
| Reports and archive verification | `R/document_results.R`, `analyses/` |

Each source session receives the exact scientific text once through PydanticAI
`instructions=`. There is no additional custom scientific system/developer block,
reference brief or retrieval tool. The user message contains exactly:

```text
Number of measurements: {m}
Exposed sample size: {n}
Unexposed sample size: {n}
Error criterion: {FWER or FDR}
Family level: {numeric value of 0.05/3}
```

Each agent sees only its own exposed/control matrices. It receives no generator,
truth, c, regime label, sibling data/history, combined-data results or target
results. Instances, dependencies, histories, workspaces and audits are separate.

Export the actual instructions, user template and PydanticAI-generated tool/output
schemas without credentials or provider calls:

```sh
poetry run python -m agents.document_preview --output deliverables/model-input.md
```

## Tools and submitted artifacts

- `run_r(code)` runs exploratory R with the session's numeric `exposed` and
  `unexposed` matrices. Rows are independent observations; matching column names
  identify measurements. Files persist in the session workspace, R variables do not.
- `write_artifact_file(path, content)` writes `analysis.R` or `report.md`.
- `finalize_design(script_file, report_file)` is the typed final submission,
  restricted to those two filenames.

`report.md` must contain nonempty sections: Exploration findings, Hypothesis
selection, Final procedure, and Assumptions and limitations. This checks formatting,
not scientific quality. The framework derives `exploration.md` from recorded R
calls and outputs without rerunning them. Agent Markdown is rendered literally.

`analysis.R` exports `hypotheses`, a data frame with `measurement_id` (existing
column names) and integer `direction` (+1 or −1), and:

```r
analyze <- function(exposed, unexposed, alpha) { ... }
```

Both directions are permitted; duplicate measurement–direction pairs are rejected.
All choices, weights, cutoffs and source-derived parameters must be embedded in
the script. No hypothesis CSV, arbitrary hypothesis ID or exploratory-file dependency
is used. Input dimensions must support both ordinary and combined subsets.

The function returns these exact tables:

| Table | Columns |
|:--|:--|
| `directional_results` | measurement_id, direction, p_value, adjusted_p_value, reject |
| `outcome_results` | measurement_id, adjusted_p_value, reject |

The first contains exactly the frozen family, the second every measurement once.
Nonselected outcomes have adjusted value 1 and no rejection. The design itself
supplies and explains the outcome-level combination when testing both directions.
The framework does not replace its multiplicity procedure.

## Validation, isolation and freezing

Submission checks require bounded regular files, safe paths, R syntax, valid
measurement names/directions, the specified function signature and required
Markdown sections. Definitions are inspected in a fresh restricted container
**without observations**. `analyze()` is not called during this check. Structural
errors may be repaired within budget; no p-values or discovery counts are returned.

Accepted files are frozen read-only with artifact hashes and an atomic completion
marker. All source attempts finish before selection. Every exploration, inspection
and uncached evaluation uses a fresh container: no network, credentials, truth,
generator, sibling files or Docker socket; inputs and code are read-only, with
bounded writable scratch/output.

After execution, validate exact required rows, unique families, finite values in
[0,1], decisions equal to adjusted value ≤ supplied alpha, directional/outcome
rejection agreement, nonselected outcomes and unchanged frozen hashes. These
checks establish executable/reporting consistency, not statistical validity.

Budgets remain 16 physical API attempts per session, 8,192 output tokens per
response, 12 exploratory R calls, 32 tool calls and two structural repairs.
Transport retries count within the physical-attempt budget. R containers have a
60-second deadline, 2 GiB memory, one CPU, 128-process limit and bounded output.

## Selection and scoring

For target i, combine the exposed samples of the other two subsets separately
from their controls. Apply both of their frozen designs at 0.05/3. More unique
measurements with rejections wins; count both-direction rejections once and audit
the conflict. Ties use smaller source index. Apply the winner unchanged to i,
again at 0.05/3. No combined-data or target feedback reaches agents.

One failed candidate yields a flagged degraded comparison using the survivor;
two failures leave the target missing. Missing target evaluations make aggregate
scenario scores incomplete, never zero-filled. Combined-data counts select a
design and are exploratory, not confirmed findings. The original cycle is a fixed
routing comparator using the same current designs; it is not a separate agent
implementation. A truth-informed oracle is labeled as an additional reference.

The non-agent competitor uses two-sided Welch for every outcome, with Holm for
FWER or BH for FDR, within each subset separately at 0.05/3. All three subsets are
aggregated with the same [six measures](document-metrics.md). Study-count recovery
and directional error diagnostics are additional. One iteration reports realized
outcomes and does not establish long-run FWER/FDR.

## Planning and checkpoints

The configuration uses both specified hypothesis-state distributions and
c=0.2/0.6/0.9, giving 24 nominal scenarios, 18 dataset settings and at most 72
source sessions. Matching m=100 FWER/FDR scenarios share observations. Preserve
RNG-stream assignments and choose the strictly smallest qualifying n. Undefined
planning or resource-limit failures are recorded without redrawing.

`run.json` seals configuration, prompt/interface/source hashes and resolved image
identity. `datasets.json` seals observations before sessions start. Each source
has pending/running/frozen/failed state. Resume verifies identity and hashes,
skips committed designs and continues unstarted sessions. Interrupted/failed
sessions keep histories, partial artifacts and known usage; no fresh budget is
silently allocated. Concurrent controllers are refused. Each scenario commits
its outputs immediately. Only complete, verified evaluation caches are reused.

`--reuse-run PATH` imports compatible observations through hash-verified provenance,
not agent designs. A small read-only historical results comparison remains
available when explicitly configured; it does not execute an older agent protocol.
Use an older run's original Git commit and recorded image for exact continuation.

## Commands and reports

```sh
Rscript --vanilla scripts/build_image.R
poetry run pytest -q
Rscript --vanilla scripts/test.R
Rscript --vanilla scripts/run_pilot.R --dry-run
Rscript --vanilla scripts/preflight.R --offline
Rscript --vanilla scripts/test_document_sandbox.R
Rscript --vanilla scripts/run_pilot.R --offline --run-dir results/offline-demo
```

Live execution uses a new directory and omits `--offline`. It requires an explicit
model and exported `OPENAI_API_KEY`. No code loads `.env`. Dry runs and previews
make no model calls and need no credentials.

Completed runs contain report.Rmd/HTML, summary and per-outcome CSVs, selection
records, failures, usage, timing and frozen agent artifacts. Verify scores and
archives independently:

```sh
Rscript --vanilla analyses/validate_document_run.R results/my-live-run
```

Create a separate reviewed portable copy and a sequential main report/supplement:

```sh
Rscript --vanilla analyses/document_live_review.R --run-dir results/my-live-run --output deliverables/my-reviewed-run
Rscript --vanilla analyses/restructure_document_report.R --source deliverables/my-reviewed-run --output deliverables/my-report
```

The main report explains measures before results and uses separate agent/competitor
columns. The supplement preserves original agent Markdown, exact instructions,
code, exploration and audits. Coverage, findings and resource totals are derived
from local saved files. Use fresh output paths; the original run and previous ZIPs
remain unchanged. See [sharing](sharing.md) for public Git boundaries.
