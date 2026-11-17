# Three-agent cross-screening

The repository contains one workflow, one configuration and one scientific prompt:

- **Prompt:** [prompts/system.txt](prompts/system.txt), unchanged from Section 2.1 of the approved specification.
- **Configuration:** [config/pilot.yml](config/pilot.yml).
- **Workflow and interfaces:** [docs/document-workflow.md](docs/document-workflow.md).

R handles simulation, sample-size planning, restricted execution, selection,
scoring and reporting. Python handles isolated PydanticAI design sessions.

## How it runs

1. Generate three independent exposed/control pairs for the same outcomes.
2. Each agent explores only its own subset with R and submits a reusable analysis
   plus a Markdown explanation. The scientific prompt is supplied once through
   PydanticAI `instructions=`, without a separate developer prompt or reference brief.
3. Validate the files and load definitions without observations; do not apply the
   final analysis during submission validation. Freeze accepted designs.
4. For target study i, compare the other two frozen designs on their combined
   observations at 0.05/3. Select the design with more unique discovered outcomes;
   ties use the smaller source-agent index.
5. Apply the winner unchanged to study i in a fresh restricted container. Agents
   receive no combined-data or target results for redesign.
6. Compare with two-sided Welch testing of every outcome, separately within each
   subset, with Holm for FWER or BH for FDR. Report the specification's six measures.

The configured grid has 24 nominal settings and 18 dataset settings: FWER with
m=20/100, FDR with m=100/1000, c=0.2/0.6/0.9, and both hypothesis-state distributions.
Matching m=100 FWER/FDR settings share observations but have independent sessions.
One iteration and zero additional validation draws are used. Undefined sample-size
planning is recorded without redrawing.

## Setup

Run commands from the repository root. Requirements: R 4.6.0, Python 3.12/3.13,
Poetry, Docker and Pandoc (also supplied by RStudio).

```sh
poetry install
Rscript --vanilla scripts/setup.R
Rscript --vanilla scripts/build_image.R
```

`poetry.lock`, `renv.lock` and the pinned Docker image record dependencies. The R
packages available to agents and the execution budgets are unchanged by cleanup.

## Inspect and verify without OpenAI calls

```sh
poetry run python -m agents.document_preview --output deliverables/model-input.md
poetry run pytest -q
Rscript --vanilla scripts/test.R
Rscript --vanilla scripts/run_pilot.R --dry-run
Rscript --vanilla scripts/preflight.R --offline
Rscript --vanilla scripts/test_document_sandbox.R
Rscript --vanilla scripts/run_pilot.R --offline --run-dir results/offline-demo
```

Previews, tests and dry runs require no credentials. Offline execution uses
prewritten PydanticAI fixtures with real restricted R containers; it checks
software behavior and does not measure live agent performance.

## Live execution

Export `OPENAI_API_KEY` privately in the controller environment. The configured
model is `gpt-6.1-sol`; no substitute is chosen automatically. The code does not
read `.env` or expose credentials to generated R.

```sh
Rscript --vanilla scripts/preflight.R
Rscript --vanilla scripts/run_pilot.R --run-dir results/my-live-run
```

Use a new run directory. The live command makes paid API requests. Each session
has separate data, history, dependencies, workspace and audit records. Containers
have no network, credentials, truth, generator, sibling workspaces or Docker socket.

A compatible checkpoint can be continued with:

```sh
Rscript --vanilla scripts/run_pilot.R --run-dir results/my-live-run --resume
```

Identity checks cover code, prompt, configuration, inputs and image. Committed
designs are reused; interrupted or failed sessions do not silently receive new
API budgets. Optional `--reuse-run PATH` imports only hash-verified compatible
observations, never old agent designs.

## Agent artifacts and measures

Each successful session preserves:

- `analysis.R`: frozen hypotheses and `analyze(exposed, unexposed, alpha)`.
- `report.md`: source evidence, hypothesis-selection rule, final procedure,
  assumptions and limitations.
- `exploration.md`: exact exploratory R calls and captured outputs from logs.
- `frozen.json` and `complete.json`: provenance and integrity records.

There is no hypothesis CSV or arbitrary hypothesis ID. The scientific prompt's
hash is recorded in [system.provenance.json](prompts/system.provenance.json).

The [six measures](docs/document-metrics.md) retain the specification's names:
total number of lower bounds, total number of correct lower bounds, number of
global null discoveries, number of true global null discoveries, number of
replicability discoveries, and number of true replicability discoveries. The
separately agreed study-count recovery score remains additional. One iteration
reports realized outcomes, not estimated long-run FWER/FDR. Executable checks do
not prove every statistical assumption.

## Where to find things

| Location | Purpose |
|:--|:--|
| `R/` | Current generation, validation, execution, selection, scoring and reporting |
| `agents/document.py` | PydanticAI design agent and typed tools |
| `agents/runtime.py`, `runner.py`, `transport.py` | Shared provider, audit and restricted R-execution helpers |
| `prompts/system.txt` | Sole scientific prompt |
| `config/pilot.yml` | Sole default experiment configuration |
| `docker/` | Restricted R runtime and pinned package installation |
| `analyses/` | Current report formatting and saved-run verification |
| `tests/` | Current-protocol, isolation, scoring, transport and publication checks |
| [Workflow guide](docs/document-workflow.md) | Prompt placement, full R interface, validation, checkpoints and report commands |
| [Sharing guide](docs/sharing.md) | Publication boundaries and archive verification |

## History and public repository boundaries

Older executable workflows, prompt versions and guides are removed from the
current tree. They remain available through Git history. Saved runs, frozen
artifacts, local reference PDFs and previous ZIPs are not deleted or rewritten.
Use a saved run's original commit and recorded image identity for exact resumption.

Credentials, `.env`, private inputs, saved results, report bundles, PDFs, ZIPs,
environments and machine-specific manifests stay excluded from Git. Only the
empty `.env.example` template is public. Report sources obtain saved-run values
from local files when rendered. Before publishing, stage explicit files and run:

```sh
Rscript --vanilla scripts/check_public_files.R
```

This checks staged blobs for private/generated paths and credential patterns
without reading `.env`.
