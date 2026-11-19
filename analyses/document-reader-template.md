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

**Why can sample-size planning be undefined?** By chance, a simulated study can have no true effects. Under Π(0,0,0)=0.9, each outcome has probability 0.075 of an effect in a particular study; with m=20, the probability of no effects in that study is 0.925²⁰ ≈ 21%. The planning formula averages power over true effects, so it is undefined for such a study. These draws were retained without redrawing; they are counted separately from agent execution failures.

## 2. The analysis using the agents' outputs

For each setting, three isolated PydanticAI sessions used **gpt-6.1-sol**. Agent j explored only subset j using R and submitted a reusable R analysis design plus a Markdown report explaining its choices. Its objective was to maximize correct directional discoveries in independent target observations, subject to the supplied criterion and level.

1. **Design.** Each agent fixed its one-sided hypotheses, alternative directions, tests and complete multiple-testing procedure. The framework checked the interface and froze the artifacts.
2. **Select the winner design.** For study i, apply the other two agents' designs to the combined data excluding study i. Choose the design rejecting the most distinct outcomes, counting an outcome once even if both directions reject; ties use the smaller source-agent index.
3. **Apply the winner design.** Apply it unchanged to study i. Repeat for all three studies.

| Study being analyzed | Combined data used to select its design | Candidate designs |
|:--|:--|:--|
| Study 1 | Subsets 2 + 3 | Agents 2 and 3 |
| Study 2 | Subsets 1 + 3 | Agents 1 and 3 |
| Study 3 | Subsets 1 + 2 | Agents 1 and 2 |

For study 3, for example, designs 1 and 2 compete on combined subsets 1+2. Study 3 is used only afterward to evaluate the winner. Exposed samples are combined separately from unexposed samples.

**Only results on the study being analyzed contribute to the reported discoveries.** The combined-data counts select the design. R code performs selection and application; agents exchange no conversations and receive no combined-data or target results. Both executions use α/3=0.05/3. See [Supplement B](supplement.html#b-simulation-and-workflow) for validation/isolation and [C](supplement.html#c-exact-instructions-and-interfaces) for exact instructions.

## 3. Competitor that does not use agents

Following Section 3 of the specification, the competitor uses a fixed procedure. For **each study separately**, we:

1. Use all exposed and unexposed observations in that study and test **all m outcomes** with two-sided Welch t-tests.
2. Adjust the m p-values using **Holm for FWER** or **BH for FDR**. Declare discoveries at adjusted p-value ≤0.05/3.
3. Repeat for studies 1, 2 and 3, then aggregate the three discovery lists using the same six measures as for agents (Section 4).

### What differs between the two approaches?

| Decision | Agents (winner design) | Competitor (Welch) |
|:--|:--|:--|
| How is the procedure chosen for study i? | The other two source designs compete on their combined observations; the winner is frozen before testing i | The same predefined Welch/Holm or Welch/BH procedure is used in every study |
| Which hypotheses are tested? | The agent's frozen outcomes and one-sided directions, with its chosen weights, ordering and correction | Every outcome, two-sided, with ordinary Holm or BH |
| Which observations confirm discoveries in study i? | Only study i's exposed and unexposed observations | Only study i's exposed and unexposed observations |
| What is finally reported? | Results from all three held-out studies, aggregated at the outcome level | Results from all three separately tested studies, aggregated identically |

When an agent also chooses Welch tests, differences come from its frozen hypothesis choices, directions, weights, multiplicity procedure and design selection. Both approaches use a family level of 0.05/3 in each study. Neither pools all three studies into one final test. Agents make directional claims; the competitor makes two-sided claims. The six main measures count outcomes without requiring matching directions; directional errors are reported separately for agents. The original cycle and truth-informed oracle are additional comparisons in [Supplement E](supplement.html#e-selection-and-secondary-comparisons).

## 4. The six measures of “power” in Section 3

These definitions apply **separately and identically to each approach**, for one simulation setting. Let j∈{1,2,3} index studies and i∈{1,…,m} index outcomes. Write

\[
h_{ji}=\mathbf1\{\eta_{ji}\ne0\},\qquad r_i=\sum_{j=1}^{3}h_{ji}.
\]

Thus \(r_i\) is the true number of subgroups with an effect on outcome i. Let \(P'_{ji}\) be its outcome-level, multiplicity-adjusted value from the final analysis of study j: the frozen design's value for agents, or Holm/BH-adjusted two-sided Welch value for the competitor. A nonselected outcome has value 1. With α=0.05, define

\[
D_{ji}=\mathbf1\{P'_{ji}\le\alpha/3\},\qquad L_i=\sum_{j=1}^{3}D_{ji}.
\]

\(L_i\) is the **reported lower bound** on \(r_i\), counting each study once even if both directions reject. It is correct for scoring when \(L_i\le r_i\); correctness concerns the count, not which studies or directions were discovered.

Table 1 of the supplied document combines the three adjusted values as

\[
G_i=\min\{1,3\min_jP'_{ji}\},\qquad
R_i=\min\{1,3\min_{j<k}\max(P'_{ji},P'_{ki})\}.
\]

The **global null** is \(r_i=0\) and the **replicability null** is \(r_i\le1\). Therefore \(G_i\le\alpha\) is equivalent to \(L_i\ge1\), and \(R_i\le\alpha\) is equivalent to \(L_i\ge2\). These claims do not require matching directions across studies. No additional correction is applied after this aggregation.

| Name in the specification | Definition across all outcomes |
|:--|:--|
| Total number of lower bounds | \(\displaystyle B=\sum_{i=1}^{m}L_i\) |
| Total number of correct lower bounds | \(\displaystyle B_{\mathrm{correct}}=\sum_{i=1}^{m}L_i\mathbf1\{L_i\le r_i\}\) |
| Number of global null discoveries | \(\displaystyle N_{\mathrm G}=\sum_{i=1}^{m}\mathbf1\{G_i\le\alpha\}\) |
| Number of true global null discoveries | \(\displaystyle T_{\mathrm G}=\sum_{i=1}^{m}\mathbf1\{G_i\le\alpha,\ r_i\ge1\}\) |
| Number of replicability discoveries | \(\displaystyle N_{\mathrm R}=\sum_{i=1}^{m}\mathbf1\{R_i\le\alpha\}\) |
| Number of true replicability discoveries | \(\displaystyle T_{\mathrm R}=\sum_{i=1}^{m}\mathbf1\{R_i\le\alpha,\ r_i\ge2\}\) |

A **true global null discovery** is a correct rejection: an effect exists somewhere. For \(r_i=2\) and \(L_i=3\), the bound overclaims and contributes zero to \(B_{\mathrm{correct}}\), but the weaker replicability claim is true and contributes one to \(T_{\mathrm R}\). These measures describe different aspects of the same findings and should not be added together.

**Check against the supplied document.** The total-lower-bound definition and four global/replicability definitions match Section 3 and Table 1. The document leaves the weighting of “correct lower bounds” ambiguous. We retain the previously agreed sum above: a correct bound of 2 contributes 2. Counting outcomes with a positive correct bound instead would give

\[
C_{\mathrm{positive}}=\sum_{i=1}^{m}\mathbf1\{1\le L_i\le r_i\},
\]

where that outcome contributes 1. The source comparison, CSV mapping, and worked examples are in [Supplement A](supplement.html#a-measures-and-worked-examples).

All six measures are **realized counts**, not normalized power estimates. The analytic planning power Π_j(n) and target c in Section 1 of the specification serve to select n. The separately agreed normalized study-count recovery score is in [Supplement I](supplement.html#i-additional-study-count-recovery). Neither is one of these six Section 3 counts. Directional power and directional errors are additional diagnostics defined in Supplement A.

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

**Results for each separate combination:** [open the per-setting report](per-setting-results.html) or [download its CSV](per-setting-results.csv). The Cartesian index includes every m × c × probability distribution × error criterion combination, with explicit labels for undefined planning and combinations outside the original design. Each evaluated setting has all six measures, agents, Welch, oracle and the maximum true discoveries. The tables below are aggregated summaries.

**Agents**, **Competitor (Welch)** and **Oracle (realized)** are evaluated on the same observations and scored identically. Each cell contains one count, not a fraction or an uncertainty interval.

The **oracle** uses the true effect signs and known population variances for one-sided z-tests of all m outcomes, followed by Holm for FWER or BH for FDR in each study at 0.05/3. It does not remove true nulls or optimize the testing allocation. It remains subject to sampling variation, so another method can exceed its realized discoveries.

**Maximum true discoveries** gives the number available with perfect knowledge: \(\sum_i r_i\) for correct lower-bound units, \(\sum_i\mathbf1\{r_i\ge1\}\) for true global null discoveries, and \(\sum_i\mathbf1\{r_i\ge2\}\) for true replicability discoveries. These are ceilings for the three *correct* totals, not predictions of what a statistical procedure can detect. A dash is shown for raw totals, which can include errors and therefore exceed the number of true discoveries. See [Supplement A](supplement.html#a-measures-and-worked-examples) for the exact oracle procedure and ceiling formulas.

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
