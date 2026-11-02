"""Load versioned prompt templates without reading environment files."""

import argparse
import ast
from pathlib import Path

from agents.models import SessionConfig
from agents.references import ReferenceLibrary


def load_prompts(root: Path, references: ReferenceLibrary | None = None) -> tuple[str, str]:
    """Read the common statistical and execution instructions."""
    directory = root / "prompts"
    system = (directory / "system.txt").read_text(encoding="utf-8")
    instructions = (directory / "developer.txt").read_text(encoding="utf-8")
    if references is not None:
        instructions += references.prompt_context()
    return system, instructions


def user_prompt(config: SessionConfig) -> str:
    """Describe only the dimensions and requested directional criterion."""
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
    """Export the actual shared prompts and R tool description for review.

    Args:
        root: Project directory containing prompts and the curated library.
        output: Markdown destination for the review copy.
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
    """Build a prompt review copy without loading credentials or calling a model."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("deliverables/revised-agent-prompts.md"))
    args = parser.parse_args()
    write_prompt_preview(Path(__file__).resolve().parent.parent, args.output)
    print(f"Prompt review: {args.output}")


if __name__ == "__main__":
    main()
