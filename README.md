# Three-agent cross-screening

R implements the simulation, sample-size calculation, tests, scoring, and report.
Python implements isolated PydanticAI design sessions. The first run covers all
eight scenarios once: 24 agent sessions, one transfer cycle per scenario, and
**zero additional validation draws**.

## Documentation

For a first code review, start with the [developer walkthrough](docs/developer-guide.md).
It follows one setting from simulation through agent design, freezing, transfer,
and scoring, with source links and an executable R-only example.

| Guide | What it explains |
|:---|:---|
| [Developer walkthrough](docs/developer-guide.md) | Call sequence, objects, ownership boundaries, failure handling, and where to make changes. |
| [Agent and artifact contracts](docs/agent-api.md) | PydanticAI architecture, each tool, session state, prompts, CSV schemas, and freeze lifecycle. |
| [Configuration and commands](docs/configuration.md) | Every YAML field, CLI option, required inputs, outputs, and operational limitations. |
| [R function reference](docs/r-api.md) | Function inputs, returned objects, filesystem effects, and failure behavior. |
| [Python API reference](docs/python-api.md) | Google-style module, class, and function documentation for the agent controller. |
| [Isolation](docs/isolation.md) | Container mounts, credential boundaries, and audit checks. |
| [Sharing](docs/sharing.md) | Public repository exclusions and validated results packaging. |

R functions carry roxygen-style documentation directly above their definitions;
the project is a collection of sourced scripts, so roxygen2 is not required.
Python maintainer APIs use Google-style docstrings. The nested agent-tool
descriptions are also part of the actual experimental prompts: changing them
changes what the model receives.

## Repository map

| Directory | Contents |
|:---|:---|
| `R/` | Simulation, sample-size planning, scoring, contracts, Docker execution, and pipeline. |
| `agents/` | PydanticAI sessions, typed tools, artifact handling, references, and API transport. |
| `prompts/` | Current system prompt and shared instructions. |
| `config/` | Scenario grid, model ID, and resource budgets. |
| `docker/` | Restricted R runtime and pinned package installer. |
| `references/agent-pack/` | Curated brief, reference summaries, approved excerpts, and their catalog. |
| `scripts/` | Setup, checks, run/report entry points, and results packaging. |
| `analyses/` | Post-run comparisons and report builders; these require saved results. |
| `reports/` | R Markdown templates, including a portable shared-results summary. |
| `docs/` | Architecture, isolation, prompt revisions, and sharing guides. |
| `tests/`, `fixtures/` | Offline software checks and deterministic fixture analyses. |

Generated `results/`, `deliverables/`, and `exports/` directories stay local and
are ignored by Git. Full source PDFs, the internal research proposal, credentials,
R data files, environments, and machine-specific Docker manifests are also ignored.
The committed curated reference pack is sufficient to run the current agents;
rebuilding its excerpts requires separately obtained source PDFs.

## Shared results

The original run is `results/live-first`; the revised run is
`results/live-revised-20261101`. They use the same generated observations.
Saved results are distributed separately from this code repository. To build the
review bundle from both completed local runs:

```sh
Rscript --vanilla scripts/build_results_bundle.R
```

Open the ZIP's `README.html` first. It explains the summary, both runs, frozen
analyses, exploratory code, audit records, baseline results, and omitted files.
The bundle contains no input matrices, private simulation RDS files, credentials,
or full PDFs. It supports inspection and summary rendering; it is not an exact
execution archive. See [the sharing guide](docs/sharing.md).

## Setup

Run commands from this directory. Requirements: R 4.6.0, Python 3.12 or 3.13,
Poetry, Docker Desktop, and Pandoc (also supplied by RStudio).

```sh
poetry install
Rscript --vanilla scripts/setup.R
Rscript --vanilla scripts/build_image.R
```

`poetry.lock` fixes Python dependencies. `renv.lock` fixes host R dependencies.
To restore the latter into the project library, run
`Rscript --vanilla scripts/setup.R --restore`. The Docker base image and agent
package versions are pinned separately in `docker/Dockerfile` and
`docker/install.R`. Every run records and executes the resolved image digest.

The controller privately reads only the `OPENAI_API_KEY` assignment from `.env`
at runtime, as authorized. An exported key takes precedence. Values are never
printed, shell-sourced, copied into results, or passed to agent containers. Other
assignments are ignored. `.env.example` names the expected variable. The Docker
build context excludes `.env` and contains only explicitly allowlisted runtime
files, the statistical contract, and the package installer.

## Verify before a live run

```sh
poetry run pytest -q
Rscript --vanilla scripts/test.R
Rscript --vanilla scripts/preflight.R --offline
Rscript --vanilla scripts/test_sandbox.R
Rscript --vanilla scripts/run_pilot.R --dry-run
Rscript --vanilla scripts/run_pilot.R --offline --run-dir results/offline-demo
```

The offline run exercises real PydanticAI agents and their tools with a
deterministic `FunctionModel` provider. Its statistical scripts are fixtures,
not OpenAI-generated designs. It still uses isolated Docker containers. There
is no host-execution fallback for generated R code.

The report labels fixture outputs explicitly. It is a software validation run,
not evidence about the quality of a live model's scientific designs.

## Live run

The requested GPT-6.1 model is configured as `gpt-6.1-sol` in `config/pilot.yml`.
Model access is checked by the API; no substitute is chosen automatically.

The existing local `.env` can supply `OPENAI_API_KEY` privately:

```sh
Rscript --vanilla scripts/preflight.R
Rscript --vanilla scripts/run_pilot.R --run-dir results/my-live-run
```

Alternatively, export `OPENAI_API_KEY`. In zsh, the following reads it without
displaying it or placing the value in a command:

```sh
read -rs 'OPENAI_API_KEY?OpenAI API key: '
export OPENAI_API_KEY
Rscript --vanilla scripts/preflight.R
Rscript --vanilla scripts/run_pilot.R --run-dir results/my-live-run
```

No API requests occur during dry-run, offline execution, tests, or report
regeneration. A live run with neither an exported key nor a local `.env` key fails
before starting agents.
Only agent-visible synthetic observations, task instructions, the curated brief,
requested reference sections, and agent tool results are sent to OpenAI;
the truth, generator code, planning parameters, and other agents' histories are
not included.

```sh
Rscript --vanilla scripts/run_pilot.R --resume --run-dir results/my-live-run
Rscript --vanilla scripts/render_report.R --run-dir results/my-live-run
```

Resume requires the same config, implementation, mode, prompts, and image digest.
Valid frozen designs are reused. Failed sessions can be retried; completed
frozen designs are never overwritten. Use a new run directory for changed inputs.
The implementation fingerprint hashes source bytes, including source comments
and docstrings. Consequently this documentation update also changes resume/cache
identity: inspect historical results as saved, or use their original code checkout
when resuming them. No historical artifacts or scores were modified.

To inspect one setting, add e.g. `--scenario fwer_m20_c20`. The default selects
all eight. `--config <file>` selects another config while preserving the
one-iteration/no-validation requirements.

## Statistical specification

- Draw the three-subgroup state per coordinate with P(000)=0.6, P(111)=0.1,
  and probability 0.05 for each other state.
- Conditional nonzero effects are independent absolute N(1,1) draws.
- Samples are normal with identity covariance. Each of the three agents gets
  an independent exposed sample and its own independent control: 6n observations.
- Find the smallest n >= 1 for which all three average nonzero-effect powers
  strictly exceed c using the PDF's one-sided alpha/m threshold.
- Agent testing uses alpha/3, where alpha=0.05.
- FWER settings: m=20,100; FDR settings: m=100,1000; c=0.2,0.6.
- Matching m=100 data are reused for the two criteria, with separate sessions.
- Freeze all three designs before transfer: 1→2, 2→3, 3→1.
- A false directional claim includes a zero target effect or the wrong sign.
- Score power over all nonzero target coordinates, not just selected coordinates.

An empty-signal subgroup makes the specified planning power undefined; record
the failure without redrawing. n=1 is preserved. `max_n` and
`max_dataset_cells` are explicit resource safeguards, not changes to the generator.

The baselines test both directions for every coordinate: Welch t-tests and a
known-variance z reference, with Holm for FWER over 2m hypotheses. The updated
configuration uses BH as the primary FDR correction and BY as a secondary
reference. New FDR method IDs include `_bh` or `_by`. The original saved experiment
used BY; those results and their reports have not been changed.
The z reference uses variance information deliberately withheld from the agents.

With one iteration, the report gives realized FDP, false-discovery indicators,
and power. **These are not estimates of FWER or FDR.** Failed procedures do not
become zero-discovery successes, and incomplete families have no global score.

## Agent contract and limits

The exact shared prompts are in `prompts/system.txt` and `prompts/developer.txt`;
the criterion/dimension template is in `agents/prompts.py`. All agents get the
same statistical instructions and differ only in their own input and objective.

PydanticAI exposes `run_r`, `read_reference`, `write_artifact_file`, `check_design`, and the typed
`finalize_design` output tool. Agents own their hypothesis selection, p-value
method, and complete multiplicity procedure. The harness validates structure
and measures outcomes; it does not certify or replace their statistical method.

The matrix structure is documented in `run_r`, rather than a repeated formal-null
block in the shared instructions. Direction encoding remains explicit in the CSV
contract. A shared curated methods brief is injected into each session; approved
paper sections can be retrieved on demand using `read_reference`. Only a sanitized
summary of the research proposal is available to agents. Original PDFs, generator
details, and prior run results are not exposed through the library.

See `docs/prompt-revision.md` for the revised choices, reference provenance, cache
identity, and rebuild command. Changed prompts or references require a new run
directory; the existing `results/live-first` is an immutable record of the old run.

The R interface is `analyze(exposed, unexposed, hypotheses, alpha)`, returning
one row per frozen hypothesis with `hypothesis_id`, raw `p_value`, logical
`reject`, and `adjusted_p_value` (or numeric NA). Empty selections are valid.

Default limits: 16 physical API attempts/session, 12 exploratory R calls,
32 successful tool calls, two contract repairs, 8,192 output tokens/response,
32 KiB tool output, 120-second API timeout, and 60 seconds/2 GiB/one CPU per R
execution. Provider SDK retries are disabled; a counted transport bounds retries.

## Files and boundaries

See `docs/isolation.md` for the trust model. Main entry points are
`scripts/run_pilot.R` and `agents/session.py`. Results include:

- `run.json`, `scenarios.csv`, `planning.csv`, and `R-session.txt`.
- Private simulation RDS files, retained only on the trusted host.
- Per-agent prompts, conversations, tool logs, frozen artifacts, and hashes.
- Per-hypothesis target results and baseline CSVs.
- `scores.csv`, `global-scores.csv`, `usage.csv`, `power.png`, `report.html`.

Start with preflight and the offline run. A complete live run requires a working
Docker daemon, network access to OpenAI, valid credentials, and model access.
