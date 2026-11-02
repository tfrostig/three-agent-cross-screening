---
title: Can agents conduct a statistical analysis?
subtitle: First simulation run — architecture, findings, and limitations
date: 17 October 2026
lang: en
---

The agents produced 24 executable analyses with explicit statistical assumptions and multiplicity procedures. Their analyses were coherent under their stated models, but this run does not establish general error control. They also did not improve on a simple Welch baseline. The main performance limitation was which hypotheses they selected for transfer.

## Experiment

We followed the supplied specification: three groups, each with exposed and control samples, and eight scenarios spanning FWER or FDR control, measurement counts of 20, 100, or 1,000, and planning targets c = 0.2 or 0.6. There was one experiment per scenario. Matching m = 100 scenarios shared observations across objectives, with separate agent sessions.

The data were Gaussian with unit variances and a mixture of null and positive effects. Effects could be present in one group and absent in another; their nonzero magnitudes were independent across groups conditional on presence. Sample sizes were chosen using the specified minimum-power calculation. The agents were given none of this generator information.

## Agent architecture

An R controller generated the data, assigned source observations, and retained truth for evaluation. For each scenario it launched three independent Python/PydanticAI sessions using gpt-6.1-sol. Each had its own conversation, dependency object, and workspace.

Each session received three prompt components together: a **shared system prompt** defining the analysis-design role; **shared instructions** specifying the estimand, software contract, tools, and freezing rules; and a **session user message** supplying dimensions, testing objective, and q = 0.05/3. In PydanticAI these entered as `system_prompt`, `instructions`, and the run's user prompt, respectively. “Shared” describes identical text, not shared state or communication.

The model controlled a tool loop: run R on its source observations, inspect returned output or errors, revise its choices, and write the analysis. It could choose hypotheses, directions, tests, and multiplicity procedures rather than selecting from a prescribed menu. It submitted three artifacts: `analysis.R`, `hypotheses.csv`, and a scientific explanation. A contract-checking tool tested their execution; PydanticAI required a structured final manifest and a successful check of the current files. Multiple tool calls were allowed within each session.

R code executed in restricted Docker containers with no network, credentials, simulation truth, or sibling workspace. Each accepted design was frozen and hashed. After all three sessions finished, the controller applied the frozen procedures in fresh containers using the cycle **1 → 2, 2 → 3, 3 → 1**. Target evaluation involved no model calls and returned no results for redesign. The transferred object was an executable procedure, not a conversation with the next agent.

## Did they conduct a proper analysis?

**Execution:** all 24 sessions produced designs that passed the executable contract and completed target evaluation. The live run took approximately 40.5 minutes and 175 API attempts. Passing these checks establishes that the code ran and followed the interface; it does not establish statistical validity.

**Statistical reasoning:** the agents supplied directional hypotheses, complete multiplicity procedures, and written assumptions and limitations. All FWER designs used Holm and all FDR designs used BY. Their analyses used conventional t-based or permutation arguments, with several choosing conservative calibrations. The exact test constructions are not central to the present assessment.

**Scope of justification:** their validity arguments depended on normality or a common-shape shift model, neither supplied in the prompts. These assumptions were compatible with the generated data, but were not established by inspecting the source observations. The evidence therefore supports the ability to implement analyses with conditional statistical justifications, rather than valid inference under only the information supplied to the agents.

## Results

We compared four procedures on the same target observations, at the same per-family level with Holm or BY as appropriate:

- **Agent:** its frozen hypothesis list and complete analysis.
- **Same list:** replace only its target test with Welch.
- **Welch screen:** rank source Welch p-values, retain the same coordinate count and direction policy, then test with Welch on the target.
- **Full Welch:** test both directions for every target measurement, correcting over 2m hypotheses separately in each group.

The two screened Welch comparisons were retrospective replays. They used saved observations and inherited the agents' shortlist sizes. No observations were pooled across groups.

The table reports realized power across the three target groups; n is the exposed sample size and also the control sample size within each group.

{{CONCISE_RESULTS}}

The agent procedures did not outperform full Welch in any scenario. Replacing their target tests with Welch gave modest improvements. A simple Welch screen performed similarly to the agent approach.

For FDR, m = 1,000 and c = 0.6, the agents made 196 discoveries, including one false discovery; full Welch made 460, including two. No false discoveries occurred in the FWER scenarios for these four procedures. These are realized outcomes from one experiment per scenario, not estimates of long-run error rates.

## What this experiment tells us

The agents could explore data, write and repair executable analyses, and articulate statistical assumptions. We found no advantage from their design choices over the specified statistical comparators in this setting.

Screening was a major limitation. At c = 0.6, the frozen agent lists contained the correct direction for only about 43–50% of true target effects. This limited their attainable power before target testing began. Source screening reduced multiplicity but excluded effects that were active or more detectable in the target group. The small gains from replacing only the target test support this interpretation.

The next assessment should distinguish executable correctness, validity of the statistical argument, and discovery performance. Repeated simulations are needed to evaluate error control and the stability of these comparisons; the present run cannot establish those properties. No human benchmark or prompt ablation was performed.

The supplement contains the exact prompts and three examples of agent code, written explanations, and recommendations copied from the frozen outputs. Frozen code, conversations, checks, and scores remain in the saved run; this report rebuilds its results from those records without new model calls.
