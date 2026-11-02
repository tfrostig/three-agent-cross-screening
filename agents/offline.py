"""Deterministic provider fixture for the real PydanticAI tool loop.

Prewritten artifacts come from R/designs.R, not a live model. Each model has a
private turn counter. Offline success validates wiring and contracts, not the
scientific quality or power of an autonomous analysis."""

import json

from pydantic_ai.messages import ModelResponse, ToolCallPart
from pydantic_ai.models.function import FunctionModel


def offline_model(with_references: bool = False):
    """Create an independent deterministic provider for software checks.

    Args:
        with_references: Add an initial approved-reference retrieval step.

    Returns:
        FunctionModel that explores, checks prewritten fixture artifacts, and
        finalizes. It does not invent a scientific method or call OpenAI.
    """
    turn = 0

    def respond(messages, info):
        """Advance this fixture's private turn counter and emit the next tool call.
        """
        nonlocal turn
        turn += 1
        if with_references and turn == 1:
            return ModelResponse(parts=[ToolCallPart("read_reference", {"reference_id": "two-team"}, "reference")])
        step = turn - int(with_references)
        if step == 1:
            return ModelResponse(parts=[ToolCallPart("run_r", {"code": "cat(dim(exposed), '\\n')"}, "explore")])
        if step == 2:
            return ModelResponse(parts=[ToolCallPart("check_design", {}, "check")])
        manifest = {"script_file": "analysis.R", "hypotheses_file": "hypotheses.csv",
                    "report_file": "report.md", "test_summary": "Fixture: directional Welch t-tests",
                    "multiplicity_summary": "Fixture: Holm for FWER or BY for FDR",
                    "assumptions": ["Independent normal observations; Welch approximation"],
                    "limitations": ["OFFLINE FIXTURE: no live model designed this procedure"]}
        return ModelResponse(parts=[ToolCallPart("finalize_design", json.dumps(manifest), "final")])

    return FunctionModel(respond)
