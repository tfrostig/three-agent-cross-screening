"""Build independent PydanticAI agents and register their typed tools.

The nested tool docstrings are model-visible experiment inputs. Host-only
maintainer docs live on the outer registration functions and in docs/agent-api.md."""

from pydantic_ai import Agent, ModelRetry, RunContext, ToolOutput

from agents.artifacts import artifact_hashes, write_artifact
from agents.models import AgentDependencies, DesignManifest, ToolResult


def build_agent(model, system_prompt: str, instructions: str):
    """Construct a session-local agent and register its capabilities.

    Args:
        model: PydanticAI model instance, live or deterministic fixture.
        system_prompt: Shared statistical role and scientific objective.
        instructions: Shared execution contract plus optional reference brief.

    Returns:
        A fresh Agent with strict DesignManifest output and session-bound tools.
    """
    agent = Agent(model, deps_type=AgentDependencies,
                  output_type=ToolOutput(DesignManifest, name="finalize_design", strict=True, max_retries=2),
                  system_prompt=system_prompt, instructions=instructions, retries=2)
    register_tools(agent)
    register_reference_tool(agent)
    register_validator(agent)
    return agent


def register_tools(agent):
    """Attach R exploration, artifact-writing, and contract-check tools.

    Args:
        agent: Fresh Agent to mutate with tool registrations.

    Tool descriptions below are model-visible prompt content. Keep maintainer
    documentation outside those descriptions unless changing the experiment.
    """
    @agent.tool
    def run_r(ctx: RunContext[AgentDependencies], code: str) -> ToolResult:
        """Explore your own data in a fresh R process with an initialized seed.

        Numeric matrices exposed and unexposed are preloaded. Rows are independent
        observations; columns are measurements. Matching column names identify the
        same measurements in target data. Row indices do not indicate matched
        subjects. n and m give the exposed row and column counts. Variables do not
        persist across calls; files in /work persist during design.

        Args:
            code: R code to execute on the supplied source observations.
        """
        deps = ctx.deps
        if deps.r_executions >= deps.config.limits["max_r_executions"]:
            raise RuntimeError("Exploratory R execution budget exhausted")
        if len(code.encode("utf-8")) > 131072:
            raise ModelRetry("R source exceeds 128 KiB")
        deps.r_executions += 1
        return deps.runner.execute("explore", code)

    @agent.tool
    def write_artifact_file(ctx: RunContext[AgentDependencies], path: str, content: str) -> str:
        """Write analysis.R, hypotheses.csv, or report.md in your own workspace."""
        try:
            write_artifact(ctx.deps.config.workspace, path, content)
        except ValueError as error:
            raise ModelRetry(str(error)) from error
        ctx.deps.checked_hashes.clear()
        return f"Wrote {path}"

    @agent.tool
    def check_design(ctx: RunContext[AgentDependencies]) -> ToolResult:
        """Validate your artifacts by running them against your own data."""
        return check_current_design(ctx.deps)


def register_reference_tool(agent):
    """Attach approved-section retrieval using only the current dependencies.

    Args:
        agent: Agent receiving a reference tool; no global library is shared.
    """
    @agent.tool
    def read_reference(ctx: RunContext[AgentDependencies], reference_id: str,
                       section_id: str = "overview") -> ToolResult:
        """Read an approved reference section, with citation and PDF page locator.

        Args:
            reference_id: Library ID listed in the shared reference catalog.
            section_id: Approved section ID; defaults to its overview.
        """
        if ctx.deps.references is None:
            raise ModelRetry("No curated reference library is configured")
        try:
            return ctx.deps.references.read(reference_id, section_id)
        except ValueError as error:
            raise ModelRetry(str(error)) from error


def check_current_design(deps: AgentDependencies) -> ToolResult:
    """Check executable structure and remember the exact successful artifact bytes.

    Args:
        deps: Mutable state for one session, including runner and repair budget.

    Returns:
        ToolResult from the source-data contract check, never target results.

    Raises:
        RuntimeError: The configured contract-repair budget is exhausted.
    """
    try:
        hashes = artifact_hashes(deps.config.workspace)
        result = deps.runner.execute("check")
    except ValueError as error:
        hashes = {}
        result = ToolResult(status="failed", error=str(error))
    if result.status == "ok" and hashes == artifact_hashes(deps.config.workspace):
        deps.checked_hashes = hashes
    else:
        deps.checked_hashes.clear()
        deps.repairs += 1
        if deps.repairs > deps.config.limits["max_contract_repairs"]:
            raise RuntimeError("Contract-repair budget exhausted")
    return result


def register_validator(agent):
    """Require final output to refer to currently checked artifact hashes.

    Args:
        agent: Agent receiving the final-output validator.

    A write invalidates the prior check; finalization cannot bypass a recheck.
    """
    @agent.output_validator
    def validate_output(ctx: RunContext[AgentDependencies], output: DesignManifest) -> DesignManifest:
        """Accept the manifest only while artifact hashes match the last check.
        """
        deps = ctx.deps
        try:
            hashes = artifact_hashes(deps.config.workspace)
        except ValueError as error:
            raise ModelRetry(str(error)) from error
        if hashes != deps.checked_hashes:
            deps.repairs += 1
            if deps.repairs > deps.config.limits["max_contract_repairs"]:
                raise RuntimeError("Contract-repair budget exhausted")
            raise ModelRetry("Run check_design successfully on the current artifacts first")
        return output
