---
title: 'K-team cross screening: three-agent simulation'
subtitle: 'Updated-prompt live experiment — analysis and results'
output: html_document
---

## 1. Simulation setting for three agents

We asked whether agents can design useful analyses for an independent subgroup and improve discoveries over the competitor that does not use agents.

Each experiment contains **three exposure subgroups**, each with its own independent sample from the population without exposure. The same m measurements are taken in every subgroup. Following the specification, we also call these three data subsets “studies” and the measurements “outcomes.”

| Parameter | Values used |
|:--|:--|
| Number of measurements, m | 20 or 100 for FWER control; 100 or 1,000 for FDR control |
| Hypothesis-state distribution | The two probability settings in the specification, described below |
| Sample-size planning target, c | 0.2, 0.6 and the subsequently agreed addition, 0.9 |
| Sample size, n | n exposed and n unexposed observations in each subset |
| Simulation iterations | One per setting; no additional validation draws |

**Both hypothesis-state distributions from the specification were included in the live run:**

- **Π(0, 0, 0) = 0.6, Π(1, 1, 1) = 0.1, all six remaining probabilities equal to 0.05 each.**
- **Π(0, 0, 0) = 0.9, Π(1, 1, 1) = 0.05, all six remaining probabilities equal to 0.05/6 each.**

The state (0, 0, 0) means no effect in any subgroup; (1, 1, 1) means an effect in all three. The six remaining states are (0, 0, 1), (0, 1, 0), (0, 1, 1), (1, 0, 0), (1, 0, 1) and (1, 1, 0). Thus Π(0, 0, 0) is the probability of no effect anywhere, giving a 40% or 10% probability of an effect in at least one subgroup, respectively.

Table headings use **Π(0, 0, 0) = 0.6** or **Π(0, 0, 0) = 0.9** as a short reference to the corresponding **complete distribution above**. FDR/FWER specifies the requested error control independently of these probabilities. A setting combines a distribution, error criterion, m and c. Realized effect proportions vary because the states are sampled.

The smallest n satisfying the specification's planning formula was used. [Supplement B](supplement.html#b-simulation-and-workflow) gives the generator and formula; [H](supplement.html#h-execution-failures-and-planning) lists actual sample sizes.

{{COVERAGE}}

## 2. The analysis using the agents' outputs

For each setting, three isolated PydanticAI sessions used **gpt-6.1-sol**. Agent j explored only subset j using R and submitted a reusable R analysis design plus a Markdown report explaining its choices. Its objective was to maximize correct directional discoveries in independent target observations, subject to the supplied criterion and level.

1. **Design.** Each agent fixed its one-sided hypotheses, alternative directions, tests and complete multiple-testing procedure. The framework checked the interface and froze the artifacts.
2. **Select the winner design.** For study i, apply the other two agents' designs to the combined data excluding study i. Choose the design with the most individual discoveries; ties use the smaller source-agent index.
3. **Apply the winner design.** Apply it unchanged to study i. Repeat for all three studies.

| Study being analyzed | Combined data used to select its design | Candidate designs |
|:--|:--|:--|
| Study 1 | Subsets 2 + 3 | Agents 2 and 3 |
| Study 2 | Subsets 1 + 3 | Agents 1 and 3 |
| Study 3 | Subsets 1 + 2 | Agents 1 and 2 |

For study 3, for example, designs 1 and 2 compete on combined subsets 1+2. Study 3 is used only afterward to evaluate the winner. Exposed samples are combined separately from unexposed samples.

**Only results on the study being analyzed contribute to the reported discoveries.** The combined-data counts select the design. R code performs selection and application; agents exchange no conversations and receive no combined-data or target results. Both executions use α/3=0.05/3. See [Supplement B](supplement.html#b-simulation-and-workflow) for validation/isolation and [C](supplement.html#c-exact-instructions-and-interfaces) for exact instructions.

## 3. Competitor that does not use agents

Following Section 3 of the specification, the competitor applies multiple comparisons **to each subset separately**, using two-sided p-values and ignoring direction: **BH for FDR control and Holm for FWER control**. In this implementation, the individual tests are independent-sample Welch t-tests. Discoveries have adjusted p-values at most 0.05/3.

The competitor uses all measurements and observations in each subset, analyzes **all three subsets separately**, and receives exactly the same six summaries as the agents. Directional errors are reported only for procedures making directional claims. The original agent cycle and a truth-informed oracle are additional comparisons in [Supplement E](supplement.html#e-selection-and-secondary-comparisons).

## 4. The six measures of “power” in Section 3

The names below follow the specification. These are realized counts from one iteration.

### Lower bounds

For each outcome, its **lower bound** is the number of subsets with adjusted p-values at most α/3. For example, significance in two subsets gives a lower bound of 2 on the number of subgroups with an effect.

- **Total number of lower bounds:** add these lower-bound values across outcomes. One outcome significant in all three subsets contributes 3.
- **Total number of correct lower bounds:** add a lower bound only if it does not exceed the number of false null hypotheses for that outcome—that is, the number of subgroups with a true nonzero effect. Otherwise its contribution is zero.

For one outcome with true effects in **two** subgroups:

| Lower bound reported | Contribution to total number of lower bounds | Contribution to total number of correct lower bounds |
|--:|--:|--:|
| 1 | 1 | 1 |
| 2 | 2 | 2 |
| 3 | 3 | 0 |

Correctness here concerns the lower bound, not the identities of the significant subsets. It is therefore different from counting individually correct subset discoveries.

### Global null discoveries

The **global null** for an outcome says that its exposure effect is zero in all three subgroups.

- **Number of global null discoveries:** outcomes for which the global null is rejected. With the specification's aggregation, this occurs when at least one subset has adjusted p-value at most α/3. Count each outcome once.
- **Number of true global null discoveries:** those discoveries for which the global null really is false—there is a nonzero effect in at least one subgroup.

### Replicability discoveries

- **Number of replicability discoveries:** outcomes declared to have effects in at least two subgroups. With the specified aggregation, at least two subsets must have adjusted p-values at most α/3. Count each outcome once.
- **Number of true replicability discoveries:** those discoveries for which effects truly exist in at least two subgroups. Matching directions are not required here.

For example, one outcome significant in all three subsets contributes **3** to the total number of lower bounds, **1** global null discovery and **1** replicability discovery. These summarize the same findings and should not be added together.

Formulas and wrong-subset/direction examples are in [Supplement A](supplement.html#a-measures-and-worked-examples). The normalized study-count recovery score agreed later is retained in [Supplement I](supplement.html#i-additional-study-count-recovery); it is **not one of the specification's six measures**.

## 5. Worked example: what the six measures count

This is an **illustration, not a simulation result**. Suppose a procedure reports the following for three outcomes:

| Outcome | Subgroups with a true effect | Subsets with a discovery | Lower bound |
|:--|:--|:--|--:|
| A | 1 and 2 | 1 and 2 | 2 |
| B | 3 only | 1 and 3 | 2 |
| C | None | 2 only | 1 |

The resulting six measures are:

| Measure | Value | How it is obtained |
|:--|--:|:--|
| Total number of lower bounds | 5 | Add 2 + 2 + 1 |
| Total number of correct lower bounds | 2 | A contributes 2; B and C overstate the true count and contribute 0 |
| Number of global null discoveries | 3 | A, B and C are each discovered in at least one subset |
| Number of true global null discoveries | 2 | A and B truly have an effect somewhere; C does not |
| Number of replicability discoveries | 2 | A and B are each discovered in at least two subsets |
| Number of true replicability discoveries | 1 | Only A truly has effects in at least two subgroups |

Outcome B illustrates the distinction: rejecting its global null is correct because it has an effect in subgroup 3, but its replicability claim is false because it has an effect in only one subgroup.

## 6. Results for the six measures

**Agents** and **Competitor (Welch)** are separate columns for two approaches evaluated on the same observations. Each cell contains one count. The columns compare procedures; they are not a fraction or an uncertainty interval.

Each table states the probability setting, requested error criterion and number of complete settings. The six row labels have exactly the meanings defined above.

{{PRIMARY_TABLE}}

These totals sum across settings, so larger m contributes more counts. The m=100 FWER/FDR settings share observations; the columns are not independent replications. Results for every individual setting are in [Supplement F](supplement.html#f-detailed-results-and-file-guide), including a direct [replicability comparison table](supplement.html#per-setting-replicability-results).

{{RESULTS_NARRATIVE}}

## 7. Interpretation

{{DESIGN_NARRATIVE}}

The method inventory identifies choices of directions, weights, allocation of the error level and testing order. Small weights or sequential stopping can restrict discovery opportunities even when every outcome belongs to the declared family. Executable and auditable designs are distinct from evidence of improvement over the competitor.

The verbal reports often gave explicit numerical rules and working-model motivations. These are inspectable choices, not evidence of optimal transfer: effects can disappear or change magnitude between subgroups. [Supplement D](supplement.html#d-agent-methods-code-and-rationales) preserves the original explanations, code, full design inventory and additional checks of which target directions remained eligible.

Validation checked executable/reporting consistency, not every statistical assumption or proof. **One iteration does not estimate long-run FWER/FDR.** Study-level FDR control alone does not establish FDR control for replicability claims. Historical comparisons are separate because the workflow also changed.

## 8. Supporting material

{{SESSION_SUMMARY}}

| Detail | Location |
|:--|:--|
| Six measures, formulas and examples | [Supplement A](supplement.html#a-measures-and-worked-examples) |
| Simulation, implementation and validation | [Supplement B](supplement.html#b-simulation-and-workflow) |
| Exact prompt, tools and output schemas | [Supplement C](supplement.html#c-exact-instructions-and-interfaces) |
| Agent choices, verbal reports, R code and exploration | [Supplement D](supplement.html#d-agent-methods-code-and-rationales) |
| Winner designs, original cycle and oracle | [Supplement E](supplement.html#e-selection-and-secondary-comparisons) |
| Every setting, outcome and error count | [Supplement F](supplement.html#f-detailed-results-and-file-guide) |
| Additional historical comparison | [Supplement G](supplement.html#g-historical-comparison) |
| Failures, resources and sample sizes | [Supplement H](supplement.html#h-execution-failures-and-planning) |
| Additional study-count recovery score | [Supplement I](supplement.html#i-additional-study-count-recovery) |

The editable sources are [report.Rmd](report.Rmd) and [supplement.Rmd](supplement.Rmd). The [directory guide](README.md) maps the accompanying files. This revision changes terminology and presentation; numerical results and original agent artifacts are unchanged.
