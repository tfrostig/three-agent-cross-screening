## Appendix: measures and interpretation

These are the six measures of “power” requested in Section 3 of *K-team cross screening (K > 2)*. Let r be the number of false null hypotheses for an outcome (subgroups with a nonzero exposure effect), and L its lower bound: the number of subsets with adjusted p-values at most α/3, where α=0.05. Count an outcome once per subset even if both directions reject.

| Name in the specification | Calculation across outcomes |
|:--|:--|
| Total number of lower bounds | Sum L |
| Total number of correct lower bounds | Sum L × I(L≤r) |
| Number of global null discoveries | Count outcomes with global null adjusted p-value ≤α |
| Number of true global null discoveries | Global null discoveries with r≥1 |
| Number of replicability discoveries | Count outcomes with replicability adjusted p-value ≤α |
| Number of true replicability discoveries | Replicability discoveries with r≥2 |

The global null states that all three subgroup effects are zero. Thus a **true global null discovery** means a correct rejection of that null, not that the outcome is truly null.

For outcome i, let P′_ji denote its adjusted p-value in subset j, following Table 1. The global null adjusted value is 3×min_j P′_ji. The replicability adjusted value is 3×min_{j<k} max(P′_ji,P′_ki), or three times the second-smallest subset value. Values are capped at 1 for reporting. No additional multiple-testing correction is applied. At the stated threshold, a global null discovery is equivalent to L≥1 and a replicability discovery to L≥2. Replicability does not require a common direction here.

| Number of false null hypotheses r | Reported lower bound L | Contribution to total number of lower bounds | Contribution to total number of correct lower bounds | Replicability discovery |
|--:|--:|--:|--:|:--|
| 3 | 1 | 1 | 1 | None |
| 3 | 2 | 2 | 2 | True |
| 2 | 2 | 2 | 2 | True |
| 2 | 3 | 3 | 0 | True |
| 1 | 2 | 2 | 0 | False |
| 0 | 1 | 1 | 0 | None |

A correct lower bound does not identify which subsets are affected. True effects in subsets 1/2 and discoveries in 1/3 give L=r=2, so the lower bound contributes 2 to both totals despite one wrong-subset discovery. Wrong-subset discoveries and directional errors are recorded separately. The two-sided competitor makes no directional claims.

The normalized study-count recovery score was agreed separately and is not one of these six measures. Its definition and results are reported in the additional-analysis supplement.

These are realized counts from one iteration, not long-run FWER/FDR estimates. Executable contract checks do not certify an arbitrary procedure's assumptions or error-control proof.
