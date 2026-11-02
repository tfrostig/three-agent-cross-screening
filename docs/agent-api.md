# Agent and artifact contracts

The Python package implements a single source-design session. R owns simulation,
target routing, baselines, and truth-aware scoring. See the [walkthrough](developer-guide.md)
for their call sequence and the [Python reference](python-api.md) for docstrings.

## Construction and session ownership

`build_agent()` creates a new `Agent` with `AgentDependencies` and strict structured
output `ToolOutput(DesignManifest, name="finalize_design")`. Each session receives
new dependencies, an `RRunner`, a verified reference snapshot, and empty history.
There is no registry or tool for contacting another source agent.

`SessionConfig` holds the already-allocated family level, dimensions, source-only
input directory, mutable workspace, controller-only audit directory, explicit
model ID, and budgets. It is a frozen dataclass, not model-provided configuration.
`AgentDependencies` holds mutable call counters and checked artifact hashes.
The reference snapshot is session-local; its frozen dataclass still contains
controller-owned nested dictionaries, so it is not a deeply immutable data structure.

## Prompt layers

| Layer | Implementation | What it contributes |
|:---|:---|:---|
| System prompt | `prompts/system.txt` → `Agent(system_prompt=...)` | Statistical role, objective, allowed design choices, and scientific limitations. |
| Shared instructions | `prompts/developer.txt` → `Agent(instructions=...)` | Frozen-artifact contract, tools, limits, and execution rules. |
| Reference context | `ReferenceLibrary.prompt_context()` appended to instructions | Common brief and catalog, with background delimited from instructions. |
| Session task | `user_prompt(config)` | Only session ID, sample dimensions, criterion, supplied alpha, and design task. |
| Tool descriptions | Registered function signatures/docstrings | Tool arguments and the exposed/unexposed matrix data dictionary. |
| Tool results | This source agent's tool calls | Printed exploration, contract results, artifact-write status, requested references. |

All agents share the statistical instructions. Their separate user/session messages
do not carry findings from preceding agents. `direction=+1` denotes a higher exposed
population mean and `-1` a lower mean. The formal theta/null block is omitted from
shared instructions; matrix structure lives in `run_r` and direction encoding in
the artifact contract.

Tool docstrings and Pydantic output-schema descriptions can affect the model.
Treat changes to them as prompt changes. Maintainer-only function docstrings and
R comments do not enter messages, although they still affect source-byte fingerprints.
The exact prompts for an actual run are in `audit/prompts.json`; current templates
are not a substitute for those archived messages.

## Tool interfaces

| Tool | Arguments | Result and effects |
|:---|:---|:---|
| `run_r` | `code: str` | `ToolResult`; explores only source matrices in a fresh Docker R process. Source limited to 128 KiB; consumes one R-call slot. Saves exact source, request, seed and output. |
| `write_artifact_file` | `path: str`, `content: str` | Writes an allowlisted basename up to 256 KiB, returns status text, and invalidates checked hashes. Paths cannot address arbitrary files. |
| `check_design` | None | `ToolResult`; runs current artifacts on source observations and records successful current hashes. Consumes repair budget on failures, not an exploratory R slot. |
| `read_reference` | `reference_id: str`, `section_id: str="overview"` | Cited approved text in a `ToolResult`, at most 8 KiB including metadata. Consumes shared tool/API budgets, not an R-call slot. |
| `finalize_design` | Strict `DesignManifest` fields below | Ends a session only if artifacts match a successful current check; its output is frozen by the controller. |

`ToolResult` has `status` (`ok` or `failed`), `stdout`, `stderr`, optional `error`,
and `truncated`. Wrapper exit/timeout metadata remains in controller audit files;
only typed fields are returned to the agent. Current container output is capped
at 32 KiB per stream, with a truncation flag. `max_tool_output_bytes` is recorded
in configuration but is not separately wired into that hard-coded wrapper cap.

Each `run_r` starts with numeric `exposed` and `unexposed` matrices and `n`/`m`.
Rows are independent observations; columns have aligned measurement names.
Rows across samples are not paired. R variables do not persist across calls;
files in `/work` persist only during that source session. Tools cannot install
packages, access a host shell, or call external services from the R container.

## Structured final output

`DesignManifest` forbids extra fields and uses strict Pydantic validation.

| Field | Type and interpretation |
|:---|:---|
| `script_file` | Literal `"analysis.R"`. |
| `hypotheses_file` | Literal `"hypotheses.csv"`. |
| `report_file` | Literal `"report.md"`. |
| `test_summary` | Nonempty description of individual tests and estimand. |
| `multiplicity_summary` | Nonempty description of the entire rejection procedure. |
| `assumptions` | List of explicitly stated modeling and error-control assumptions. |
| `limitations` | List of scientific, computational, or transfer limitations. |

These fields summarize the design; the executable procedure remains in `analysis.R`.
Pydantic cannot establish whether a statistical justification is correct.

## Frozen files

`hypotheses.csv` must have exactly these columns in order:

```csv
hypothesis_id,measurement_id,direction
v0001_up,v0001,1
v0001_down,v0001,-1
```

IDs are unique nonempty strings. Measurements must exist in the matrices, and
each measurement/direction pair must be unique. Either sign, both signs, or neither
may be submitted. An empty family includes the header and no rows. Selecting both
directions creates two distinct hypotheses; it is not one two-sided test.

`analysis.R` must define:

```r
analyze <- function(exposed, unexposed, hypotheses, alpha) {
  # Compute target-only raw p-values and the complete frozen correction here.
}
```

It must include its own helpers and fixed settings, keyed by hypothesis ID where
appropriate. It cannot depend on mutable source files or source observations.
It returns exactly these columns:

| Column | Contract |
|:---|:---|
| `hypothesis_id` | Exactly one row for every frozen ID; order may differ because scoring aligns IDs. |
| `p_value` | Finite numeric raw one-sided value in `[0,1]`. |
| `reject` | Logical decision without missing values. |
| `adjusted_p_value` | Numeric in `[0,1]`, or `NA_real_` if not meaningful. |

A valid zero-row result still uses character/numeric/logical/numeric column types.
The harness does not check that rejection flags equal a conventional adjustment:
agents own the complete correction and must explain it. Likewise schema validation
cannot prevent semantically invalid p-values. Review the scientific explanation.

`report.md` explains hypothesis selection, directions, tests, correction, assumptions,
transfer issues, references actually used, and limitations. `frozen.json` combines
the final structured manifest with SHA-256 hashes of the three artifacts.

## Check, repair, and freeze lifecycle

1. Write or revise artifacts in the source workspace.
2. Run `check_design()` on source observations. Hashes are recorded only on success
   and only if bytes remain unchanged through checking.
3. Further artifact writes clear those hashes. A failed check also clears them and
   increments the configured repair counter.
4. Submit `finalize_design`. The output validator rejects unchecked or changed
   files; exhausted repair budgets stop the session.
5. The controller rehashes files, copies the exact checked bytes into a new frozen
   directory, and makes the files read-only. Existing frozen destinations are refused.
6. R evaluates target data in a separate fresh container and verifies frozen hashes
   before and after. No target response enters the source conversation.

Read-only permissions and hashes protect the frozen record; they are not an
operating-system boundary for the trusted host controller. Docker provides the
boundary for generated R. The host process and its filesystem remain trusted.

## API requests and offline behavior

Live sessions use an explicit Responses model, disable SDK retries, request no
provider storage, and disable parallel tool calls. PydanticAI limits model-loop
requests/tool calls; `CountedTransport` independently limits physical HTTP attempts.
Only HTTPS POST `/v1/responses` to `api.openai.com` is accepted by that transport.
Its retry status allowlist excludes HTTP 520; that historical failure was recovered
separately with preserved audit evidence.

Offline execution uses `FunctionModel` and prewritten R fixture artifacts. It still
exercises the real PydanticAI tools and Docker wrapper but makes no OpenAI calls.
It validates session wiring, not autonomous scientific design. The fixture's FDR
correction remains BY even when the live preference is BH.
