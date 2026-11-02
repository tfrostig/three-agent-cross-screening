"""Session-local PydanticAI agents and typed R tools."""

from pydantic_ai import Agent, ModelRetry, RunContext, ToolOutput

from agents.artifacts import artifact_hashes, write_artifact
from agents.models import AgentDependencies, DesignManifest, ToolResult


def build_agent(model, system_prompt: str, instructions: str):
    """Construct a fresh agent without shared conversation state."""
    agent = Agent(model, deps_type=AgentDependencies,
                  output_type=ToolOutput(DesignManifest, name="finalize_design", strict=True, max_retries=2),
                  system_prompt=system_prompt, instructions=instructions, retries=2)
    register_tools(agent)
    register_reference_tool(agent)
    register_validator(agent)
    return agent


def register_tools(agent):
    """Register only the session-bound R and artifact capabilities."""
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
    """Register bounded access to the session-local reference snapshot."""
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
    """Record hashes only after a successful contract execution."""
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
    """Require a successful current-artifact check before final output."""
    @agent.output_validator
    def validate_output(ctx: RunContext[AgentDependencies], output: DesignManifest) -> DesignManifest:
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
