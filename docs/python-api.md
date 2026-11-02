# Python API reference

These entries are extracted statically from the source docstrings. No credentials, agents, or model clients are loaded. See the [agent contracts](agent-api.md) for tool schemas and the [developer walkthrough](developer-guide.md) for the R/Python boundary.

## `agents/__init__.py`

Isolated PydanticAI statistical design sessions.

## `agents/artifacts.py`

Bounded data-only artifact writes, integrity checks, and final freezing.

Only analysis.R, hypotheses.csv, and report.md are writable through the tool.
No artifact is evaluated by this module; successful source checks authorize
freezing only the exact bytes whose hashes were recorded.

### `artifact_path`

[Source](../agents/artifacts.py)

```python
def artifact_path(workspace: Path, name: str) -> Path
```

```text
Resolve one of the three permitted regular workspace artifacts.

Args:
    workspace: Session-specific mutable work directory.
    name: analysis.R, hypotheses.csv, or report.md only.

Returns:
    Safe local Path; a missing destination is permitted before its first write.

Raises:
    ValueError: The name, path containment, link, or file type is unsafe.
```

### `write_artifact`

[Source](../agents/artifacts.py)

```python
def write_artifact(workspace: Path, name: str, content: str) -> None
```

```text
Write a bounded UTF-8 artifact without executing its contents.

Args:
    workspace: Session-specific artifact directory.
    name: One allowlisted artifact basename.
    content: Text no larger than 256 KiB when UTF-8 encoded.

Raises:
    ValueError: The artifact is oversized or its path is unsafe.
```

### `artifact_hashes`

[Source](../agents/artifacts.py)

```python
def artifact_hashes(workspace: Path) -> dict[str, str]
```

```text
Hash the three bounded regular artifacts as raw bytes.

Args:
    workspace: Directory containing all three required artifact files.

Returns:
    Mapping from artifact basename to SHA-256 digest.

Raises:
    ValueError: An artifact is missing, linked, unsafe, or larger than 256 KiB.
```

### `freeze_design`

[Source](../agents/artifacts.py)

```python
def freeze_design(workspace: Path, destination: Path, manifest: DesignManifest, checked_hashes: dict[str, str]) -> dict
```

```text
Publish checked artifacts exactly once and make their copies read-only.

Args:
    workspace: Mutable directory that passed the latest check.
    destination: New sibling frozen directory; an existing directory is refused.
    manifest: Validated structured scientific description from final output.
    checked_hashes: Digests saved after a successful current-artifact check.

Returns:
    Manifest/hash record also written to frozen.json; source bytes are copied.

Raises:
    ValueError: Bytes changed after checking or the frozen destination exists.
```

## `agents/credentials.py`

Trusted-controller credential parsing and optional model-access checks.

Uses an exported key first, otherwise the previously authorized private loader.
Assignments are never shell-sourced, expanded, logged, or sent to R containers.
Publication/documentation checks never call this loader.

### `read_api_key`

[Source](../agents/credentials.py)

```python
def read_api_key(project_root: Path) -> str
```

```text
Load the runtime key without shell evaluation or secret output.

Args:
    project_root: Trusted project directory with an optional authorized .env.

Returns:
    Exported OPENAI_API_KEY when set, otherwise its literal .env assignment.
    The value stays in controller memory and is never passed to R containers.

Raises:
    ValueError: The assignment is missing, empty, or malformed.
```

### `parse_key`

[Source](../agents/credentials.py)

```python
def parse_key(value: str) -> str
```

```text
Parse one literal key assignment without expansion or execution.

Args:
    value: Right-hand side of an OPENAI_API_KEY assignment, with optional quotes.

Returns:
    Exactly one nonempty literal token; shell substitutions remain literal.

Raises:
    ValueError: Invalid quoting or multiple/empty tokens, with no secret echoed.
```

### `verify_model`

[Source](../agents/credentials.py)

```python
def verify_model(project_root: Path, model: str) -> bool
```

```text
Check model availability through the trusted controller only.

Args:
    project_root: Root used by the private credential loader.
    model: Explicit provider model ID; never substituted automatically.

Returns:
    Boolean success; prints only model identity or error class/HTTP status.
    This uses the models endpoint outside the design-session transport.
```

### `main`

[Source](../agents/credentials.py)

```python
def main()
```

```text
Check runtime credential availability or explicit model access.

--check only checks key availability. --verify-model MODEL makes a provider
model-access request without sending observations or printing the credential.
```

## `agents/factory.py`

Build independent PydanticAI agents and register their typed tools.

The nested tool docstrings are model-visible experiment inputs. Host-only
maintainer docs live on the outer registration functions and in docs/agent-api.md.

### `build_agent`

[Source](../agents/factory.py)

```python
def build_agent(model, system_prompt: str, instructions: str)
```

```text
Construct a session-local agent and register its capabilities.

Args:
    model: PydanticAI model instance, live or deterministic fixture.
    system_prompt: Shared statistical role and scientific objective.
    instructions: Shared execution contract plus optional reference brief.

Returns:
    A fresh Agent with strict DesignManifest output and session-bound tools.
```

### `register_tools`

[Source](../agents/factory.py)

```python
def register_tools(agent)
```

```text
Attach R exploration, artifact-writing, and contract-check tools.

Args:
    agent: Fresh Agent to mutate with tool registrations.

Tool descriptions below are model-visible prompt content. Keep maintainer
documentation outside those descriptions unless changing the experiment.
```

### `register_tools.run_r`

[Source](../agents/factory.py)

```python
def run_r(ctx: RunContext[AgentDependencies], code: str) -> ToolResult
```

```text
Explore your own data in a fresh R process with an initialized seed.

Numeric matrices exposed and unexposed are preloaded. Rows are independent
observations; columns are measurements. Matching column names identify the
same measurements in target data. Row indices do not indicate matched
subjects. n and m give the exposed row and column counts. Variables do not
persist across calls; files in /work persist during design.

Args:
    code: R code to execute on the supplied source observations.
```

### `register_tools.write_artifact_file`

[Source](../agents/factory.py)

```python
def write_artifact_file(ctx: RunContext[AgentDependencies], path: str, content: str) -> str
```

```text
Write analysis.R, hypotheses.csv, or report.md in your own workspace.
```

### `register_tools.check_design`

[Source](../agents/factory.py)

```python
def check_design(ctx: RunContext[AgentDependencies]) -> ToolResult
```

```text
Validate your artifacts by running them against your own data.
```

### `register_reference_tool`

[Source](../agents/factory.py)

```python
def register_reference_tool(agent)
```

```text
Attach approved-section retrieval using only the current dependencies.

Args:
    agent: Agent receiving a reference tool; no global library is shared.
```

### `register_reference_tool.read_reference`

[Source](../agents/factory.py)

```python
def read_reference(ctx: RunContext[AgentDependencies], reference_id: str, section_id: str='overview') -> ToolResult
```

```text
Read an approved reference section, with citation and PDF page locator.

Args:
    reference_id: Library ID listed in the shared reference catalog.
    section_id: Approved section ID; defaults to its overview.
```

### `check_current_design`

[Source](../agents/factory.py)

```python
def check_current_design(deps: AgentDependencies) -> ToolResult
```

```text
Check executable structure and remember the exact successful artifact bytes.

Args:
    deps: Mutable state for one session, including runner and repair budget.

Returns:
    ToolResult from the source-data contract check, never target results.

Raises:
    RuntimeError: The configured contract-repair budget is exhausted.
```

### `register_validator`

[Source](../agents/factory.py)

```python
def register_validator(agent)
```

```text
Require final output to refer to currently checked artifact hashes.

Args:
    agent: Agent receiving the final-output validator.

A write invalidates the prior check; finalization cannot bypass a recheck.
```

### `register_validator.validate_output`

[Source](../agents/factory.py)

```python
def validate_output(ctx: RunContext[AgentDependencies], output: DesignManifest) -> DesignManifest
```

```text
Accept the manifest only while artifact hashes match the last check.

```

## `agents/models.py`

Typed host/session and artifact contracts.

DesignManifest is the strict model-visible output schema; its class description
is intentionally preserved. SessionConfig contains source paths but no truth.
See docs/agent-api.md for the complete tool and artifact field contracts.

### `DesignManifest`

[Source](../agents/models.py)

```python
class DesignManifest
```

```text
Scientific description of a frozen R analysis.
```

### `ToolResult`

[Source](../agents/models.py)

```python
class ToolResult
```

```text
Bounded result of a container execution or contract check.
```

### `SessionConfig`

[Source](../agents/models.py)

```python
class SessionConfig
```

```text
Immutable host-side configuration for one source session.

Attributes:
    session_id: Opaque session identifier, with no sibling information.
    m: Measurement count.
    n: Observations per exposed/control arm.
    criterion: FWER or FDR.
    alpha: Already allocated target-family level; do not divide it again.
    model: Explicit provider model ID.
    input_dir: Directory containing this source's exposed/unexposed RDS files.
    workspace: Mutable source-only artifact and persistent-file directory.
    audit_dir: Controller-owned logs, outside agent-visible mounts.
    project_root: Trusted host code root; never mounted into agent containers.
    sandbox: Image, CPU, memory, and execution timeout configuration.
    limits: R-call, tool-call, repair, and output budgets.
    openai: Provider request, retry, timeout, and output-token limits.
    reference_pack: Optional trusted curated-library path.
    reference_digest: Optional expected catalog SHA-256.
```

### `AgentDependencies`

[Source](../agents/models.py)

```python
class AgentDependencies
```

```text
Mutable state allocated afresh for each PydanticAI session.

Attributes:
    config: Immutable source-session configuration.
    runner: Session-bound RRunner.
    r_executions: Exploration-call budget consumed so far.
    repairs: Failed contract/finalization checks counted against the repair cap.
    checked_hashes: Artifact digests from the latest successful check; cleared
        after a tool write or failed check.
    references: Verified session-local methodological reference snapshot.
```

## `agents/offline.py`

Deterministic provider fixture for the real PydanticAI tool loop.

Prewritten artifacts come from R/designs.R, not a live model. Each model has a
private turn counter. Offline success validates wiring and contracts, not the
scientific quality or power of an autonomous analysis.

### `offline_model`

[Source](../agents/offline.py)

```python
def offline_model(with_references: bool=False)
```

```text
Create an independent deterministic provider for software checks.

Args:
    with_references: Add an initial approved-reference retrieval step.

Returns:
    FunctionModel that explores, checks prewritten fixture artifacts, and
    finalizes. It does not invent a scientific method or call OpenAI.
```

### `offline_model.respond`

[Source](../agents/offline.py)

```python
def respond(messages, info)
```

```text
Advance this fixture's private turn counter and emit the next tool call.

```

## `agents/prompts.py`

Assemble versioned prompts and export an offline review copy.

System role, shared execution instructions, optional reference context, and
source-session task metadata are distinct inputs. Generator source, truth,
planning targets, sibling histories, and target outcomes never enter this text.

### `load_prompts`

[Source](../agents/prompts.py)

```python
def load_prompts(root: Path, references: ReferenceLibrary | None=None) -> tuple[str, str]
```

```text
Load shared templates and optionally append approved reference context.

Args:
    root: Project root containing prompts/system.txt and developer.txt.
    references: Optional verified session-local ReferenceLibrary.

Returns:
    Tuple of statistical system prompt and shared execution instructions.
```

### `user_prompt`

[Source](../agents/prompts.py)

```python
def user_prompt(config: SessionConfig) -> str
```

```text
Build the source session's dimensions and directional-discovery task.

Args:
    config: SessionConfig with sample dimensions, criterion, and supplied alpha.

Returns:
    Task text without generator truth, sibling data, target outcomes, or n's
    planning rationale. Source observations arrive only through the R tool.
```

### `write_prompt_preview`

[Source](../agents/prompts.py)

```python
def write_prompt_preview(root: Path, output: Path) -> None
```

```text
Export current assembled prompt text without running agents.

Args:
    root: Project directory containing templates, curated pack, and tool source.
    output: Markdown review destination; parent directories are created.

Reads the run_r docstring statically because it is part of model-visible data
documentation; does not load credentials or send provider requests.
```

### `main`

[Source](../agents/prompts.py)

```python
def main()
```

```text
Run the offline prompt-preview CLI.

Accepts --output FILE, defaulting to deliverables/revised-agent-prompts.md.
```

## `agents/references.py`

Verify and snapshot curated methods references independently per session.

Only catalog-approved payloads are readable. The common brief is injected into
shared instructions; optional sections are retrieved by ID with citations and
size limits. This interface cannot read original PDFs or arbitrary host paths.

### `approved_file`

[Source](../agents/references.py)

```python
def approved_file(root: Path, name: str) -> Path
```

```text
Resolve one catalog-relative regular file inside the reference pack.

Args:
    root: Trusted reference-pack directory.
    name: Approved relative filename, without absolute paths or traversal.

Returns:
    Existing regular Path after containment and link checks.

Raises:
    ValueError: The reference is missing, linked, or outside the library.
```

### `snapshot_contents`

[Source](../agents/references.py)

```python
def snapshot_contents(root: Path, catalog: dict) -> dict[str, str]
```

```text
Read only catalog-approved payloads and verify their byte hashes.

Args:
    root: Reference-pack directory.
    catalog: Versioned catalog containing payload digests and allowed sections.

Returns:
    UTF-8 text mapping owned by this session; at most 16 KiB for the brief
    and 6 KiB per other payload. Rejects stale or unapproved content.
```

### `ReferenceLibrary`

[Source](../agents/references.py)

```python
class ReferenceLibrary
```

```text
Session-local verified snapshot of approved methodological context.

Attributes:
    digest: SHA-256 of the original catalog bytes.
    catalog: Allowed references, section locators, citations, and payload hashes.
    contents: Verified UTF-8 payloads, loaded once for this session.

Frozen dataclass fields prevent reassignment; nested dictionaries are treated
as controller-owned values and are never passed to tools for modification.
```

### `ReferenceLibrary.load`

[Source](../agents/references.py)

```python
def load(cls, root: Path, expected_digest: str | None=None)
```

```text
Snapshot a verified library before model access.

Args:
    root: Reference-pack directory containing catalog.json.
    expected_digest: Optional catalog SHA-256 locked by the R controller.

Returns:
    New ReferenceLibrary containing verified text and catalog metadata.

Raises:
    ValueError: The catalog/version/digest or an approved payload is invalid.
```

### `ReferenceLibrary.prompt_context`

[Source](../agents/references.py)

```python
def prompt_context(self) -> str
```

```text
Compose the common brief and available section IDs for shared instructions.

Returns:
    Prompt text with reference_brief delimiters. Full optional excerpts
    are not injected; the model requests those through read_reference.
```

### `ReferenceLibrary.read`

[Source](../agents/references.py)

```python
def read(self, reference_id: str, section_id: str='overview') -> ToolResult
```

```text
Return one approved section with attribution and PDF page locators.

Args:
    reference_id: Allowlisted library ID from the common catalog.
    section_id: Named section, defaulting to overview.

Returns:
    ToolResult whose stdout is the cited section, bounded to 8 KiB total.

Raises:
    ValueError: IDs are unknown or the response exceeds its size limit.
```

### `ReferenceLibrary.audit_record`

[Source](../agents/references.py)

```python
def audit_record(self) -> dict
```

```text
Describe exactly which reference context was available in this session.

Returns:
    Dictionary containing the catalog digest, full catalog, and injected
    brief. Requested section content is recorded in conversation audits.
```

## `agents/runner.py`

Bridge source-only R tools to the trusted Docker wrapper.

Every call records its request and seed, saves submitted exploration source,
and invokes only scripts/agent_tool.R under a credential-free environment.
The wrapper then stages allowlisted files into a fresh restricted container.

### `clean_environment`

[Source](../agents/runner.py)

```python
def clean_environment(project_root: Path, home: Path) -> dict[str, str]
```

```text
Build the credential-free environment for the trusted R wrapper.

Args:
    project_root: Host project root passed through CROSS_SCREENING_ROOT.
    home: Temporary wrapper home, replacing the user's inherited HOME.

Returns:
    Explicit environment allowlist; OPENAI_API_KEY and other secrets are absent.
```

### `save_exploration_code`

[Source](../agents/runner.py)

```python
def save_exploration_code(request_file: Path, code: str) -> None
```

```text
Archive exact submitted R source before any container execution.

Args:
    request_file: Controller-owned audit request path.
    code: Submitted exploration source, encoded as UTF-8 without alteration.

Writes audit/exploration/<request-stem>.R, including calls that later fail.
```

### `RRunner`

[Source](../agents/runner.py)

```python
class RRunner
```

```text
Session-bound bridge to scripts/agent_tool.R and Docker execution.

Attributes:
    config: Source-only SessionConfig.
    calls: Numbered audit sequence covering exploration and contract checks.

Generated R never runs directly in this Python process or in a host R session.
```

### `RRunner.__init__`

[Source](../agents/runner.py)

```python
def __init__(self, config: SessionConfig)
```

```text
Bind wrapper paths and the audit sequence to one source session.

Args:
    config: SessionConfig whose input/work/audit paths never change here.
```

### `RRunner.execute`

[Source](../agents/runner.py)

```python
def execute(self, mode: str, code: str='') -> ToolResult
```

```text
Delegate one explore/check request to the trusted Docker wrapper.

Args:
    mode: explore or check; target evaluation is controlled separately by R.
    code: R source for explore; ignored for artifact checking.

Returns:
    Bounded ToolResult. Writes numbered request/result audits and records
    an independent execution seed; each call starts a fresh container.
```

## `agents/session.py`

Execute one isolated design session launched by the trusted R pipeline.

The controller creates fresh histories, dependencies, runner, reference snapshot,
and client per session. It records partial audits, checks final artifact hashes,
and publishes frozen copies. Target evaluation remains exclusively in R.

### `load_session`

[Source](../agents/session.py)

```python
def load_session(path: Path) -> SessionConfig
```

```text
Read a trusted R-controller manifest and prepare session directories.

Args:
    path: Host-private JSON containing source paths, budgets, and task metadata.

Returns:
    SessionConfig with resolved paths; creates work/audit directories.
```

### `live_resources`

[Source](../agents/session.py)

```python
async def live_resources(config)
```

```text
Create one Responses model, owned client, and counted transport.

Args:
    config: SessionConfig with an explicit model ID and OpenAI budgets.

Returns:
    Tuple of model, AsyncOpenAI client, and CountedTransport. The caller owns
    client cleanup; SDK retries are disabled so physical attempts are counted.
```

### `execute`

[Source](../agents/session.py)

```python
async def execute(config: SessionConfig, offline: bool) -> dict
```

```text
Run one source-only design session and freeze the checked artifacts.

Args:
    config: Independent session configuration; contains no latent effects.
    offline: Use the deterministic provider instead of a live OpenAI model.

Returns:
    Success summary with duration, retained usage, and frozen hashes. Writes
    prompt/reference/session audits; exceptions propagate to the CLI handler.
```

### `run_with_audit`

[Source](../agents/session.py)

```python
async def run_with_audit(agent, prompt, deps)
```

```text
Run with an empty history and persist exchanges after each graph node.

Args:
    agent: Fresh PydanticAI agent with typed dependencies and output.
    prompt: Session-specific dimensions, criterion, level, and task.
    deps: State owned by this session alone.

Returns:
    Completed run result; partial messages are also persisted on failure.
```

### `write_audit`

[Source](../agents/session.py)

```python
def write_audit(config, name, value)
```

```text
Serialize controller metadata outside the agent-visible mounts.

Args:
    config: SessionConfig identifying the audit directory.
    name: Controller-chosen JSON filename, never an arbitrary model path.
    value: JSON-serializable metadata; unsupported scalar values use str().
```

### `main`

[Source](../agents/session.py)

```python
def main()
```

```text
Run the single-session CLI invoked by R/designs.R.

Reads --session FILE and optional --offline. On an execution failure, records
failed session metadata and exits with a generic message. Never used to run
a complete scenario directly; the R pipeline controls freeze/transfer order.
```

## `agents/transport.py`

Count physical API attempts rather than only model-loop requests.

A single session owns this transport and its attempt budget. The allowlist is
HTTPS POST /v1/responses on api.openai.com; SDK retries are disabled separately.
The transport is not used for the standalone model-availability preflight.

### `CountedTransport`

[Source](../agents/transport.py)

```python
class CountedTransport
```

```text
Session-owned transport restricting destinations and counting retries.

Attributes:
    limit: Maximum physical outbound attempts in the whole session.
    retries: Maximum extra attempts per individual request.
    attempts: Number of physical attempts already started.
    transport: Owned httpx backend, with its own retries disabled by default.
```

### `CountedTransport.__init__`

[Source](../agents/transport.py)

```python
def __init__(self, limit: int, retries: int=2, transport=None)
```

```text
Configure a shared physical-request budget for one model session.

Args:
    limit: Maximum total outbound attempts, including transient retries.
    retries: Additional retries per request, still bounded by limit.
    transport: Optional async transport used by deterministic HTTP tests.
```

### `CountedTransport.handle_async_request`

[Source](../agents/transport.py)

```python
async def handle_async_request(self, request)
```

```text
Send only HTTPS POST /v1/responses to api.openai.com.

Args:
    request: httpx request whose body can be replayed for bounded retries.

Returns:
    Response from the underlying transport. Retries transport errors and
    HTTP 408/409/429/500/502/503/504; HTTP 520 is not retried here.

Raises:
    RuntimeError: Destination/endpoint is unsupported or the budget is spent.
```

### `CountedTransport.aclose`

[Source](../agents/transport.py)

```python
async def aclose(self)
```

```text
Release the owned underlying HTTP transport.

```
