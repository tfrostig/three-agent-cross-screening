# R function reference

Source documentation is authoritative. This is a sourced-script project; roxygen2 is not required. See the [developer walkthrough](developer-guide.md) and [pooled-selection guide](pooled-selection.md).

## `R/bootstrap.R`

## `R/config.R`

### `r_packages`

List the host-side R dependencies

[Source](../R/config.R)


**Returns / effects:** Character vector of package names.

### `load_config`

Read and validate a pilot YAML configuration

[Source](../R/config.R)

- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Validated configuration list; invalid settings raise an error.

### `validate_config`

Enforce the fixed pilot grid and one-iteration contract

[Source](../R/config.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.

**Returns / effects:** The configuration invisibly; stops on unsupported settings.

### `%||%`

Substitute a default only for NULL

[Source](../R/config.R)

- `value`: Any R value; only NULL triggers the fallback.
- `default`: Fallback returned when the requested value is absent.

**Returns / effects:** The supplied value or the default; NA and empty vectors are preserved.

### `scenario_grid`

Expand the permitted scenarios and shared dataset IDs

[Source](../R/config.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.

**Returns / effects:** Data frame with m, c, criterion, id, and data_id. Matching m=100 criteria share data_id.

### `require_packages`

Check dependencies without installing packages

[Source](../R/config.R)

- `packages`: Character vector of required R package names.

**Returns / effects:** NULL invisibly; stops with missing package names.

### `validate_live_config`

Check explicit model selection and private credential availability

[Source](../R/config.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.

**Returns / effects:** No scientific result; stops before agents start if configuration is unavailable.

## `R/contracts.R`

### `validate_matrices`

Validate the simulator's equal-shape finite matrix contract

[Source](../R/contracts.R)

- `exposed`: Numeric n by m exposed matrix with unique measurement column names.
- `unexposed`: Numeric n by m independent control matrix with the same dimensions and names.

**Returns / effects:** TRUE invisibly; stops on invalid matrices, names, dimensions, or values.

### `validate_hypotheses`

Validate a frozen directional hypothesis family

[Source](../R/contracts.R)

- `hypotheses`: Frozen table with hypothesis_id, measurement_id, and integer direction (-1 or +1).
- `measurements`: Character vector of valid measurement column names.

**Returns / effects:** TRUE invisibly; requires exact columns and unique measurement-direction pairs; empty families are valid.

### `validate_result`

Validate agent output against the frozen family

[Source](../R/contracts.R)

- `result`: Per-hypothesis table with hypothesis_id, p_value, reject, and adjusted_p_value.
- `hypotheses`: Frozen table with hypothesis_id, measurement_id, and integer direction (-1 or +1).

**Returns / effects:** TRUE invisibly; checks exact columns, IDs, logical decisions, and finite raw p-values in [0,1]. Does not certify statistical validity.

### `empty_result`

Construct the typed empty analysis result

[Source](../R/contracts.R)


**Returns / effects:** Zero-row data frame with hypothesis_id, p_value, reject, adjusted_p_value.

### `read_hypothesis_table`

Read the frozen CSV with explicit column types

[Source](../R/contracts.R)

- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Hypothesis data frame; direction is integer. Validation is a separate operation.

### `read_result_table`

Read per-hypothesis results with explicit column types

[Source](../R/contracts.R)

- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Result data frame; reject is logical. Validation is a separate operation.

## `R/designs.R`

### `write_pair`

Serialize one observation pair for a session-specific mount

[Source](../R/designs.R)

- `pair`: List with exposed and unexposed numeric observation matrices.
- `directory`: Filesystem directory holding the relevant inputs or outputs.

**Returns / effects:** Writes exposed.rds and unexposed.rds in directory; contains observations, never truth.

### `fixture_design`

Prepare deterministic R artifacts for an offline provider session

[Source](../R/designs.R)

- `pair`: List with exposed and unexposed numeric observation matrices.
- `workspace`: Session-specific mutable artifact directory.
- `criterion`: Character scalar FWER or FDR.

**Returns / effects:** Writes three work artifacts, explicitly labeled fixtures; does not call a model.

### `design_cache_key`

Bind cached designs to observations and execution identity

[Source](../R/designs.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `input_dir`: Directory containing only exposed.rds and unexposed.rds for this subgroup.
- `mode`: Execution mode or live/offline discriminator used by the caller.
- `image_id`: Resolved Docker image SHA-256 identifier.

**Returns / effects:** Hash of input bytes, criterion, levels, budgets, source, prompts, references, and image.

### `source_fingerprint`

Fingerprint implementation files used in strict resume checks

[Source](../R/designs.R)


**Returns / effects:** Hash covering R/Python scripts, fixtures, Docker source, prompts, and lockfiles. Documentation edits inside those source files also change it.

### `verify_frozen`

Verify each frozen artifact against its recorded content hash

[Source](../R/designs.R)

- `directory`: Filesystem directory holding the relevant inputs or outputs.

**Returns / effects:** TRUE invisibly; stops on a missing, unsafe, or changed artifact.

### `session_manifest`

Build host-private configuration for exactly one agent session

[Source](../R/designs.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `directory`: Filesystem directory holding the relevant inputs or outputs.
- `pair`: List with exposed and unexposed numeric observation matrices.
- `session_id`: Opaque identifier for a single source-agent session.

**Returns / effects:** List consumed by agents.session; includes source paths and task dimensions, not generator truth.

### `run_design`

Reuse a verified design or launch one isolated PydanticAI session

[Source](../R/designs.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `pair`: List with exposed and unexposed numeric observation matrices.
- `directory`: Filesystem directory holding the relevant inputs or outputs.
- `offline`: Logical; use deterministic fixture artifacts/provider instead of OpenAI.
- `image_id`: Resolved Docker image SHA-256 identifier.

**Returns / effects:** Session summary list. Writes source inputs, controller manifest, audit logs, and successful cache metadata; never overwrites an indexed frozen design.

## `R/imports.R`

### `setting_stream_ids`

Preserve the original six stream slots and append c=0.9 settings.

[Source](../R/imports.R)

- `config`: Validated experiment configuration.

**Returns / effects:** Ordered data IDs; stable for both supported grids.

### `print_run_plan`

Print planned imported/new design counts without Docker, credentials, or models.

[Source](../R/imports.R)

- `scenarios`: Selected scenario rows.
- `reuse_run`: Optional historical run directory; contents are verified during execution.

**Returns / effects:** Prints the plan, explicitly distinguishing artifacts from new sessions.

### `prepare_reuse`

Snapshot and validate a reuse source before any new sessions.

[Source](../R/imports.R)

- `config`: Current configuration with resolved Docker and reference identities.
- `path`: Optional saved run directory.
- `offline`: Whether the destination uses deterministic fixture sessions.

**Returns / effects:** NULL or provenance containing the source path, identity, and file hashes.

### `reuse_file`

Verify a snapshotted source file before importing it.

[Source](../R/imports.R)

- `config`: Destination configuration containing reuse provenance.
- `relative`: Source-run-relative path.

**Returns / effects:** Verified regular source file path, or NULL if absent from the source snapshot.

### `import_setting`

Copy an available historical dataset without reserializing it.

[Source](../R/imports.R)

- `config`: Destination configuration with optional reuse record.
- `data_id`: Measurement/power setting ID.
- `destination`: New private RDS path.

**Returns / effects:** TRUE if imported; FALSE if this setting requires generation.

### `copy_imported_session`

Copy approved historical session files with byte-integrity checks.

[Source](../R/imports.R)

- `config`: Configuration containing the source snapshot.
- `relative`: Source-run-relative agent directory.
- `directory`: New agent directory.

**Returns / effects:** NULL; creates input, frozen, and audit copies only.

### `import_design`

Recheck one imported design against its own source observations.

[Source](../R/imports.R)

- `config`: Current sandbox configuration.
- `scenario`: One scenario row.
- `pair`: Expected source observations from the imported setting.
- `directory`: Destination agent directory.
- `source`: Source subgroup number.

**Returns / effects:** Original successful session summary, with a separate import/check provenance file.

### `prepare_design`

Import an available source design or launch exactly one new session.

[Source](../R/imports.R)

- `config`: Validated configuration and optional reuse snapshot.
- `scenario`: One scenario record.
- `pair`: This source's observations only.
- `directory`: Destination source-agent directory.
- `source`: Source subgroup number.
- `offline`: Whether to use a fixture provider for new sessions.
- `image_id`: Resolved Docker image identity.

**Returns / effects:** Source session summary; imported sessions make no API calls.

## `R/io.R`

### `ensure_dir`

Create a directory and resolve its absolute path

[Source](../R/io.R)

- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Normalized existing directory path.

### `write_json`

Write controller metadata with stable JSON settings

[Source](../R/io.R)

- `value`: R value to serialize or hash.
- `path`: Destination JSON file; its parent directories are created.

**Returns / effects:** Writes UTF-8 JSON, creating parent directories; NULL and NA serialize as null.

### `read_json`

Read controller JSON with simplified vectors

[Source](../R/io.R)

- `path`: Existing controller-owned JSON file.

**Returns / effects:** Parsed R value from jsonlite; malformed input raises a parse error.

### `file_hash`

Hash a file's bytes for artifact integrity

[Source](../R/io.R)

- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** SHA-256 hexadecimal string; no content is interpreted.

### `object_hash`

Hash an R object for internal cache identity

[Source](../R/io.R)

- `value`: R value to serialize or hash.

**Returns / effects:** SHA-256 string based on R serialization, not a portable content-file checksum.

### `write_csv`

Write a results table with full numeric precision

[Source](../R/io.R)

- `value`: Data frame to serialize as a CSV table.
- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Writes CSV without row names, representing NA as empty cells; restores global digits afterward.

### `read_csv`

Read a results table without altering column names

[Source](../R/io.R)

- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Data frame with strings kept as character values.

### `cli_value`

Read the value following a named CLI option

[Source](../R/io.R)

- `args`: Character vector of command-line arguments.
- `name`: Named CLI flag, including its leading --.
- `default`: Fallback returned when the requested value is absent.

**Returns / effects:** Character option value or default; stops if a present option has no value.

### `timestamp`

Format the current instant for audit metadata

[Source](../R/io.R)


**Returns / effects:** UTC timestamp in ISO-like YYYY-MM-DDTHH:MM:SSZ form.

### `safe_file`

Require an existing regular artifact within its trusted root

[Source](../R/io.R)

- `path`: Existing artifact path to validate without following a linked final component.
- `root`: Existing trusted root that must contain the resolved regular file.

**Returns / effects:** Resolved path; rejects a linked final path, directories, or paths outside root.

### `atomic_rds`

Publish an RDS file through a same-directory temporary file

[Source](../R/io.R)

- `value`: R value to serialize or hash.
- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Writes path.partial and renames it to path; stops if publication fails.

## `R/metrics.R`

### `directional_family`

Enumerate both directional alternatives for every measurement

[Source](../R/metrics.R)

- `measurements`: Character vector of valid measurement column names.

**Returns / effects:** Data frame with 2m rows and stable _pos/_neg hypothesis IDs.

### `baseline_pvalues`

Calculate raw directional Welch or known-variance z p-values

[Source](../R/metrics.R)

- `exposed`: Numeric n by m exposed matrix with unique measurement column names.
- `unexposed`: Numeric n by m independent control matrix with the same dimensions and names.
- `hypotheses`: Frozen table with hypothesis_id, measurement_id, and integer direction (-1 or +1).
- `known_variance`: Logical; use the generator's unit population variance for an oracle z reference.

**Returns / effects:** Numeric vector aligned to hypotheses; Welch fails for fewer than two observations per arm.

### `baseline_analysis`

Test the full directional family with a specified correction

[Source](../R/metrics.R)

- `exposed`: Numeric n by m exposed matrix with unique measurement column names.
- `unexposed`: Numeric n by m independent control matrix with the same dimensions and names.
- `criterion`: Character scalar FWER or FDR.
- `alpha`: Family level used directly; callers supply config$alpha/3 for target testing.
- `known_variance`: Logical; use the generator's unit population variance for an oracle z reference.
- `fdr_method`: BH or BY; ignored for Holm FWER correction.

**Returns / effects:** List containing hypotheses and result. Uses Holm for FWER, the requested BH/BY for FDR.

### `score_claims`

Score frozen directional rejections using trusted target effects

[Source](../R/metrics.R)

- `hypotheses`: Frozen table with hypothesis_id, measurement_id, and integer direction (-1 or +1).
- `result`: Per-hypothesis table with hypothesis_id, p_value, reject, and adjusted_p_value.
- `effects`: A 3 by m effect matrix for generation/planning, or a named target-effect vector for scoring.

**Returns / effects:** One-row data frame of counts, FDP, any_false, and power. Zero or opposite-sign effects are false claims; power counts unique correct coordinates.

### `global_scores`

Combine successful target evaluations within scenario and method

[Source](../R/metrics.R)

- `scores`: Per-target scores.csv data frame including method, status, and discovery metrics.

**Returns / effects:** Data frame of totals. Global FDP/power require exactly three successful target rows; incomplete groups receive NA.

## `R/pipeline.R`

### `prepare_data`

Generate or reuse one trusted dataset per unique setting

[Source](../R/pipeline.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenarios`: Scenario-grid data frame, optionally filtered to one setting.
- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Data frame mapping data_id to private RDS paths. Matching criteria reuse observations; generation errors are stored without redrawing.

### `new_run`

Create a run record or enforce an identical resume signature

[Source](../R/pipeline.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.
- `offline`: Logical; use deterministic fixture artifacts/provider instead of OpenAI.
- `resume`: Logical; permit an existing run only if its full identity matches.
- `image_id`: Resolved Docker image SHA-256 identifier.
- `scenario_ids`: Ordered character vector of scenario identifiers included in the run.

**Returns / effects:** Absolute run path. Writes run.json and R-session.txt for a new run; refuses mismatched existing runs.

### `score_row`

Create a uniform success or failure row for scores.csv

[Source](../R/pipeline.R)

- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `method`: Method ID used in score tables.
- `source`: Source subgroup index (1, 2, or 3).
- `target`: Target subgroup index, or NA for a failure without a target.
- `status`: Execution status, normally ok or failed.
- `error`: Error condition or failure message, as indicated by the caller.
- `metrics`: One-row score_claims() result, or NULL to preserve missing metrics.
- `elapsed`: Elapsed seconds, or NA when unavailable.

**Returns / effects:** One-row data frame. Missing metrics remain NA rather than becoming zero discoveries.

### `evaluate_agent`

Apply a frozen source design to its independent target group

[Source](../R/pipeline.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `setting`: Trusted generated setting including observations, effects, and planning metadata.
- `directory`: Filesystem directory holding the relevant inputs or outputs.
- `source`: Source subgroup index (1, 2, or 3).
- `output_dir`: Directory receiving target CSVs and execution metadata.

**Returns / effects:** One score row after fresh-container execution; writes results and execution audit. Verifies artifact hashes before and after evaluation.

### `evaluate_baseline`

Evaluate one full-family baseline on one target group

[Source](../R/pipeline.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `setting`: Trusted generated setting including observations, effects, and planning metadata.
- `target`: Target subgroup index (1, 2, or 3); observations are never pooled.
- `output_dir`: Directory receiving target CSVs and execution metadata.
- `known`: Logical; select oracle z instead of Welch.
- `fdr_method`: BH or BY; ignored for Holm FWER correction.

**Returns / effects:** One success/failure score row; writes hypothesis and target-result CSVs without model calls.

### `evaluate_scenario_baselines`

Enumerate target groups and configured baseline variants

[Source](../R/pipeline.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `setting`: Trusted generated setting including observations, effects, and planning metadata.
- `output_dir`: Directory receiving target CSVs and execution metadata.

**Returns / effects:** List of score rows for Welch and oracle z, including both configured FDR corrections.

### `scenario_designs`

Finish all three source sessions before target execution

[Source](../R/pipeline.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `setting`: Trusted generated setting including observations, effects, and planning metadata.
- `scenario_dir`: Directory for this scenario's three source-agent sessions.
- `offline`: Logical; use deterministic fixture artifacts/provider instead of OpenAI.
- `image_id`: Resolved Docker image SHA-256 identifier.

**Returns / effects:** List of three session summaries, retaining failures for later scoring.

### `run_scenario`

Execute one complete freeze-then-transfer cycle

[Source](../R/pipeline.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `setting`: Trusted generated setting including observations, effects, and planning metadata.
- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.
- `offline`: Logical; use deterministic fixture artifacts/provider instead of OpenAI.
- `image_id`: Resolved Docker image SHA-256 identifier.

**Returns / effects:** Score data frame for all agents and baselines; records generation/design/evaluation failures explicitly.

### `run_pilot`

Coordinate the configured one-iteration experiment

[Source](../R/pipeline.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `options`: List with offline, dry_run, resume, run_dir, and scenario CLI settings.

**Returns / effects:** Run directory invisibly on success; writes datasets, designs, incremental scores and report. Stops after reporting if any evaluation failed.

## `R/references.R`

### `reference_pack_path`

Resolve the curated reference library configured for the run

[Source](../R/references.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.

**Returns / effects:** Absolute existing pack path, defaulting to references/agent-pack.

### `reference_pack_digest`

Verify approved payload hashes and lock the catalog identity

[Source](../R/references.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.

**Returns / effects:** SHA-256 catalog hash; stops on traversal, stale payloads, or mid-run digest changes.

### `reference_pack_record`

Record the reference path and verified catalog identity

[Source](../R/references.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.

**Returns / effects:** List with path and digest for cache/run provenance.

## `R/report.R`

### `escape_html`

Escape report text for safe HTML insertion

[Source](../R/report.R)

- `text`: Character text to escape, sanitize, or write.

**Returns / effects:** Character vector with HTML-sensitive characters encoded.

### `planning_table`

Summarize sample-size minimality from trusted saved settings

[Source](../R/report.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Data frame of n, power at n and n-1, and subgroup signal counts; failed settings are omitted.

### `agent_reports`

Read scientific explanations from frozen designs only

[Source](../R/report.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** List of report labels/text; never reads mutable workspace drafts.

### `session_usage`

Collect retained session usage and duration records

[Source](../R/report.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Data frame for reporting. Missing usage fields default to zero; failed-attempt usage may be incomplete.

### `save_report_plots`

Plot successful per-target realized power

[Source](../R/report.R)

- `scores`: Per-target scores.csv data frame including method, status, and discovery metrics.
- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Writes power.png; returns invisibly without a plot if no evaluations succeeded.

### `render_pilot_report`

Rebuild the full HTML report from saved local results

[Source](../R/report.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Writes report.html, planning.csv, usage.csv, power.png, and render intermediates. Requires private setting files but makes no model calls.

## `R/sandbox.R`

### `docker_info`

Resolve a locally available Docker image to its immutable ID

[Source](../R/sandbox.R)

- `image`: Docker image tag or immutable image identifier.

**Returns / effects:** Image SHA-256 identifier; stops if Docker cannot inspect the image.

### `mount_arg`

Build a validated Docker bind-mount argument

[Source](../R/sandbox.R)

- `source`: Existing host directory to bind into the container.
- `target`: Absolute container mount path.
- `readonly`: Logical; append Docker's read-only mount option when TRUE.

**Returns / effects:** Two CLI arguments; rejects source paths containing commas.

### `sandbox_args`

Construct the restricted R-container invocation

[Source](../R/sandbox.R)

- `request`: Trusted request list with mode, input_dir, workspace, alpha, execution_seed, and sandbox settings.
- `stage`: Temporary directory containing only code or staged analysis artifacts.
- `output`: Destination directory or file, as indicated in the description.
- `name`: Unique Docker container name for this execution.

**Returns / effects:** Character vector of Docker arguments with mounts, resource limits, no network, and a non-root user.

### `prepare_stage`

Stage exploration code or the two executable design files

[Source](../R/sandbox.R)

- `request`: Trusted request list with mode, input_dir, workspace, alpha, execution_seed, and sandbox settings.
- `stage`: Temporary directory containing only code or staged analysis artifacts.

**Returns / effects:** Writes read-only files in stage; report text and host-private files are never staged.

### `bounded_text`

Read at most a fixed number of captured output bytes

[Source](../R/sandbox.R)

- `path`: Input or destination filesystem path, as indicated in the description.
- `limit`: Maximum number of output bytes to read.

**Returns / effects:** Character output, or an empty string for a missing file.

### `run_container`

Run Docker with wall-time and output-volume safeguards

[Source](../R/sandbox.R)

- `args`: Docker CLI arguments from sandbox_args().
- `timeout`: Maximum permitted wall-clock seconds.
- `directory`: Filesystem directory holding the relevant inputs or outputs.
- `name`: Unique container name used for forced removal at resource limits.

**Returns / effects:** List containing exit_code, timed_out, bounded stdout/stderr, and truncated. timed_out also marks the combined-output ceiling.

### `execute_sandbox`

Stage, execute, and validate one untrusted R request

[Source](../R/sandbox.R)

- `request`: Trusted request list with mode, input_dir, workspace, alpha, execution_seed, and sandbox settings.

**Returns / effects:** Bounded execution metadata; optionally publishes a validated result CSV. Temporary stage/output directories are removed on exit.

## `R/selection.R`

### `pool_non_target`

Pool only the two non-target observation pairs.

[Source](../R/selection.R)

- `observations`: List of three exposed/control pairs.
- `target`: Held-out study index.

**Returns / effects:** Exposed/control matrices with aligned columns and 2n rows per arm.

### `choose_candidate`

Choose the most discoveries, breaking ties by smaller source index.

[Source](../R/selection.R)

- `candidates`: Table containing source, status, and discoveries.

**Returns / effects:** Selection record; failed candidates are excluded rather than scored zero.

### `execute_frozen_pair`

Run one fixed analysis on a supplied pair and record reusable result integrity.

[Source](../R/selection.R)

- `config`: Sandbox and testing-level configuration.
- `pair`: Observations for either pooled selection or held-out testing.
- `frozen`: Verified frozen design directory.
- `prefix`: Output file prefix identifying purpose, target, and source.

**Returns / effects:** Result, hypotheses, artifact/result hashes, and cache identity.

### `evaluate_candidate`

Evaluate a candidate without making any truth-based selection decisions.

[Source](../R/selection.R)

- `config`: Testing and sandbox configuration.
- `pair`: Pooled non-target observations only.
- `directory`: Scenario directory.
- `source`: Candidate source index.
- `target`: Held-out index, used solely for filenames and routing.

**Returns / effects:** Audit row with a unique-measurement count and directional-conflict count.

### `reuse_target_result`

Reuse an identical historical held-out result after verifying its source snapshot.

[Source](../R/selection.R)

- `config`: Destination configuration with optional historical snapshot.
- `scenario`: Scenario row.
- `source`: Source index.
- `target`: Held-out index.
- `prefix`: New evaluation prefix.

**Returns / effects:** TRUE if copied, otherwise FALSE; only the archived cyclic route is available.

### `evaluate_selected_target`

Evaluate or reuse a held-out source/target pair and create ledger and score rows.

[Source](../R/selection.R)

- `config`: Current execution configuration.
- `scenario`: Scenario row.
- `setting`: Trusted setting; effects are used only after analysis finishes.
- `directory`: Scenario directory.
- `source`: Selected or cyclic source index; NA denotes failed selection.
- `target`: Held-out study index.
- `method`: agent_pooled_select or agent_cycle.

**Returns / effects:** List with a directional score and an evaluation-ledger row.

### `selected_baselines`

Evaluate full-family baselines and expose their outputs in the common ledger.

[Source](../R/selection.R)

- `config`: Baseline configuration.
- `scenario`: Scenario row.
- `setting`: Trusted setting.
- `directory`: Scenario directory.

**Returns / effects:** List of score data frame and ledger data frame.

### `run_selected_scenario`

Run pooled selection for all targets and retain the cyclic comparison.

[Source](../R/selection.R)

- `config`: Current configuration.
- `scenario`: Scenario row.
- `setting`: Trusted setting; truth is excluded from candidate evaluations.
- `directory`: Scenario directory with three completed source attempts.
- `designs`: Source attempt summaries, retained by the caller for audit.

**Returns / effects:** Directional score rows; writes candidate, decision, and evaluation ledgers.

## `R/simulation.R`

### `seed_streams`

Allocate independent L'Ecuyer-CMRG random-number streams

[Source](../R/simulation.R)

- `seed`: Integer master simulation seed.
- `count`: Number of independent RNG streams to allocate.

**Returns / effects:** List of RNG states. Sets the process RNG kind and initial state.

### `with_stream`

Evaluate an operation under a supplied RNG state

[Source](../R/simulation.R)

- `stream`: One saved L'Ecuyer-CMRG RNG state.
- `operation`: Zero-argument function evaluated under the supplied RNG state.

**Returns / effects:** The operation's result; restores the prior .Random.seed on exit.

### `draw_states`

Sample shared three-subgroup signal-presence patterns

[Source](../R/simulation.R)

- `m`: Number of measurement columns.
- `probabilities`: Named probabilities for the eight three-subgroup bit patterns.

**Returns / effects:** A 3 by m integer matrix of zero/one indicators.

### `draw_effects`

Generate positive effect magnitudes for active states

[Source](../R/simulation.R)

- `states`: A 3 by m zero/one signal-presence matrix.
- `delta`: Mean of the normal draw before taking its absolute value.
- `tau_squared`: Variance of the normal draw before taking its absolute value.

**Returns / effects:** A 3 by m numeric effect matrix; inactive entries remain zero.

### `planning_power`

Evaluate the specified known-variance planning formula

[Source](../R/simulation.R)

- `n`: Number of independent observations per exposed/control arm in each subgroup.
- `effects`: A 3 by m effect matrix for generation/planning, or a named target-effect vector for scoring.
- `alpha`: Overall planning level; the formula internally uses alpha/m, not the target-testing alpha/3.

**Returns / effects:** Three average powers over positive effects, with NA for an empty-signal subgroup.

### `smallest_sample`

Find the smallest integer n passing all subgroup power targets

[Source](../R/simulation.R)

- `effects`: A 3 by m effect matrix for generation/planning, or a named target-effect vector for scoring.
- `target`: Planning power target c.
- `alpha`: Overall planning level passed to planning_power(), which applies alpha/m.
- `max_n`: Largest permitted integer sample size.

**Returns / effects:** List with n, power at n, and previous_power at n-1 (NULL for n=1). Stops on empty signals or the resource ceiling.

### `draw_observations`

Generate independent exposed and control matrices for each subgroup

[Source](../R/simulation.R)

- `n`: Number of independent observations per exposed/control arm in each subgroup.
- `effects`: A 3 by m effect matrix for generation/planning, or a named target-effect vector for scoring.

**Returns / effects:** List of three pairs; each named matrix is n by m, with identity population covariance.

### `generate_setting`

Generate one reusable setting using separate state, effect, and data streams

[Source](../R/simulation.R)

- `config`: Validated configuration list from load_config(), unless a SessionConfig is explicitly noted.
- `m`: Number of measurement columns.
- `target`: Planning power target c.
- `streams`: Three saved RNG states for states, effects, and observations, in that order.

**Returns / effects:** List containing states, effects, planning, observations, streams, m, and target; stops on resource limits.

## `R/study_metrics.R`

### `discovered_measurements`

Collapse directional rejections into one claim per measurement per study.

[Source](../R/study_metrics.R)

- `hypotheses`: Frozen directional family.
- `result`: Validated per-hypothesis output.

**Returns / effects:** Character vector of discovered measurement IDs, without duplicates.

### `study_count_scores`

Evaluate all measurements under the count-only recovery definition.

[Source](../R/study_metrics.R)

- `effects`: Three-by-m truth matrix with measurement column names.
- `claims`: List of three measurement-ID vectors, or NULL for missing target outputs.

**Returns / effects:** Per-measurement counts, credit, and overclaim indicators; incomplete credit is NA.

### `summarize_study_counts`

Summarize recovery with equal weight for every nonnull measurement.

[Source](../R/study_metrics.R)

- `table`: Per-measurement output from study_count_scores().

**Returns / effects:** One-row summary; all-null measurements are excluded, and incomplete methods are NA.

### `score_study_ledger`

Score a method across held-out studies using the saved evaluation ledger.

[Source](../R/study_metrics.R)

- `setting`: Host-private generated setting.
- `ledger`: Three target records with status and artifact/result file paths.
- `directory`: Scenario directory against which ledger paths are resolved.

**Returns / effects:** Per-measurement table; missing or failed target records remain missing.

### `write_run_summaries`

Write primary recovery and secondary directional summaries for a completed run.

[Source](../R/study_metrics.R)

- `scores`: Per-target directional scores.
- `run_dir`: Run directory with scenario ledgers and private settings.

**Returns / effects:** Writes global-scores.csv and, for pooled runs, study-count summaries/tables.

## `R/study_report.R`

### `collect_scenario_tables`

Collect selection ledgers without treating their counts as confirmed discoveries.

[Source](../R/study_report.R)

- `run_dir`: Saved pooled-selection run.
- `filename`: Scenario-relative CSV filename.

**Returns / effects:** Combined data frame with a scenario identifier.

### `plot_study_recovery`

Plot primary recovery rather than conventional directional power.

[Source](../R/study_report.R)

- `counts`: Scenario/method count-recovery table.
- `run_dir`: Destination run directory.

**Returns / effects:** Writes study-count-recovery.png using complete method rows.

### `render_study_report`

Render both full and portable concise reports from saved output only.

[Source](../R/study_report.R)

- `run_dir`: Completed or failed pooled-selection run.

**Returns / effects:** Writes report.html, summary.Rmd/html/md, usage, planning, and recovery plot.

## `scripts/agent_tool.R`

## `scripts/build_image.R`

## `scripts/build_reference_pack.R`

### `reference_entry`

Describe the provenance and permitted sections of one reference

[Source](../scripts/build_reference_pack.R)

- `id`: Stable reference or section identifier.
- `source`: Source PDF filename relative to references/.
- `citation`: Bibliographic citation text.
- `pages`: Human-readable PDF page locator.
- `excerpts`: List of explicitly approved excerpt specifications.

**Returns / effects:** List used only by the trusted-host library build script.

### `excerpt_spec`

Specify PDF pages, text boundaries, and optional crop for an excerpt

[Source](../scripts/build_reference_pack.R)

- `id`: Stable reference or section identifier.
- `first`: First PDF page to extract (one-based).
- `last`: Last PDF page to extract (one-based).
- `start`: Literal opening text marker.
- `finish`: Literal closing text marker, included in the returned excerpt.
- `crop`: Optional PDF crop coordinates passed to pdftotext (-x, -y, -W, -H).

**Returns / effects:** Named extraction specification list.

### `reference_entries`

Declare the seven approved methodological references

[Source](../scripts/build_reference_pack.R)


**Returns / effects:** List of citation/source/extraction specifications, including a summary-only proposal entry.

### `extract_reference_excerpt`

Extract one bounded PDF passage on the trusted host

[Source](../scripts/build_reference_pack.R)

- `source`: Full source PDF path; read only by the trusted-host extraction process.
- `spec`: Named excerpt specification from excerpt_spec().

**Returns / effects:** Normalized text between explicit markers; requires pdftotext and stops on missing boundaries.

### `build_reference_entry`

Build approved excerpt files and provenance for one reference

[Source](../scripts/build_reference_pack.R)

- `entry`: One reference provenance/extraction record.
- `root`: Trusted containing directory used for path validation.

**Returns / effects:** Catalog entry with citation, source PDF hash, and named sections; writes extracted text only.

### `build_reference_pack`

Rebuild and hash the curated pack from separately available PDFs

[Source](../scripts/build_reference_pack.R)


**Returns / effects:** Writes catalog.json and approved excerpts; checks size limits and reports the verified digest.

## `scripts/build_results_bundle.R`

### `bundle_run_files`

Select reviewable results through an explicit path allowlist

[Source](../scripts/build_results_bundle.R)

- `directory`: Filesystem directory holding the relevant inputs or outputs.

**Returns / effects:** Sorted relative filenames; excludes input, private, work, controller logs, and caches.

### `bundle_copy_run`

Copy one completed live run into an export tree

[Source](../scripts/build_results_bundle.R)

- `name`: Saved live-run folder name, relative to results/.
- `output`: Destination directory or file, as indicated in the description.

**Returns / effects:** Manifest records for copied files; local paths may be sanitized except in immutable artifacts.

### `bundle_check_run`

Verify frozen hashes, exploration exports, and successful scores

[Source](../scripts/build_results_bundle.R)

- `directory`: Filesystem directory holding the relevant inputs or outputs.

**Returns / effects:** No result value; stops unless the saved run has eight scenarios and 24 successful designs.

### `bundle_extra_files`

Copy the methodology and approved reference context

[Source](../scripts/build_results_bundle.R)

- `output`: Destination directory or file, as indicated in the description.

**Returns / effects:** Manifest records for methods documents, current prompts, and curated library files.

### `bundle_examples`

Write editorial descriptions linking two actual revised designs

[Source](../scripts/build_results_bundle.R)

- `output`: Destination directory or file, as indicated in the description.

**Returns / effects:** Creates examples/README.md; agent explanations themselves remain in frozen reports.

### `bundle_render`

Render the reading guide and portable saved-results summary

[Source](../scripts/build_results_bundle.R)

- `output`: Destination directory or file, as indicated in the description.

**Returns / effects:** Manifest rows for copied templates/tables; writes HTML and Markdown without executing agent code.

### `bundle_manifest`

Inventory every exported payload with size, hash, and provenance

[Source](../scripts/build_results_bundle.R)

- `output`: Destination directory or file, as indicated in the description.
- `records`: Data frame mapping exported paths to original paths and copy dispositions.

**Returns / effects:** Manifest data frame, also written to MANIFEST.csv; excludes the manifest's own hash.

### `bundle_verify_files`

Check exported file integrity and absence of prohibited content

[Source](../scripts/build_results_bundle.R)

- `output`: Destination directory or file, as indicated in the description.
- `manifest`: Export inventory data frame containing paths and SHA-256 hashes.

**Returns / effects:** Stops on hash failures, common credential patterns, remaining local paths, or invalid saved artifacts.

### `build_results_bundle`

Build and validate a shareable ZIP for the two completed runs

[Source](../scripts/build_results_bundle.R)

- `output`: Destination directory or file, as indicated in the description.

**Returns / effects:** Creates output directory and adjacent .zip, refusing existing destinations. Originals remain unchanged; requires both local live runs.

### `resolve_bundle_run`

Resolve an explicit run path or a historical result-folder name.

[Source](../scripts/build_results_bundle.R)

- `name`: Absolute/project-relative directory or basename under results/.

**Returns / effects:** Existing normalized run directory.

### `render_bundle_readme`

Render the bundle reading guide without running agent content.

[Source](../scripts/build_results_bundle.R)

- `output`: Export root containing README.md.

**Returns / effects:** Writes a standalone README.html.

## `scripts/check_public_files.R`

### `check_staged_public_files`

Inspect the actual Git index before publishing source

[Source](../scripts/check_public_files.R)


**Returns / effects:** Stops on prohibited paths, unusual modes, oversized content or credential patterns; never opens .env.

## `scripts/check_reuse.R`

## `scripts/export_exploration.R`

### `write_exploration_source`

Export exact submitted R bytes without replacing different content

[Source](../scripts/export_exploration.R)

- `code`: Exact exploratory R source submitted to run_r.
- `output`: Destination directory or file, as indicated in the description.

**Returns / effects:** Creates output or verifies identical existing source; stops on a mismatch.

### `export_exploration_request`

Convert one recorded explore request into an R file and index row

[Source](../scripts/export_exploration.R)

- `path`: Input or destination filesystem path, as indicated in the description.
- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** One-row metadata data frame, or NULL for non-exploration modes.

### `exploration_readme`

Describe how archived exploratory snippets depend on their original setup

[Source](../scripts/export_exploration.R)


**Returns / effects:** Character lines for exploration-README.md.

### `export_exploration`

Export saved exploration calls and build their index

[Source](../scripts/export_exploration.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Writes .R copies, exploration-index.csv, and a reading guide without executing R snippets or calling models.

## `scripts/preflight.R`

## `scripts/render_api_reference.R`

### `reference_entry_lines`

Convert one adjacent roxygen-style block into a reference entry.

[Source](../scripts/render_api_reference.R)

- `expression`: Parsed named function assignment.
- `location`: Source reference identifying its definition line.
- `text`: Source file lines.
- `path`: Project-relative source path.

**Returns / effects:** Markdown lines documenting the name, parameters, return/effects, and source link.

### `reference_file_lines`

Enumerate named function assignments without evaluating their bodies.

[Source](../scripts/render_api_reference.R)

- `path`: Project-relative R source file.

**Returns / effects:** Markdown file section containing documented top-level functions.

## `scripts/render_report.R`

## `scripts/run_pilot.R`

## `scripts/setup.R`

## `scripts/sharing_helpers.R`

### `publication_secret_pattern`

Define heuristic credential patterns for publication review

[Source](../scripts/sharing_helpers.R)


**Returns / effects:** PCRE pattern; this is a format check, not a guarantee that arbitrary secrets are absent.

### `publication_private_path`

Identify generated or private paths that must not be staged

[Source](../scripts/sharing_helpers.R)

- `paths`: Character vector of filesystem paths or names to inspect.

**Returns / effects:** Logical vector aligned to paths; a plain .env.example is permitted outside blocked directories.

### `publication_read_text`

Read bounded text for publication review

[Source](../scripts/sharing_helpers.R)

- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** File content as a character scalar; refuses files larger than 20 MiB.

### `publication_scan`

Reject common credential formats without reading private key files

[Source](../scripts/sharing_helpers.R)

- `paths`: Character vector of filesystem paths or names to inspect.

**Returns / effects:** TRUE invisibly; on a match reports filenames only, never matching secret text.

### `publication_write_text`

Write exact UTF-8 export content

[Source](../scripts/sharing_helpers.R)

- `text`: Character text to escape, sanitize, or write.
- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Creates parent directories and writes bytes without an added newline.

### `publication_sanitize_paths`

Replace local project, home, and temporary paths in export text

[Source](../scripts/sharing_helpers.R)

- `text`: Character text to escape, sanitize, or write.

**Returns / effects:** Sanitized character text; the original source file is not changed.

### `publication_copy`

Copy an export file and optionally sanitize local paths

[Source](../scripts/sharing_helpers.R)

- `source`: Existing regular source file; symbolic links are rejected.
- `target`: Export destination file path, never the original source path.
- `immutable`: Logical; forbid sanitization or alteration of copied artifact bytes.

**Returns / effects:** Invisible disposition: unchanged or path-sanitized. Immutable artifacts must be byte-identical or copying stops.

## `scripts/test_sandbox.R`

## `scripts/test.R`

## `analyses/build_research_note.R`

### `note_page_break`

Insert a report page break using raw OpenXML

[Source](../analyses/build_research_note.R)


**Returns / effects:** Markdown fragment for Word-oriented rendering.

### `prompt_block`

Display literal prompt text as a fenced code block

[Source](../analyses/build_research_note.R)

- `text`: Character text to escape, sanitize, or write.

**Returns / effects:** Markdown string without interpreting prompt content as instructions.

### `note_agent_examples`

Select three reviewed examples from original frozen artifacts

[Source](../analyses/build_research_note.R)


**Returns / effects:** List of excerpt metadata and agent explanations; tied to the original run.

### `render_agent_example`

Format one archived code example with its explanation

[Source](../analyses/build_research_note.R)

- `example`: Archived example metadata and exact code/report excerpts.

**Returns / effects:** Markdown text quoting the source artifact and separating editorial commentary.

### `note_examples_appendix`

Combine original agent examples into the supplement

[Source](../analyses/build_research_note.R)


**Returns / effects:** Markdown appendix string.

### `note_prompt_appendix`

Collect archived shared and session prompts for the original run

[Source](../analyses/build_research_note.R)


**Returns / effects:** Markdown appendix; current prompt templates are not substituted for archived text.

### `compose_research_note`

Fill the historical note template from saved results

[Source](../analyses/build_research_note.R)


**Returns / effects:** Writes the composed Markdown note and returns its destination path; requires saved comparison outputs and original artifacts.

### `style_note_row`

Apply Word table-cell widths, borders and paragraph styles

[Source](../analyses/build_research_note.R)

- `row`: Character scalar containing a legacy Word table row's XML.
- `widths`: Numeric cell widths for the legacy Word formatter.
- `header`: Logical; apply header-row styling.
- `last`: Logical; apply the final-row border rule.

**Returns / effects:** Modified XML row string for the legacy Word formatter.

### `style_one_table`

Apply layout rules to one legacy Word table

[Source](../analyses/build_research_note.R)

- `table`: Character scalar containing a Word table's XML.

**Returns / effects:** Modified XML table string.

### `note_table_widths`

Choose widths for the legacy report's table types

[Source](../analyses/build_research_note.R)

- `columns`: Number of columns in the report table.
- `per_design`: Logical; use the per-design appendix layout.

**Returns / effects:** Numeric vector of cell widths for the supplied table shape.

### `style_note_tables`

Style all tables inside a legacy Word document

[Source](../analyses/build_research_note.R)

- `document`: Character scalar containing the Word document XML.

**Returns / effects:** Modified document XML string; does not mutate the caller's input.

### `style_prompt_text`

Adjust code and prompt paragraph styles in Word XML

[Source](../analyses/build_research_note.R)

- `styles`: Character scalar containing Word styles XML.

**Returns / effects:** Modified styles XML string.

### `style_note_styles`

Apply legacy report font, spacing, and heading styles

[Source](../analyses/build_research_note.R)

- `styles`: Character scalar containing Word styles XML.

**Returns / effects:** Modified styles XML string.

### `style_word_note`

Unpack, style, and repack a generated legacy Word note

[Source](../analyses/build_research_note.R)

- `path`: Input or destination filesystem path, as indicated in the description.

**Returns / effects:** Rewrites the supplied docx; publishing a document still requires visual verification.

### `build_research_note`

Build the legacy original-run Word research note

[Source](../analyses/build_research_note.R)


**Returns / effects:** Writes deliverables Markdown/docx from saved results; this is not the revised-run summary.

## `analyses/build_rmarkdown_note.R`

### `rmarkdown_note_header`

Define the original-run R Markdown document header

[Source](../analyses/build_rmarkdown_note.R)


**Returns / effects:** YAML and setup chunk text tied to the legacy local report builders.

### `build_agent_supplement`

Export the original prompt and example appendix as R Markdown

[Source](../analyses/build_rmarkdown_note.R)


**Returns / effects:** Writes deliverables/agent-analysis-supplement.Rmd and returns its path.

### `build_rmarkdown_note`

Build the concise original-run R Markdown note and supplement

[Source](../analyses/build_rmarkdown_note.R)


**Returns / effects:** Writes generated deliverables and literal prompt excerpts; no model calls.

## `analyses/compare_welch.R`

### `welch_screen`

Construct a source Welch shortlist with an inherited family size

[Source](../analyses/compare_welch.R)

- `pair`: List with exposed and unexposed numeric observation matrices.
- `reference`: Original frozen hypothesis table whose coordinate count and direction policy are inherited.
- `ranking`: p_value for two-sided Welch p ranking, otherwise absolute t-statistic ranking.

**Returns / effects:** Hypothesis data frame using source signs, or both directions when present in the reference family.

### `family_keys`

Represent measurement-direction pairs independently of hypothesis IDs

[Source](../analyses/compare_welch.R)

- `hypotheses`: Frozen table with hypothesis_id, measurement_id, and integer direction (-1 or +1).

**Returns / effects:** Character vector used for family-overlap comparisons.

### `welch_on_family`

Apply ordinary target Welch tests to a specified frozen family

[Source](../analyses/compare_welch.R)

- `pair`: List with exposed and unexposed numeric observation matrices.
- `hypotheses`: Frozen table with hypothesis_id, measurement_id, and integer direction (-1 or +1).
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `alpha`: Family level used directly; callers supply config$alpha/3 for target testing.

**Returns / effects:** Result data frame using Holm for FWER and historical BY for FDR.

### `check_existing_baseline`

Reproduce the original saved full Welch baseline before comparison

[Source](../analyses/compare_welch.R)

- `setting`: Trusted generated setting including observations, effects, and planning metadata.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `original`: Original saved score table used as a consistency reference.
- `alpha`: Family level used directly; callers supply config$alpha/3 for target testing.

**Returns / effects:** Stops if any of three target metrics differs beyond tolerance; makes no model calls.

### `compare_design`

Compare an original agent family with matched-size Welch screening

[Source](../analyses/compare_welch.R)

- `setting`: Trusted generated setting including observations, effects, and planning metadata.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `source`: Source subgroup index (1, 2, or 3).
- `context`: List with run, output, and alpha for the historical comparison.

**Returns / effects:** List of score and overlap tables; writes new comparison outputs and verifies original frozen hashes.

### `run_comparison`

Build the historical shortlist-versus-Welch comparison

[Source](../analyses/compare_welch.R)


**Returns / effects:** Writes results/welch-method-comparison, preserving results/live-first and using no new scientific draws.

## `analyses/retry_gateway_session.R`

### `gateway_retry_config`

Require the exact original implementation before a targeted gateway retry

[Source](../analyses/retry_gateway_session.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Validated live-run configuration with image and reference identities; stops after any signature change.

### `preserve_first_pass`

Archive score tables and report before replacing a failed attempt

[Source](../analyses/retry_gateway_session.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Creates infrastructure-retries/first-pass once; stops rather than replacing an existing archive.

### `publish_gateway_recovery`

Replace one failed score and rebuild recovery summaries

[Source](../analyses/retry_gateway_session.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `source`: Source subgroup index (1, 2, or 3).
- `result`: Recovered source-session summary from run_design().
- `score`: One updated per-target score row.
- `scores`: Per-target scores.csv data frame including method, status, and discovery metrics.
- `index`: Row index to replace in the scores table.

**Returns / effects:** Updates design status, scores, completion metadata and report; preserves unrelated score rows.

### `retry_gateway_session`

Recover the historical unfrozen HTTP 520 session under strict guards

[Source](../analyses/retry_gateway_session.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.
- `scenario_id`: Stable scenario identifier such as fwer_m20_c20.
- `source`: Source subgroup index (1, 2, or 3).

**Returns / effects:** Runs only one missing source design and its target evaluation; requires a matching archived failed audit. Not a general retry command.

## `analyses/summarize_revised_run.R`

### `revised_tool_usage`

Count actual exploratory and reference calls in one saved history

[Source](../analyses/summarize_revised_run.R)

- `directory`: Filesystem directory holding the relevant inputs or outputs.

**Returns / effects:** List with exploration/reference counts and requested section IDs; missing histories produce NA.

### `revised_design_row`

Summarize one revised frozen design and target-direction coverage

[Source](../analyses/summarize_revised_run.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `source`: Source subgroup index (1, 2, or 3).

**Returns / effects:** One-row data frame with methods, family size, coverage, tool calls and usage.

### `revised_metric`

Extract a complete scenario-method aggregate metric

[Source](../analyses/summarize_revised_run.R)

- `global`: Scenario-method aggregate table from global_scores().
- `scenario`: One-row scenario record containing id, data_id, m, c, and criterion.
- `method`: Method ID used in score tables.
- `field`: Metric column to extract, defaulting to power.

**Returns / effects:** Scalar value, or NA when the method is missing or incomplete.

### `revised_comparison`

Compare original and revised realized power on matched data

[Source](../analyses/summarize_revised_run.R)

- `old_dir`: Original saved live-run directory.
- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Eight-row comparison table; checks unchanged historical Welch Holm/BY baseline metrics.

### `revised_coverage_note`

Describe frozen-direction coverage for the large high-power FDR setting

[Source](../analyses/summarize_revised_run.R)

- `designs`: Revised per-agent summary data frame.

**Returns / effects:** Editorial text, or an empty string if required coverage is unavailable.

### `revised_method_note`

Describe BH/Holm labels in submitted manifest summaries

[Source](../analyses/summarize_revised_run.R)

- `designs`: Revised per-agent summary data frame.

**Returns / effects:** Editorial text based on text matching; equal weights also count as weighted in this legacy summary.

### `revised_summary_text`

Compose the revised-run comparison narrative and power table

[Source](../analyses/summarize_revised_run.R)

- `comparison`: Eight-scenario original/revised comparison data frame.
- `designs`: Revised per-agent summary data frame.
- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Markdown text from saved tables and archived failure records.

### `render_revised_summary`

Write and render the project-dependent revised-run summary

[Source](../analyses/summarize_revised_run.R)

- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Writes analysis-summary.Rmd/html; requires original results and project helpers.

### `summarize_revised_run`

Verify matching datasets and build the revised-run summaries

[Source](../analyses/summarize_revised_run.R)

- `old_dir`: Original saved live-run directory.
- `run_dir`: Saved run directory containing metadata, scenarios, scores, and host-private inputs.

**Returns / effects:** Writes agent-designs.csv, comparison.csv, and Markdown/R Markdown/HTML; reads private truth, never calls models.

## `analyses/technical_note.R`

### `technical_setting`

Format a scenario label for the original research note

[Source](../analyses/technical_note.R)

- `row`: One scenario record to label, or a Word XML row in styling helpers.

**Returns / effects:** Character label containing criterion, m, and c.

### `concise_note_results`

Format the original run's four-method power comparison

[Source](../analyses/technical_note.R)


**Returns / effects:** Markdown table string; requires original run and saved Welch comparison.

### `technical_methods`

Map historical report column labels to method IDs

[Source](../analyses/technical_note.R)


**Returns / effects:** Named character vector A through E.

### `technical_scores`

Join saved historical comparison and oracle rows

[Source](../analyses/technical_note.R)


**Returns / effects:** Validated 120-row score table from local results; no analysis is rerun.

### `technical_metric_table`

Format a chosen historical metric across five methods

[Source](../analyses/technical_note.R)

- `formatter`: Function accepting an ordered method table and returning display strings.
- `headers`: Character vector of Markdown column headings.

**Returns / effects:** Markdown table string using the caller's formatter and column headers.

### `technical_planning_table`

Format and check historical sample-size minimality

[Source](../analyses/technical_note.R)


**Returns / effects:** Markdown table; requires planning.csv and verifies the strict crossing condition.

### `technical_test_type`

Look up manually reviewed test categories in the original run

[Source](../analyses/technical_note.R)

- `scenario`: Original-run scenario ID string, not a scenario data frame.
- `source`: Source subgroup index (1, 2, or 3).

**Returns / effects:** T1-T4 label; valid only for the archived original 24 designs, not new runs.

### `technical_agent_rows`

Summarize all original frozen designs and true-direction coverage

[Source](../analyses/technical_note.R)


**Returns / effects:** Validated 24-row table; reads private truth on the trusted host and verifies frozen hashes.

### `technical_coverage_table`

Aggregate original source-family coverage of target signals

[Source](../analyses/technical_note.R)

- `agents`: Original per-design table from technical_agent_rows().

**Returns / effects:** Markdown table and a saved coverage.csv under comparison report-tables.

### `technical_usage_table`

Format original-run elapsed time and model usage

[Source](../analyses/technical_note.R)


**Returns / effects:** Markdown table from saved retained-session usage and run timestamps.

### `technical_sections`

Build the historical technical note's data-dependent sections

[Source](../analyses/technical_note.R)


**Returns / effects:** Named Markdown replacements; also writes agent-design and global-results report tables.

### `technical_agent_appendix`

Format original per-design routes and outcomes

[Source](../analyses/technical_note.R)


**Returns / effects:** Markdown appendix; depends on manually reviewed original test-type labels.

## `analyses/validate_pooled_run.R`

### `reconstruct_count_credit`

Independently reconstruct count credit from per-target result files.

[Source](../analyses/validate_pooled_run.R)

- `setting`: Trusted setting providing the true effect matrix.
- `rows`: Three successful evaluation-ledger rows for one method.
- `directory`: Scenario output directory.

**Returns / effects:** List with recovery, overclaims and all-null discoveries.

### `validate_pooled_decisions`

Check selection counts and routes against actual pooled output files.

[Source](../analyses/validate_pooled_run.R)

- `directory`: Scenario directory with candidate/decision tables.

**Returns / effects:** NULL; stops on a mismatched count, winner, tie, or source route.

### `validate_pooled_outputs`

Validate all score definitions, frozen files, and original cyclic comparator values.

[Source](../analyses/validate_pooled_run.R)

- `run_dir`: Completed new run.
- `reuse_run`: Original revised run used for imports.

**Returns / effects:** TRUE invisibly; checks every method against independently reconstructed counts.

### `validate_pooled_provenance`

Verify imported bytes, c=.9 planning minimality, and new/historical usage separation.

[Source](../analyses/validate_pooled_run.R)

- `run_dir`: Completed new run.
- `reuse_run`: Historical source run.

**Returns / effects:** NULL; stops on altered imports or unexpected design/accounting counts.

## `docker/install.R`

### `install_exact`

Install a pinned R package while building the image

[Source](../docker/install.R)

- `package`: R package name.
- `version`: Exact package version to install and verify.

**Returns / effects:** Downloads from CRAN or its archive and verifies the installed version; build-time network only.

## `docker/runtime.R`

### `write_failure`

Record a container-side analysis error

[Source](../docker/runtime.R)

- `error`: Caught R condition whose message is written to the container status file.

**Returns / effects:** Writes /output/status.json with failed status and the exception message.

### `load_pair`

Load and validate only the observation matrices mounted into a container

[Source](../docker/runtime.R)


**Returns / effects:** List containing exposed and unexposed; has no access to simulation truth.

### `run_exploration`

Evaluate exploratory R code in a fresh scope inside the container

[Source](../docker/runtime.R)

- `pair`: List with exposed and unexposed numeric observation matrices.

**Returns / effects:** Executes /control/code.R with matrices and n/m; files in /work may be written.

### `run_analysis`

Execute the staged reusable analysis and validate its output

[Source](../docker/runtime.R)

- `pair`: List with exposed and unexposed numeric observation matrices.
- `alpha`: Family level used directly; callers supply config$alpha/3 for target testing.

**Returns / effects:** Writes /output/result.csv; checks the declared frozen family and result schema.

### `main`

Dispatch container mode, seed execution, and write success status

[Source](../docker/runtime.R)

- `args`: Container arguments: mode, alpha, and execution seed, in that order.

**Returns / effects:** Writes /output/status.json; the top-level handler records errors and exits nonzero.

## `fixtures/analysis.R`

### `fixture_pvalue`

Calculate one directional Welch p-value for an offline fixture

[Source](../fixtures/analysis.R)

- `exposed`: Numeric n by m exposed matrix with unique measurement column names.
- `unexposed`: Numeric n by m independent control matrix with the same dimensions and names.
- `measurement`: One existing measurement column name.
- `direction`: Frozen sign: +1 for a higher exposed population mean, -1 for a lower mean.

**Returns / effects:** Numeric p-value; not a model-designed scientific method.

### `analyze`

Execute the deterministic fixture analysis under the artifact contract

[Source](../fixtures/analysis.R)

- `exposed`: Numeric n by m exposed matrix with unique measurement column names.
- `unexposed`: Numeric n by m independent control matrix with the same dimensions and names.
- `hypotheses`: Frozen table with hypothesis_id, measurement_id, and integer direction (-1 or +1).
- `alpha`: Family level used directly; callers supply config$alpha/3 for target testing.

**Returns / effects:** Typed per-hypothesis result data frame using FIXTURE_CORRECTION injected by fixture_design.
