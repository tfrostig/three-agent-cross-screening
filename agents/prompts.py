"""Assemble versioned prompts and export an offline review copy.

System role, shared execution instructions, optional reference context, and
source-session task metadata are distinct inputs. Generator source, truth,
planning targets, sibling histories, and target outcomes never enter this text."""

import argparse
import ast
from pathlib import Path

from agents.models import SessionConfig
from agents.references import ReferenceLibrary


def load_prompts(root: Path, references: ReferenceLibrary | None = None) -> tuple[str, str]:
    """Load shared templates and optionally append approved reference context.

    Args:
        root: Project root containing prompts/system.txt and developer.txt.
        references: Optional verified session-local ReferenceLibrary.

    Returns:
        Tuple of statistical system prompt and shared execution instructions.
    """
    directory = root / "prompts"
    system = (directory / "system.txt").read_text(encoding="utf-8")
    instructions = (directory / "developer.txt").read_text(encoding="utf-8")
    if references is not None:
        instructions += references.prompt_context()
    return system, instructions


def user_prompt(config: SessionConfig) -> str:
    """Build the source session's dimensions and directional-discovery task.

    Args:
        config: SessionConfig with sample dimensions, criterion, and supplied alpha.

    Returns:
        Task text without generator truth, sibling data, target outcomes, or n's
        planning rationale. Source observations arrive only through the R tool.
    """
    if config.criterion == "FWER":
        criterion = ("Strong directional FWER: under your stated assumptions, control the "
                     "probability of at least one false directional discovery at alpha.")
    else:
        criterion = ("Directional FDR: target E[V / max(R, 1)] <= alpha, where V counts "
                     "false directional claims. Prefer practical BH with stated assumptions "
                     "and limitations; distinguish practical justification from a theorem.")
    return f"""Design a directional multiple-testing analysis using your available data.
Session identifier: {config.session_id}
Exposed sample size: {config.n}
Unexposed sample size: {config.n}
Number of measurements: {config.m}
Required criterion: {criterion}
Required family level: alpha = {config.alpha:.17g}. Use this supplied value without dividing again.
A false discovery includes a sign claim for a zero effect or an incorrect sign.
Select a frozen design using your observations. It will be applied to an
independent subgroup whose effects may differ. Aim for as many correct target
discoveries as possible subject to the requested criterion. Inspect your data, write the
required artifacts, check the contract, and finalize your design.
"""


def write_prompt_preview(root: Path, output: Path) -> None:
    """Export current assembled prompt text without running agents.

    Args:
        root: Project directory containing templates, curated pack, and tool source.
        output: Markdown review destination; parent directories are created.

    Reads the run_r docstring statically because it is part of model-visible data
    documentation; does not load credentials or send provider requests.
    """
    references = ReferenceLibrary.load(root / "references/agent-pack")
    system, instructions = load_prompts(root, references)
    tree = ast.parse((root / "agents/factory.py").read_text(encoding="utf-8"))
    tool = next(node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == "run_r")
    description = ast.get_docstring(tool)
    text = ("# Revised agent prompts\n\nFuture-run templates; prior run outputs are unchanged.\n\n"
            "## System prompt\n\n```text\n" + system + "```\n\n"
            "## Shared instructions, reference brief, and catalog\n\n```text\n"
            + instructions + "\n```\n\n## Data description supplied with run_r\n\n```text\n"
            + description + "\n```\n")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


def main():
    """Run the offline prompt-preview CLI.

    Accepts --output FILE, defaulting to deliverables/revised-agent-prompts.md.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("deliverables/revised-agent-prompts.md"))
    args = parser.parse_args()
    write_prompt_preview(Path(__file__).resolve().parent.parent, args.output)
    print(f"Prompt review: {args.output}")


if __name__ == "__main__":
    main()
