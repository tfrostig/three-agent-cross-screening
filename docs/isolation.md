# Isolation and reproducibility boundaries

The statistical prompts are instructions, not a security boundary. PydanticAI
validates structured interfaces; Docker restricts filesystem, process, and
network access. The host R simulator/evaluator and Python controller are trusted.
Agent-authored R and reports are untrusted. This is container isolation, not a
formal guarantee against a compromised Docker daemon or kernel vulnerability.

## Information flow

1. The host R simulator saves truth and generation RNG streams in `private/`.
2. It writes two data-only RDS matrices into each session's input directory.
3. A fresh PydanticAI agent receives its dimensions, objective, and own tool
   results. Session dependencies hold only its input/work/audit references and
   restricted runner. Every session also has its own verified snapshot of the same
   curated methods library. No shared histories, observations, writable retrieval
   stores, or delegation tools exist.
4. `run_r` starts a fresh container. It mounts only that session's input, scratch
   R source, own writable workspace, and bounded output directory.
5. `check_design` stages regular bounded artifacts and executes them on source
   data. The controller records the successful artifact hashes.
6. PydanticAI validates the final manifest. Only after the run completes does
   the controller publish read-only frozen copies.
7. Target evaluation starts a fresh container with only the frozen R script,
   hypotheses, and current target observations. No design data or truth is
   mounted. The host validates returned CSVs again, checks frozen hashes, then
   scores the claims against target truth.
8. Reports escape agent text. They never execute agent Markdown as R Markdown.
9. `read_reference` resolves only allowlisted reference/section IDs from an immutable
   in-memory snapshot. It cannot open arbitrary paths, original PDFs, generator
   files, previous run results, or sibling observations. A common brief is injected
   into shared instructions; source excerpts are returned only on request.

## Controls

- New conversation history, agent instance, model fixture state, dependency
  object, workspace, and usage limits per session.
- Reference payloads are hash-verified before sessions start; their catalog digest
  enters run/cache identity. The exact brief/catalog are audited independently of
  the agent-visible R workspace. Reference metadata does not change file mounts.
- Stateless provider requests (`openai_store=False`), no shared previous-response
  or conversation IDs. Storage policy does not substitute for history isolation.
- R subprocesses get an explicit environment allowlist without provider keys or
  cloud credentials. Docker does not inherit the controller environment.
- The trusted Python controller may privately read the authorized `OPENAI_API_KEY`
  assignment in `.env`. It never shell-sources the file, exports its values, or
  includes them in manifests, tool arguments, or transcripts. Exported keys take
  precedence. Preflight returns availability only.
- Containers run as nobody with no network, capabilities, privilege escalation,
  host project mount, host PID sharing, or Docker socket.
- Read-only inputs, image root filesystem, and staged design. Separate temporary
  storage; one CPU, 2 GiB memory, 128-process limit, execution timeout, and log cap.
- Only regular allowlisted artifacts are accepted. Paths escaping the workspace,
  symbolic links, oversized files, duplicate hypotheses, and malformed results
  are rejected.
- Simulation seeds are never exposed. Agent execution seeds are independently
  generated and retained in private execution audit records.
- The Docker build context includes only its explicitly allowlisted runtime
  files; `.env` is excluded without being opened.

## Intended dependence

Agents share coordinate identities and the common n required by the specification.
Subgroup states are correlated through the specified joint mixture. These are
features of the experiment. Conditional on the realized effects and n, source
and target observations are independent; marginal latent-effect dependence is
not an agent communication channel.

## Tests

`scripts/test_sandbox.R` uses synthetic canaries to verify hidden host files are
unavailable, credentials absent, inputs/runtime read-only, Docker socket absent,
network access disabled, and execution deadlines enforced. It never reads `.env`.
Python tests verify dependency-specific tool dispatch, typed finalization,
path/symlink rejection, frozen hash checks, and physical request budgets.
The offline full study exercises all transfer routes and the report without
making any OpenAI API requests.

Passing checks establishes the tested software contract. It does not prove that
arbitrary p-values are statistically calibrated or that a method's claimed
FWER/FDR guarantee holds. One iteration cannot establish those guarantees.
