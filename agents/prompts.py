"""Assemble legacy-protocol prompts and export a historical workflow preview.

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
        root: Project root containing the prompts/legacy-*.txt templates.
        references: Optional verified session-local ReferenceLibrary.

    Returns:
        Tuple of statistical system prompt and shared execution instructions.
    """
    directory = root / "prompts"
    system = (directory / "legacy-system.txt").read_text(encoding="utf-8")
    instructions = (directory / "legacy-developer.txt").read_text(encoding="utf-8")
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
    """Export the legacy assembled prompt without running agents.

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
    text = ("# Legacy agent prompts\n\nHistorical workflow only. Current prompt: prompts/document-20261111.txt.\n\n"
            "## System prompt\n\n```text\n" + system + "```\n\n"
            "## Shared instructions, reference brief, and catalog\n\n```text\n"
            + instructions + "\n```\n\n## Data description supplied with run_r\n\n```text\n"
            + description + "\n```\n")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


def main():
    """Export current model input by default, or legacy prompts with --legacy.

    Accepts --output FILE and makes no provider requests or credential reads.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--legacy", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = args.output or Path("deliverables") / ("legacy-agent-prompts.md" if args.legacy else "current-agent-prompts.md")
    if args.legacy:
        write_prompt_preview(root, output)
    else:
        from agents.document_preview import export
        export(root, output)
    print(f"Prompt review: {output}")


if __name__ == "__main__":
    main()
