# Document-based three-study workflow

This protocol implements Section 2.1 and Section 3 of `nsf_bsf_2025 (1).pdf`.
The scientific prompt is copied unchanged into `prompts/document-20261111.txt`.
Its provenance file records PDF and prompt SHA-256 digests. Typesetting line breaks
and discretionary line-end hyphens are removed; scientific wording is preserved.

## What the model receives

Every source session gets that one instruction block through PydanticAI
`instructions=`, with no additional custom system prompt, developer instructions,
reference brief, or retrieval tool. Its user message contains only m, n per arm,
FWER/FDR and the numeric family level 0.05/3. The two tools are `run_r` and
`write_artifact_file`; `finalize_design` is the typed final output. Tool schemas
contain the technical data and output contract, and are part of the recorded
model inputs. `prompt-preview.md` captures the actual PydanticAI tool schemas.

Each agent sees its own independent exposed/control matrices. It never sees
simulation truth, the generator, c, regime labels, sibling data/conversations,
pooled selection results, or held-out results. Separate instances, histories,
dependencies and workspaces are allocated per source. Python handles the model;
R handles simulation, statistical execution, selection and scoring.

## Design interface

The agent writes only `analysis.R` and `report.md`. The R script exports a
`hypotheses` data frame with `measurement_id` (matrix column name) and integer
`direction` (+1 exposed > unexposed, -1 exposed < unexposed). Both directions may
occur, but each pair is unique. There is no arbitrary hypothesis ID or external
hypothesis CSV. Store source-derived weights and selections in the script.

`analyze(exposed, unexposed, alpha)` returns a named list:

- `directional_results`: measurement_id, direction, p_value,
  adjusted_p_value, reject, in that column order; exactly the frozen family.
- `outcome_results`: measurement_id, adjusted_p_value, reject, in that order;
  every input measurement once. Nonselected outcomes have value 1/no rejection.

P-values must be finite within [0,1]; reject is logical and equals adjusted value
<= supplied alpha. An outcome is rejected exactly when any of its directional
claims is rejected. If both directions are tested, the design itself computes
and explains a combined outcome value; the framework does not invent it.
Use input matrix dimensions: pooled inputs have twice the source rows per arm.
The script cannot require exploratory workspace files at evaluation time.

## Validation and execution

The agent can run exploratory R, inspect errors/output, and write files.
`exploration.md` is generated from exact recorded calls/results, without rerunning
anything. The original explanation/recommendations remain in `report.md`.

Finalization checks bounded regular files, parses and loads definitions in a
fresh restricted container **without any observations**, checks family and
function arguments, and never calls `analyze`. Structural failures may be repaired
at most twice. Successful script/report files are hashed and frozen. No
performance-driven repair follows freezing.

After all three source attempts finish, target i compares designs j/k on pooled
j+k exposed and control samples separately. Both run at alpha/3; the larger
unique-outcome rejection count wins, ties use smaller source index. One failed
candidate permits the survivor with a degraded flag; two failures fail that
target. The unchanged winner runs on independent held-out i. The original cycle
is secondary. Equivalent evaluations use a hash-verified cache, including input,
artifact, runtime, level and deterministic execution seed identity.

Each execution has no network/credentials/truth/sibling workspaces, read-only
inputs, a fresh filesystem/process, nonroot user, 60-second deadline, one CPU,
2 GiB memory, process cap and bounded output. Docker only executes generated R;
it is not an agent or a statistical validator. Runtime checks enforce the output
contract, not statistical calibration. No pooled or target feedback reaches agents.

## Scoring

For each outcome, q1/q2/q3 are the combined adjusted values supplied by designs.
Global value is min(1,3*min(q)); replicability is min(1,3*second-smallest(q)).
No further correction is applied. Replicability requires effects in at least two
studies, without requiring a common direction. L counts studies with q<=alpha/3;
r is the true number of nonzero studies. Main totals are sum(L),
sum(L*I(L<=r)), global discoveries and true global discoveries, and replicability
discoveries and true replicability discoveries. Recovery is mean(L/r*I(L<=r))
over r>0. Wrong studies/signs may still earn count credit; directional errors,
FDP, directional power, overclaims and all-null discoveries are separate.
Missing targets make all aggregate scores incomplete, never zero-filled.

The primary comparator tests every outcome with a two-sided Welch test,
Holm for FWER or BH for FDR, at alpha/3 separately in each study. It makes no
sign claims. Pooled counts are exploratory; one iteration does not estimate
long-run error rates. Offline fixtures are prewritten software tests, not findings
about autonomous agents.

## Running and reading outputs

Use the existing locked renv/Poetry dependencies. Do not install new frameworks.

```sh
Rscript --vanilla scripts/build_image.R --config config/document-pilot.yml
poetry run pytest
Rscript --vanilla scripts/test.R
Rscript --vanilla scripts/preflight.R --config config/document-pilot.yml --offline
Rscript --vanilla scripts/run_pilot.R --config config/document-pilot.yml --run-dir results/document-offline --offline
```

A live run uses a new output directory and omits `--offline`. It requires an
explicit model and exported OPENAI_API_KEY. This protocol never reads `.env`.
`--dry-run` lists scenarios without Docker/model calls. `--scenario` selects one
scenario; its RNG slot remains fixed. `--reuse-run PATH` imports only compatible
historical dense datasets, with byte hashes and origin recorded; it never
imports old designs as new-prompt designs. New runs refuse existing directories.
Legacy configs/readers and historical output remain available unchanged.

Both regimes and c=.2/.6/.9 give 24 nominal scenarios/18 dataset slots/at most
72 sessions. Planning failures remain in failures.csv, with no redraw. Matching
m=100 FWER/FDR settings share data. All settings are planned before model calls.

Open report.html for summaries, report.Rmd for editable source, and summary.csv
for numbers. Under scenarios/, agent-N/frozen contains code, explanation,
exploration and integrity metadata. selection-*.csv records selection; method
subdirectories contain target-results.json, outcomes.csv (full document tables)
and directional-metrics.csv where applicable. evaluations/ retains execution
and cache audits. private/ contains truth/observations for reproducibility;
none is agent-visible. The results ZIP includes a README and SHA256.csv.

Generated results, ZIPs, private inputs and credentials are excluded from Git.
Reports escape agent text and never knit agent-supplied R Markdown.

## Checkpoints and the live results report

The scientific prompt is unchanged. The technical artifact schema now requires
four nonempty Markdown headings in each agent's report: Exploration findings,
Hypothesis selection, Final procedure, and Assumptions and limitations. These
hold the agent's actual source evidence, reproducible selection/direction rule,
counts, cutoff/weight rationale, correction/combination procedure and relevant
assumptions. This is a structure check, not a scientific-quality grader.

`run.json` seals configuration, model/interface/scientific prompt/source hashes
and resolved image identity. `datasets.json` seals every dataset's bytes before
any model session. Use `--reuse-run results/document-verified-20261112` to import
both regimes from the verified snapshot without redrawing. Each source has a
pending/running/frozen/failed checkpoint. Frozen directories are published by
atomic rename, with a completion marker covering the frozen metadata hash.

Use the original command plus `--resume` to recover the same run. Identity or
hash mismatches stop recovery. Frozen sessions never call the model again.
Unstarted sessions continue. Interrupted sessions without a committed design
are marked failed; their histories/partial artifacts/API-attempt counters and
known usage are preserved, with no silently renewed budget. Existing transient
transport retries and structural repairs stay within original limits. No target
results return for redesign. Concurrent controllers are refused. Each completed
scenario commits its results and an integrity index immediately.

The main report leads with actual live/fixture status, matched discovery counts,
paired recovery comparisons, plots, completeness and usage. Appendices contain
metric definitions/examples, the exact prompt and technical interfaces, method
excerpts, all original explanations and an agent index. `agent-methods.csv`
distinguishes proposed designs from selected target uses. `selected-algorithms.csv`
records routing, ties, failures and artifact digests. Historical comparisons are
restricted to matched dense datasets and are workflow comparisons, not proof of
a prompt-only effect.

The full ZIP retains reproducibility records. The smaller `-share.zip` contains
reports, frozen code, original explanations, exploration journals, per-measurement
results and audits, but omits raw observation/truth matrices and mutable workspaces.
It has a separate subset hash index. Previous archives are never overwritten;
interrupted packaging outputs are retained under timestamped names.

An explicitly authorized trusted launcher may privately extract only OPENAI_API_KEY
from the original .env and export it to the run subprocess. This does not display,
log or copy the credential file/value into artifacts. The source-session module
still accepts only an exported key, and R tools/containers receive no credential.
Without that explicit authorization, .env remains unread.

## Independent verification and a portable reviewed report

After the controller exits, verify the saved scores and original archives:

```sh
Rscript --vanilla analyses/validate_document_run.R results/document-live-20261115
```

This independently recomputes the six aggregate counts and recovery from saved
outcome values, checks incomplete scores, and verifies full and compact archive
hashes. It makes no model calls and does not rerun agent designs.

Create a results-first portable copy with additional interpretation:

```sh
Rscript --vanilla analyses/document_live_review.R \
  --run-dir results/document-live-20261115 \
  --output deliverables/document-live-20261115-final
```

Choose a new output directory when repeating this command. The original live
directory and its archives remain unchanged. The reviewed copy adds explicit
source failure reasons, readable paired tables, all-route comparisons, family
structure and post-run direction-eligibility diagnostics. Its plots show only
complete paired settings. Markdown formatting preserves literal original agent
text and renders that text without executing it. The script renders the editable
R Markdown, writes a directory guide and creates a separately indexed ZIP in
`exports/`. These diagnostics are not sent to agents or used to select designs.

For this live experiment, build a sequential main report and separate supplement:

```sh
Rscript --vanilla analyses/restructure_document_report.R \
  --source deliverables/document-live-20261115-final \
  --output deliverables/document-live-20261115-guide
```

The main text is maintained in `analyses/document-reader-template.md`; coverage,
findings, family/session counts, timing/usage and tables come from saved local
CSV/JSON files. No saved-run results are embedded in the public template.
`supplement.html` preserves original
literal explanations/code, organized into appendices A–H. This narrative describes
this specific experiment. Use a new output directory, and verify the narrative
when adapting it to another run. Restructuring and rendering make no model calls.

The specification-aligned edition uses the six measure names from Section 3
verbatim, labels probability settings by Π(0,0,0), and places the later-agreed
study-count recovery score in Supplement I. Build it with the same command and
`--output deliverables/document-live-20261115-specification`. The generated
`specification-terms.csv` maps document names to unchanged stored field names;
`specification-provenance.json` records the source PDF identity. The tables and
agent artifacts keep their original values and hashes. Original quoted agent
reports and code excerpts are never rewritten to match framework terminology.
