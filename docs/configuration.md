# Configuration and commands

Run CLI commands from the repository root. `R/bootstrap.R` can resolve an explicit
root from `CROSS_SCREENING_ROOT`, but several entry-point paths are relative to
the working directory. [README setup](../README.md#setup) lists prerequisites.

## YAML fields

The current configuration is [`config/pilot.yml`](../config/pilot.yml).
`validate_config()` intentionally supports the fixed first-run experiment, not
an arbitrary simulation grid. Unknown YAML fields are not comprehensively rejected;
do not infer that an unused setting changes behavior.

| Field | Current value | Purpose and implementation |
|:---|:---|:---|
| `seed` | `20261016` | Master scientific RNG seed; source execution seeds and model output are separate. |
| `alpha` | `0.05` | Overall level; planning uses `alpha/m`, each target family receives `alpha/3`. |
| `iterations_per_scenario` | `1` | Validator requires exactly one. |
| `additional_validation_draws` | `0` | Validator requires zero; there is no repeated validation stage. |
| `reference_pack` | `references/agent-pack` | Approved curated library; relative to project root unless absolute. |
| `baseline_fdr_methods` | `[BH, BY]` | Requested full Welch/oracle FDR variants. If absent, historical default is BY. |
| `measurements` | `[20, 100, 1000]` | Validator requires these values; criterion-specific filtering creates eight scenarios. |
| `power_targets` | `[0.2, 0.6]` | Validator requires these values; `c` denotes a planning power target. |
| `delta` | `1` | Normal mean before taking the absolute nonzero-effect draw. |
| `tau_squared` | `1` | Variance of that normal draw; must be positive. |
| `state_probabilities` | `000: .60`, `111: .10`, others `.05` | Named probabilities for all eight subgroup-presence patterns; sum to one. |
| `max_n` | `100000` | Planning search ceiling; failure is recorded rather than silently changing the design. |
| `max_dataset_cells` | `20000000` | Reject a setting when `6*n*m` exceeds this memory safeguard. |
| `results_directory` | `results` | Parent for automatically timestamped run directories. |
| `openai.model` | `gpt-6.1-sol` | Explicit provider ID; no model substitution. Access depends on the runtime account. |
| `openai.max_output_tokens` | `8192` | Maximum response output passed to PydanticAI model settings. |
| `openai.request_limit` | `16` | Bounds model-loop requests and, independently, total physical API attempts. |
| `openai.api_timeout_seconds` | `120` | Client request timeout. |
| `openai.transient_retries` | `2` | Extra transport attempts per request, still bounded by the session limit. |
| `agent.max_r_executions` | `12` | Number of exploratory `run_r` calls, including ones that fail after submission. |
| `agent.max_contract_repairs` | `2` | Shared counted allowance for failed contract/current-artifact finalization checks. |
| `agent.tool_calls_limit` | `32` | PydanticAI tool-call limit; reference retrieval uses this budget too. |
| `agent.max_tool_output_bytes` | `32768` | Recorded/intended output budget; wrapper currently applies a hard-coded 32 KiB per captured stream. Changing this field alone does not alter the cap. |
| `sandbox.image` | `cross-screening-r:4.6.0` | Locally built tag, resolved to an immutable image ID before running. |
| `sandbox.timeout_seconds` | `60` | Per-container wall time; output above 1 MiB combined also terminates the process. |
| `sandbox.memory` | `2g` | Docker memory limit. |
| `sandbox.cpus` | `1` | Docker CPU quota. |

Other fixed limits live in code: 128 KiB submitted exploration source, 256 KiB per
artifact, 2 MiB result CSV, 128 container processes, and a 128 MiB temporary mount.
PydanticAI tool/output retry configuration is distinct from the counted scientific
contract-repair budget. See source and [tool contracts](agent-api.md).

## Experiment entry point

```sh
Rscript --vanilla scripts/run_pilot.R [options]
```

| Option | Default | Effect |
|:---|:---|:---|
| `--config FILE` | `config/pilot.yml` | Load and validate YAML. |
| `--scenario ID` | All eight | Select an exact ID, e.g. `fwer_m20_c20`; unknown IDs fail. |
| `--run-dir DIR` | Timestamp under `results_directory` | Destination; existing directories require compatible `--resume`. |
| `--offline` | Live | Use fixture provider/artifacts; Docker is still required. |
| `--dry-run` | Off | Print scenarios/session count and return before credentials, Docker or data generation. |
| `--resume` | Off | Require matching run signature, reuse verified cached designs, and retry unfinished sessions. |

The scripts parse known flags with small explicit helpers rather than a general
CLI parser; there is no `--help` implementation or strict rejection of unknown
flags. Use the documented spellings. A nonzero final exit can accompany a report:
the pipeline writes failure rows and completion metadata before reporting failure.

Resume is not an extension to additional iterations. It verifies source bytes,
configuration, selected scenarios, mode, image, prompts, and references. Changes
to comments/docstrings also change this signature. A compatible resume reuses
successful designs; target evaluations and reports can be recomputed from the
same saved data. Do not use it to let agents redesign after seeing target results.

## Supporting commands

| Command | Inputs and outputs | Services required |
|:---|:---|:---|
| `poetry install` | Restores Python dependencies from lockfile. | Package network, no model. |
| `Rscript --vanilla scripts/setup.R --restore` | Restores host R lockfile; default setup instead installs missing packages and snapshots. | Package network. |
| `Rscript --vanilla scripts/build_image.R` | Builds restricted image; writes ignored local image metadata. | Docker and build network. |
| `Rscript --vanilla scripts/preflight.R --offline` | Checks host libraries, Pandoc, references, local Docker image, and Poetry imports. | Docker image inspect; no model. |
| `Rscript --vanilla scripts/preflight.R` | Same checks plus explicit model ID and credential availability. This script does not verify model access over the network. | Local runtime key availability. |
| `poetry run python -m agents.credentials --verify-model MODEL` | Optional actual provider access check; does not send observations. | OpenAI/network and runtime key. |
| `Rscript --vanilla scripts/test.R` | Runs host R tests. | No OpenAI or Docker execution. |
| `poetry run pytest -q` | Runs deterministic Python tests. | No OpenAI calls. |
| `Rscript --vanilla scripts/test_sandbox.R` | Runs mount/network/credential/timeout canaries; writes ignored isolation metadata. | Working Docker image/daemon. |
| `Rscript --vanilla scripts/render_report.R --run-dir DIR` | Renders saved full report; requires private setting RDS files. | Pandoc, no model. |
| `Rscript --vanilla scripts/export_exploration.R --run-dir DIR` | Exports existing audit requests to exact `.R` files and an index. | No model or agent-code execution. |
| `poetry run python -m agents.prompts --output FILE` | Writes a current prompt review copy. | No model or key loader. |
| `Rscript --vanilla scripts/build_results_bundle.R --output-dir DIR` | Builds new directory/ZIP from both saved live runs; refuses existing destinations. | Saved results, Pandoc; no model. |
| `Rscript --vanilla scripts/check_public_files.R` | Inspects staged Git blobs and prohibited paths. | Local Git, no key loader. |

For an end-to-end software smoke test, use a new destination:

```sh
Rscript --vanilla scripts/run_pilot.R --dry-run
Rscript --vanilla scripts/run_pilot.R --offline --scenario fwer_m20_c20 --run-dir results/offline-demo
```

For a live experiment, export a runtime key using the README's hidden-input
example, confirm account/model access as needed, then omit `--offline`. Live mode
can incur API usage. Never put credentials in YAML, prompts, command arguments,
or results. The existing application can use its authorized private loader;
documentation and publication checks do not read `.env`.

## Historical reporting utilities

`analyses/summarize_revised_run.R` accepts `--original-dir` and `--run-dir` and
requires both runs' private datasets to verify equality and directional coverage.
It is different from the shared portable summary, which reads included CSVs only.
`analyses/compare_welch.R` targets the original run and writes a separate method
comparison. Legacy Word/R Markdown builders require those comparison outputs.
These utilities are documented individually in the [R reference](r-api.md).

The narrow `analyses/retry_gateway_session.R` accepts `--run-dir`, `--scenario`,
and `--source`. It requires the exact historical HTTP 520 failure, an already
archived matching audit, no frozen design, and an unchanged implementation. It
can incur live API usage and update that failed result. It should not be used as
a generic retry or as a way to change completed designs.
