# Three-agent statistical analysis experiment: shared results

Start with **[the concise comparison](summary/summary.html)**. This package contains
two completed runs: the original instructions and revised instructions, evaluated
on the same simulated observations. There are eight scenarios and 24 successful
agent designs in each run. Each scenario has one iteration, with no additional
validation draws. The model was `gpt-6.1-sol`.

## Suggested reading order

1. Read `summary/summary.html` for the question, architecture, results, and limits.
2. Read `examples/README.md` for two actual revised-agent designs and their rationale.
3. Open `runs/live-revised-20261101/report.html` for the revised run's full report.
4. Inspect an agent's `frozen/report.md`, then `analysis.R` and `hypotheses.csv`.
5. Use `audit/exploration/` for its exploratory R code and matching result JSON files.
6. Consult `runs/live-first/` when comparing with the original behavior.

HTML files open locally in a browser after the ZIP is extracted. Markdown and R
files open in a text editor; CSV files open in R or a spreadsheet application.
The frozen agent scripts and exploratory snippets are supplied for inspection;
they are not executed when any report is opened or rendered.

## Directory map

| Directory or file | What it contains and how to use it |
|:---|:---|
| `summary/` | Concise comparison in HTML, Markdown, and portable R Markdown; `comparison.csv` supplies the eight-scenario table. Start here. |
| `examples/` | Links and commentary for one weighted full-family design and one two-measurement shortlist. Commentary is ours; the linked `report.md` files are the agents' own explanations. |
| `methods/` | Architecture, isolation, prompt revision notes, and the revised curated reference pack. Exact per-session prompts are in each agent's audit folder. |
| `runs/live-revised-20261101/` | Revised run completed 1 November 2026. Main result set. |
| `runs/live-first/` | Original run started 17 October 2026. Comparator, not the current prompts. |
| `MANIFEST.csv` | SHA-256 hashes, file sizes, original relative paths, and whether each exported file is unchanged, path-sanitized, or generated. The manifest does not hash itself. |

## Inside each run

| Path | Meaning |
|:---|:---|
| `report.html` | Already-rendered full report, including frozen scientific explanations. |
| `scores.csv` | One row per method, source/target route, and scenario. Agent results and baseline results are separate rows. |
| `global-scores.csv` | Summed outcomes across the three target groups, with scenario-level realized power and FDP. These are not estimated FWER or FDR. |
| `scenarios.csv`, `planning.csv` | Scenario definitions, sample sizes, and planning information. `c` is a planning power target; `n` is the sample size per exposed/control arm in each group. |
| `run.json`, `completion.json` | Run configuration and completion metadata; paths in exported copies are placeholders. |
| `usage.csv` | Model usage and timing for the retained sessions. |
| `exploration-index.csv` | Each saved exploratory call, its R file, request/result paths, status, and source hash. All paths are relative to its run folder. |
| `scenarios/<scenario>/agent-1/`, `agent-2/`, `agent-3/` | Three separate source-agent sessions. Source 1 tests target 2; source 2 tests target 3; source 3 tests target 1. |
| `scenarios/<scenario>/evaluation/` | Per-hypothesis target outputs and execution metadata for agents and baselines. Baseline files identify their target group in the filename. |

The revised run also includes `agent-designs.csv` (method summaries, directions,
coverage, tool counts), `comparison.csv`, and `infrastructure-retries/`. One session
failed with an upstream HTTP 520 after one exploratory call and was rerun before
any design was frozen. Its partial history is retained separately. The 24 retained
session usage rows exclude complete usage for that failed attempt, which was not
available. Other completed designs were not rerun.

Within an agent directory:

- `frozen/analysis.R`: the final reusable target-analysis code.
- `frozen/hypotheses.csv`: the frozen measurement IDs and directions; +1 means a
  higher exposed mean, -1 a lower exposed mean.
- `frozen/report.md`: the agent's scientific explanation, assumptions, and limitations.
- `frozen/frozen.json`: the final structured summary and original artifact hashes.
- `audit/prompts.json`: exact system, shared instructions, and session message.
- `audit/messages.json`: recorded model/tool exchanges, with local paths sanitized.
- `audit/session.json`: session completion, model usage, and final manifest.
- `audit/references.json`: revised-run brief/catalog provenance, where present.
- `audit/exploration/execution-NNN.R`: exact R source sent for exploration.
- `audit/execution-NNN.json` and `execution-NNN-result.json`: request/seed and
  observed output/errors. These include exploration and contract-check calls;
  use the exploration index to find exploratory code specifically.

Exploration used fresh R containers with `exposed` and `unexposed` already loaded.
Files under `/work` persisted during that session; R variables did not. A snippet
may therefore depend on a previous session file and is not a standalone script.

## How to interpret the comparisons

All three designs were frozen before the cycle **1→2, 2→3, 3→1**. Target results
were not returned for redesign. Agents did not communicate or pool observations.
The full Welch baseline tests all measurements in each target group separately,
including both directions, at the same `0.05/3` family level. It does not combine
the observations of Groups 1–3.

Original FDR agents used BY. Revised FDR instructions prefer practical BH; the
revised run includes full Welch BH and BY comparators. FWER comparisons use Holm.
The known-variance z reference additionally knows variance information withheld
from agents. Thus a comparison with that reference is not an equal-information
comparison. The prompt, reference context, and FDR preference changed together;
this is not a prompt-only experiment or a human-versus-agent comparison.

Successful execution establishes the software contract, not statistical validity.
One simulation realization cannot establish long-run error-rate control or a
reliable performance advantage. Inspect the agents' assumptions alongside their
discovery counts.

## What is deliberately absent

No credentials, `.env`, private simulation truth RDS files, input matrices,
workspaces, cache state, full PDFs, or internal research proposal are included.
The included audit output still contains summaries of synthetic observations.
Frozen artifacts and exploratory R source are byte-identical to the originals;
local paths in other exported text files are replaced with placeholders.
Consequently this is a review package, not a resumable execution archive.

To regenerate the concise summary without OpenAI or Docker, open
`summary/summary.Rmd` in RStudio and knit it, or run:

```r
rmarkdown::render("summary/summary.Rmd")
```

This uses only the CSV tables in the extracted bundle and requires the R packages
`rmarkdown` and `knitr`, plus Pandoc. The code repository separately provides the
full simulation and agent implementation:
[tfrostig/three-agent-cross-screening](https://github.com/tfrostig/three-agent-cross-screening).
