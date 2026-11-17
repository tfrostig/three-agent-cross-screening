# Three-agent cross-screening

**Current scientific prompt: [prompts/system.txt](prompts/system.txt).** It is an
exact copy of the approved, versioned [document-20261111.txt](prompts/document-20261111.txt).
The current agent loads that versioned text once through PydanticAI `instructions=`;
no additional custom scientific system/developer block or reference brief is added.

**Current default configuration: [config/document-pilot.yml](config/document-pilot.yml).**
The previous system/developer texts are preserved as
[legacy-system.txt](prompts/legacy-system.txt) and
[legacy-developer.txt](prompts/legacy-developer.txt), used only by the explicit
legacy workflow. [The prompt directory guide](prompts/README.md) explains the mapping.

R implements simulation, planning, deterministic validation, selection, evaluation
and reporting. Python implements isolated PydanticAI source-design sessions.

## Current workflow

1. Generate three independent exposed/control pairs for the same outcomes.
2. Each agent explores only its own subset using R and writes a self-contained
   analysis design plus a scientific explanation.
3. Check the submitted files and inspect definitions without observations;
   do not apply the final analysis during submission validation. Freeze accepted designs.
4. For target study i, compare the other two frozen designs on their combined
   observations at 0.05/3. More unique discovered outcomes wins; ties use the
   smaller source-agent index. These counts select a design and are exploratory.
5. Apply the winner unchanged to study i in a fresh restricted container, at
   0.05/3. Agents receive no combined-data or target results for redesign.
6. Compare with two-sided Welch testing of every outcome, separately within each
   subset, with Holm for FWER or BH for FDR. Aggregate all three subsets using
   the specification's six measures.

The current configuration contains 24 nominal settings, 18 dataset settings and
at most 72 source sessions: FWER with m=20/100, FDR with m=100/1000, c=0.2/0.6/0.9,
and both hypothesis-state distributions. Matching m=100 FWER/FDR settings share
observations but use separate agent sessions. There is one iteration per setting
and zero additional validation draws. Undefined planning is recorded without redrawing.

## Documentation

| Guide | Scope |
|:--|:--|
| [Current workflow and interfaces](docs/document-workflow.md) | Exact prompt placement, typed tools, R contract, validation, isolation, selection, checkpoints and commands |
| [Current prompts](prompts/README.md) | Which files are current, which are legacy, and how to export the complete model input |
| [Six measures from the specification](docs/document-metrics.md) | Lower bounds, global null discoveries and replicability discoveries, using the original names |
| [Sharing](docs/sharing.md) | Code/results separation, staged-content checks and exclusions |
| [Legacy developer walkthrough](docs/developer-guide.md) | Earlier session, hypothesis CSV and reference-based workflow |
| [Legacy agent contract](docs/agent-api.md) | Earlier tools and artifact schemas |
| [Legacy configuration](docs/configuration.md) | Explicit config/pilot.yml settings and historical command options |
| [Legacy pooled selection](docs/pooled-selection.md) | Earlier design imports and study-count recovery extension |
| [R reference](docs/r-api.md), [Python reference](docs/python-api.md) | Earlier generated API references; current interfaces are in the workflow guide and source docstrings |

Functions carry documentation in source. The scientific prompt and tool schemas
are experimental inputs: changes require a new run identity, not silent resumption.

## Setup

Run from the repository root. Requirements: R 4.6.0, Python 3.12/3.13, Poetry,
Docker and Pandoc (also supplied by RStudio).

```sh
poetry install
Rscript --vanilla scripts/setup.R
Rscript --vanilla scripts/build_image.R
```

The image builder, preflight and experiment entry point default to
`config/document-pilot.yml`. Supplying that path explicitly is equivalent.
`poetry.lock` and `renv.lock` record dependencies; the Docker base image is pinned
in `docker/Dockerfile`. Every execution records its resolved image identity.

## Inspect and verify without OpenAI calls

```sh
poetry run python -m agents.document_preview --output deliverables/current-model-input.md
poetry run pytest -q
Rscript --vanilla scripts/test.R
Rscript --vanilla scripts/run_pilot.R --dry-run
Rscript --vanilla scripts/preflight.R --offline
Rscript --vanilla scripts/test_document_sandbox.R
Rscript --vanilla scripts/run_pilot.R --offline --run-dir results/document-offline-demo
```

`poetry run python -m agents.prompts --output FILE` also exports the **current**
model input. Add `--legacy` only to inspect the historical assembled prompts.

Tests, previews and dry runs require no credentials. Offline execution uses
prewritten deterministic PydanticAI fixtures and real restricted R containers;
its outputs are software checks, not evidence of live agent performance.

## Live execution

The current protocol requires an **exported OPENAI_API_KEY** and the explicit
model configured in `config/document-pilot.yml` (`gpt-6.1-sol`). It does not
implicitly load `.env`. Never paste a real key into a command, commit or report.
The optional private credential loader is separate and requires explicit local
authorization; it is not called by the document-protocol source sessions.

After exporting the key privately, these commands start live execution:

```sh
Rscript --vanilla scripts/preflight.R --config config/document-pilot.yml
Rscript --vanilla scripts/run_pilot.R --config config/document-pilot.yml --run-dir results/my-document-run
```

Use a new run directory. Each session has separate data, history, dependencies,
workspace and audit records. Docker receives no credentials, truth, generator,
sibling workspaces, network access or Docker socket.

A compatible checkpoint can be continued with:

```sh
Rscript --vanilla scripts/run_pilot.R --config config/document-pilot.yml --run-dir results/my-document-run --resume
```

Identity checks include configuration, prompts, implementation, data and image.
Committed designs are reused; failed or interrupted sessions do not silently
receive a new API budget. For an older saved run, use its original source revision
and explicit configuration. This update does not rewrite saved runs or archives.

## Current agent artifacts and measures

- `analysis.R`: frozen hypothesis family and `analyze(exposed, unexposed, alpha)`.
  There is no hypothesis CSV or arbitrary hypothesis ID.
- `report.md`: the agent's source evidence, hypothesis-selection rule, final
  procedure, assumptions and limitations.
- `exploration.md`: exact executed exploratory R and captured outputs, generated
  from logs without rerunning code.
- `frozen.json` and `complete.json`: framework provenance and integrity records.

The six main measures use the specification's names: total number of lower bounds,
total number of correct lower bounds, number of global null discoveries, number
of true global null discoveries, number of replicability discoveries, and number
of true replicability discoveries. The separately agreed study-count recovery
score is additional. One iteration reports realized outcomes, not estimated
long-run FWER/FDR. Executable checks do not prove every statistical assumption.

The current report is generated automatically by the run. Additional report and
verification commands are documented in [the workflow guide](docs/document-workflow.md).

## Historical workflow

The previous configuration and scientific texts remain available for explicit
legacy runs:

```sh
Rscript --vanilla scripts/build_image.R --config config/pilot.yml
Rscript --vanilla scripts/preflight.R --config config/pilot.yml --offline
Rscript --vanilla scripts/run_pilot.R --config config/pilot.yml --offline --run-dir results/legacy-offline-demo
poetry run python -m agents.prompts --legacy --output deliverables/legacy-model-input.md
```

That workflow uses `agents/session.py`, the `legacy-*.txt` files, a curated reference
brief, `check_design` and `hypotheses.csv`. The current workflow instead uses
`agents/document.py`; historical designs are not reinterpreted as current designs.
Saved conversation records identify exactly what a past agent received.

## Public repository boundaries

This repository contains code, configurations, prompts, locked dependencies,
tests, curated reference excerpts and reusable report templates. Reports obtain
saved-run numbers from local files when rendered.

Credentials, `.env`, private inputs, saved results, report bundles, ZIPs, PDFs,
local environments and machine-specific manifests stay excluded. Only the empty
`.env.example` variable template is public. Generated `results/`, `deliverables/`
and `exports/` remain local. Before publishing a change, stage explicit files and run:

```sh
Rscript --vanilla scripts/check_public_files.R
```

The check inspects staged blobs and rejects private/generated paths and common
credential patterns without opening `.env`. The historical reference pack is
retained for legacy runs; the current agents do not receive it.
