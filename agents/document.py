"""Document-v2 sessions: one unchanged scientific prompt and source-only tools."""

import argparse
import asyncio
import dataclasses
import hashlib
import json
import os
import time
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict
from pydantic_ai import Agent, ModelRetry, RunContext, ToolOutput
from pydantic_ai.messages import ModelResponse, ToolCallPart
from pydantic_ai.models.function import FunctionModel

from agents.models import AgentDependencies, SessionConfig
from agents.document_state import atomic_json, validate_markdown, fixture_report, freeze, usage_from_messages, committed
from agents.runner import RRunner
from agents.runtime import live_resources, load_session, run_with_audit, write_audit


class Submission(BaseModel):
    """Artifact filenames for the completed design."""

    model_config = ConfigDict(strict=True, extra="forbid")
    script_file: Literal["analysis.R"]
    report_file: Literal["report.md"]


def hashes(directory):
    """Hash only bounded regular submission files.

    Args:
        directory: Source workspace or frozen directory.
    """
    result = {}
    for name in ("analysis.R", "report.md"):
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 262144:
            raise ValueError(f"Missing, linked, or oversized artifact: {name}")
        result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def task(config):
    """Return scenario metadata without additional scientific instructions.

    Args:
        config: Source-only session configuration.
    """
    return (f"Number of measurements: {config.m}\nExposed sample size: {config.n}\n"
            f"Unexposed sample size: {config.n}\nError criterion: {config.criterion}\n"
            f"Family level: {config.alpha:.17g}\n")


def build(model, prompt):
    """Register the two working tools and structural finalization.

    Args:
        model: Live model or deterministic fixture.
        prompt: Unchanged Section 2.1 text.
    """
    agent = Agent(model, instructions=prompt, deps_type=AgentDependencies,
                  output_type=ToolOutput(Submission, name="finalize_design", strict=True, max_retries=2))
    register_tools(agent)
    register_validation(agent)
    return agent


def register_tools(agent):
    """Register technical execution and artifact interfaces.

    Args:
        agent: Session-local agent.
    """
    @agent.tool
    def run_r(ctx: RunContext[AgentDependencies], code: str) -> dict:
        """Execute exploratory R with numeric matrices exposed and unexposed, n and m.

        Rows are independent observations, not matched subjects. Matching column
        names identify measurements. Each call uses a fresh process: variables do
        not persist; files under /work persist. Output is bounded and truncation
        is indicated. Only this session's observations are available.
        """
        deps = ctx.deps
        if deps.r_executions >= deps.config.limits["max_r_executions"]:
            raise ModelRetry("Exploratory R execution budget exhausted")
        if len(code.encode()) > 131072:
            raise ModelRetry("R source exceeds 128 KiB")
        deps.r_executions += 1
        return deps.runner.execute("explore", code).model_dump()

    register_artifact_tool(agent)


def register_artifact_tool(agent):
    """Register the artifact schema, including the required report sections.

    Args:
        agent: Session-local agent.
    """
    @agent.tool
    def write_artifact_file(ctx: RunContext[AgentDependencies], path: str, content: str) -> str:
        """Write analysis.R or report.md as UTF-8, at most 256 KiB per file.

        analysis.R exports hypotheses (data.frame: measurement_id character,
        direction integer +1 exposed>unexposed or -1 exposed<unexposed) and
        analyze(exposed, unexposed, alpha). No duplicate measurement-direction pairs.
        All parameters and dependencies on exploratory files must be embedded.
        analyze supports supplied matrix dimensions, including pooled inputs, and
        returns list(directional_results, outcome_results). directional_results
        columns: measurement_id, direction, p_value, adjusted_p_value, reject.
        outcome_results columns: measurement_id, adjusted_p_value, reject, one row
        per measurement. Both tables use logical reject = adjusted_p_value <= alpha.
        Outcome reject equals any directional rejection for that measurement.
        Nonselected outcomes have adjusted_p_value 1 and reject FALSE. The script
        supplies combined outcome values if both directions are present.
        report.md requires nonempty Markdown headings: Exploration findings;
        Hypothesis selection; Final procedure; Assumptions and limitations. Include
        source observations/numerical evidence actually used, the reproducible
        selection/direction rule and counts, justification of cutoffs or weights
        (or retaining everything), tests/correction/combination rules, assumptions
        and transfer limitations. Provide scientific rationale, not internal
        deliberation. These sections document the design rather than prescribe it.
        """
        if path not in ("analysis.R", "report.md") or len(content.encode()) > 262144:
            raise ModelRetry("Invalid artifact filename or size")
        destination = ctx.deps.config.workspace / path
        if destination.is_symlink():
            raise ModelRetry("Linked artifacts are forbidden")
        destination.write_text(content, encoding="utf-8")
        return f"Wrote {path}"


def register_validation(agent):
    """Inspect definitions without observations or analysis application.

    Args:
        agent: Session-local agent.
    """
    @agent.output_validator
    def validate(ctx: RunContext[AgentDependencies], output: Submission) -> Submission:
        deps = ctx.deps
        try:
            before = hashes(deps.config.workspace)
            validate_markdown(deps.config.workspace / "report.md")
            result = deps.runner.inspect()
            if result["status"] != "ok":
                raise ValueError(result.get("error") or "Definition inspection failed")
            if hashes(deps.config.workspace) != before:
                raise ValueError("Artifacts changed during inspection")
            deps.checked_hashes = before
            deps.runner.family = result["payload"]
            return output
        except (ValueError, RuntimeError) as error:
            deps.repairs += 1
            if deps.repairs > deps.config.limits["max_contract_repairs"]:
                raise RuntimeError("Structural repair budget exhausted") from error
            raise ModelRetry(str(error)) from error


class DocumentRunner(RRunner):
    """Add data-free definition inspection to the existing exploration runner."""

    def inspect(self):
        """Run the trusted document inspection bridge without calling analyze."""
        import subprocess
        from agents.runner import clean_environment
        import tempfile
        config = self.config
        self.calls += 1
        request = {"mode": "document-inspect", "workspace": str(config.workspace),
                   "input_dir": str(config.input_dir), "alpha": config.alpha,
                   "execution_seed": 1, "sandbox": config.sandbox,
                   "measurements": [f"v{i:04d}" for i in range(1, config.m + 1)]}
        path = config.audit_dir / f"inspection-{self.calls:03d}.json"
        output = path.with_name(path.stem + "-result.json")
        path.write_text(json.dumps(request))
        with tempfile.TemporaryDirectory() as home:
            subprocess.run(["Rscript", "--vanilla", "scripts/agent_tool.R", str(path), str(output)],
                           cwd=config.project_root, env=clean_environment(config.project_root, Path(home)),
                           capture_output=True, timeout=config.sandbox["timeout_seconds"] + 30, check=True)
        return json.loads(output.read_text())


def fixture(config):
    """Exercise real tools using prewritten fixture artifacts, without OpenAI.

    Args:
        config: Source-only session configuration.
    """
    script = (config.project_root / "tests/fixtures/document-analysis.R").read_text()
    script = script.replace("MEASUREMENT_COUNT", str(config.m)).replace("CORRECTION", "holm" if config.criterion == "FWER" else "BH")
    calls = [("run_r", {"code": "cat(dim(exposed), '\\n'); print(colMeans(exposed)[1])"}),
             ("write_artifact_file", {"path": "analysis.R", "content": script}),
             ("write_artifact_file", {"path": "report.md", "content": fixture_report()}),
             ("finalize_design", {"script_file": "analysis.R", "report_file": "report.md"})]
    turn = 0

    def respond(messages, info):
        nonlocal turn
        name, args = calls[min(turn, len(calls)-1)]
        turn += 1
        return ModelResponse(parts=[ToolCallPart(name, args, f"fixture-{turn}")])

    return FunctionModel(respond)


def exploration(config):
    """Export recorded exploration without executing report contents.

    Args:
        config: Session-local paths.
    """
    text = ["# Executed exploration\n"]
    for path in sorted((config.audit_dir / "exploration").glob("*.R")):
        result = json.loads((config.audit_dir / f"{path.stem}-result.json").read_text())
        text.extend([f"## {path.stem}\n", "````r\n" + path.read_text() + "\n````\n",
                     "````text\n" + json.dumps(result, indent=2) + "\n````\n"])
    return "\n".join(text)


async def execute(config, offline):
    """Run and freeze one document-v2 source design.

    Args:
        config: Session configuration containing no simulation truth.
        offline: Select deterministic fixture without credential access.
    """
    started = time.monotonic()
    prompt = (config.project_root / "prompts/system.txt").read_text()
    client = transport = None
    if offline:
        model = fixture(config)
    else:
        if not os.environ.get("OPENAI_API_KEY", "").strip():
            raise RuntimeError("Export OPENAI_API_KEY; document-v2 never reads .env")
        model, client, transport = await live_resources(config, exported_key=os.environ["OPENAI_API_KEY"].strip())
        transport.attempt_observer = lambda count: atomic_json(config.audit_dir / "api-attempts.json", {"attempts": count})
    deps = AgentDependencies(config, DocumentRunner(config))
    agent = build(model, prompt)
    write_audit(config, "prompts.json", {"instructions": prompt, "user": task(config)})
    try:
        result = await run_with_audit(agent, task(config), deps)
        freeze(config, deps.checked_hashes, deps.runner.family, exploration(config), hashes)
        usage = result.usage() if callable(result.usage) else result.usage
        write_audit(config, "session.json", {"status": "ok", "offline": offline,
                    "duration_seconds": time.monotonic()-started, "usage": dataclasses.asdict(usage),
                    "physical_api_attempts": transport.attempts if transport else 0})
    except BaseException as error:
        atomic_json(config.audit_dir / "session.json", {"status": "failed", "error": str(error),
                    "duration_seconds": time.monotonic()-started, "usage": usage_from_messages(config),
                    "physical_api_attempts": transport.attempts if transport else 0})
        raise
    finally:
        if client is not None:
            await client.close()


def main():
    """Run the document session CLI; record failures without exposing credentials."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", type=Path, required=True)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    config = load_session(args.session)
    if committed(config):
        return
    if any((config.audit_dir / name).exists() for name in ("api-attempts.json", "messages.json", "session.json")):
        raise SystemExit("Existing attempt retained; resume the controller, not the individual session")
    try:
        asyncio.run(execute(config, args.offline))
    except Exception as error:
        if not (config.audit_dir / "session.json").exists():
            atomic_json(config.audit_dir / "session.json", {"status": "failed", "error": str(error)})
        raise SystemExit("Document session failed; inspect session audit") from None


if __name__ == "__main__":
    main()
