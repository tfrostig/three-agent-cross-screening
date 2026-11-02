# Prompt and reference revision

This revision prepares new runs. It does not change the saved first experiment,
its reports, or its frozen agent outputs. Use a new run directory.

The system prompt prioritizes correct discoveries in the target subgroup subject
to the requested criterion. It presents full-family testing, screening, weights,
and hierarchical procedures as possibilities rather than a required comparison.
The agent must explain any design choice it actually makes. BH is the practical
FDR preference, with explicit assumptions and limitations rather than an assertion
of arbitrary-dependence control.

The formal theta/null-hypothesis block is omitted from shared instructions. The
matrix description is documented in the `run_r` tool, where the model receives it
with the executable interface. The artifact contract retains plain direction
encoding: +1 is a higher exposed population mean; -1 is a lower exposed population
mean. The CSV schema, population-mean estimand, and transfer cycle are unchanged.
Any fixed weights or hierarchy settings belong in the frozen analysis and report.

`deliverables/revised-agent-prompts.md` presents the actual system prompt, fully
assembled shared instructions, reference catalog, and R tool data description in
one review copy. Regenerate it with `poetry run python -m agents.prompts`.

## Reference library

Every session receives the same brief from `references/agent-pack/brief.md` and
the catalog of available reference IDs. Optional `read_reference(reference_id,
section_id="overview")` calls return approved summaries or source excerpts, with
citations and PDF page locators. These are local files, not a GitHub URL and not a
network retrieval service. Only named catalog sections can be read. Requests use
the existing tool/API budgets, not the R exploration budget.

The two-team study is the primary design example. It illustrates test selection,
scientific prioritization, gatekeeping, and independent confirmation. The research
proposal supplies motivation for global-null and replicability research, but its
full text, preliminary simulations, results, and figures are excluded from agent
access. The other papers provide methodological orientation and their own
conditions; methods needing several studies' p-values are not advertised as
directly executable from a single source subgroup.

The original PDFs remain unchanged. Cards are curated summaries, not quotations.
Excerpts are extracted from specified PDF pages with whitespace normalized,
watermark-only lines removed, and Symbol-font alpha/equality glyphs transcribed.
The scanned cross-screening abstract is cropped to exclude sidebar metadata.
The shared brief is background, separated from
instructions with explicit delimiters, following the
[official OpenAI prompt engineering guidance](https://developers.openai.com/api/docs/guides/prompt-engineering).
This does not turn references into instructions or grant access to another agent.

The catalog hashes every approved payload. Each session snapshots and verifies
the library before model use. Its audit contains the exact injected brief and
catalog identity, while conversation logs retain requested sections. Run and
design cache identities include the library digest. After editing a card or the
brief, rebuild and verify the catalog from the project root:

```sh
Rscript --vanilla scripts/build_reference_pack.R
```

The PDF extraction tool `pdftotext` is required only to rebuild excerpts on the
trusted host. It is not installed or invoked by agent-generated R code. Runtime
sessions use only the prepared pack and existing dependencies.

## Future comparisons

The updated default configuration requests BH first and BY second for FDR
baselines, for both Welch and the known-variance z reference. New FDR method IDs
end in `_bh` or `_by`; the report displays correction priority. FWER baselines
retain Holm. Configurations omitting `baseline_fdr_methods` retain BY-only
numerical behavior. The direct R baseline helper also defaults to BY for
compatibility with deterministic replays of the original experiment.

No aggregation or replicability decision stage has been added. The library
explains that broader motivation without claiming the current cycle implements
the proposal's additional procedures. No live model runs are part of this update.
