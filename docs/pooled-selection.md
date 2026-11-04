# Pooled algorithm selection and study-count recovery

The current experiment has twelve scenarios: FWER at 20/100 measurements and
FDR at 100/1,000, each at planning targets 0.2, 0.6, and 0.9. There is one
iteration per scenario and no additional validation draws. R owns pooling,
selection, routing, and scoring. Python agents and their prompts are unchanged.

## Reuse and random streams

`--reuse-run results/live-revised-20261101` explicitly imports 24 frozen designs
and six datasets, leaving twelve new source sessions at c=0.9. The source run's
scientific parameters, model/budgets, reference catalog and Docker identity must
match. Files are snapshotted with hashes before execution. Input matrices must
equal the imported setting; source prompts must match current templates and the
verified reference identity. Every imported analysis is rechecked in Docker on
its own source data. A frozen design is copied, never rewritten.

`design-origin.json` and `imported-check.json` document imports. Original audit
records retain historical session usage. `usage.csv` reports zero new usage for
imports, with separate historical attempts, tokens and time. This import operation
does not relax strict resume checks: the new run has its own signature and cache.
Source files remain outside agent mounts, and no historical target results enter
new agent conversations.

The original six RNG slots remain `m100_c20`, `m100_c60`, `m1000_c20`,
`m1000_c60`, `m20_c20`, `m20_c60`. Append `m100_c90`, `m1000_c90`, `m20_c90`.
Each receives independent state/effect/observation streams. Consequently adding
c=0.9 cannot shift the earlier datasets. Matching m=100 criteria share data.

## Selection interface and outputs

For held-out i, `pool_non_target(observations, i)` concatenates exposed observations
from the other two studies and separately concatenates controls. It never pairs
rows or uses effects. `evaluate_candidate()` runs each other study's frozen
analysis on the pooled pair at alpha/3 and counts unique rejected measurements.
Both-direction rejection of one measurement counts once and is separately audited.

`choose_candidate()` maximizes that count with smaller source index as the tie
rule. Failed candidates have missing counts and are excluded. One survivor is
used with `degraded=TRUE`; neither survivor yields a failed target. The chosen
algorithm, including its complete frozen family/settings, is then applied to i
in a fresh container at alpha/3. Pool results are exploratory selection scores,
because a candidate used part of that pool during design. Only held-out results
enter outcome scoring. Agents receive neither selection nor target outputs.

`agent_pooled_select` identifies this procedure; `agent_cycle` retains the earlier
1→2, 2→3, 3→1 comparator. Identical held-out source/target executions share a cache
bound to observation bytes, artifact hashes, alpha, sandbox, and execution identity.
Historical cyclic outputs can be reused only from the verified source snapshot.
Every evaluation is schema-validated and frozen hashes are checked around execution.

Selection candidates/decisions are saved per scenario and combined at the run
root. The evaluation ledger identifies every method's source, target, status,
hypothesis table and result file. Failures remain failures; they never become
successful zero-discovery rows.

## Count-only score

For measurement h, let r_h count nonzero truth effects across three studies and
k_h count studies with at least one rejection for that measurement. For r_h>0,
credit is k_h/r_h if k_h<=r_h, otherwise zero. The primary scenario score averages
credit equally over measurements with r_h>0. This is **study-count recovery**.
For r=3, claims of 1/2/3 earn 1/3, 2/3, 1. For r=2, a claim of 3 earns zero.

It intentionally scores only the count: wrong study identities or signs can earn
credit. Directional errors and the original directional power remain secondary
outputs. All-null measurements are excluded from the recovery average; their
discoveries and other overclaims are counted separately. No eligible measurement
means an undefined average. Any missing/failed target makes the method incomplete
and its global recovery/overclaim totals missing rather than zero.

`study-counts/<method>.csv` records measurement ID, true count, claimed count,
credit, overclaim flag, all-null flag, observed partial claims, evaluable-study
count, and completion. `study-count-summary.csv` contains the macro average and
error totals. `global-scores.csv` retains secondary directional outcomes and adds
the recovery fields. A unique discovered measurement across studies is different
from a directional hypothesis rejection; both counts are available explicitly.

## Reproduction and review

```sh
Rscript --vanilla scripts/run_pilot.R --dry-run --reuse-run results/live-revised-20261101
Rscript --vanilla scripts/check_reuse.R --reuse-run results/live-revised-20261101
Rscript --vanilla scripts/run_pilot.R --reuse-run results/live-revised-20261101 --run-dir results/live-pooled-20261104
Rscript --vanilla scripts/export_exploration.R --run-dir results/live-pooled-20261104
Rscript --vanilla analyses/validate_pooled_run.R --run-dir results/live-pooled-20261104 --reuse-run results/live-revised-20261101
Rscript --vanilla scripts/build_results_bundle.R --run-dir results/live-pooled-20261104 --output-dir exports/pooled-results-2026-11-04
```

The check command uses Docker and no credentials/model calls. The live command
uses the existing authorized runtime credential loader and twelve new model
sessions when the full historical source is available. Public review ZIPs omit
private data, so they alone are not sufficient to import/resume a historical run.
Without `--reuse-run`, live execution generates all 36 designs instead.

The saved-results validator independently reconstructs count credit from raw
target CSVs, verifies selection counts and tie decisions, checks imported bytes,
reproduces historical cyclic/baseline metrics, and verifies usage separation and
c=0.9 planning minimality. Its optional `--original-hashes FILE` checks a local
pre-run inventory. It makes no new model calls or scientific draws.

For a deterministic software check, use `--offline` and a new temporary run
directory. Package that fixture alone using `--standalone --run-dir DIR`.
Fixture reports are labeled and do not assess a live model's scientific quality.
The portable `summary.Rmd` needs only included CSVs plus rmarkdown/knitr/Pandoc.
Do not interpret one iteration's recovery, FDP, or overclaims as long-run guarantees.
