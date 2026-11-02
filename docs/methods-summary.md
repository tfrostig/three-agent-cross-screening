# Agent-designed cross-screening versus Welch procedures

The agents mostly implemented familiar statistical procedures: Welch-style screening on one subgroup, followed by a frozen directional analysis on another subgroup. Their main contributions were choosing the shortlist size, whether to retain one or both directions, the final testing method, and a written justification of its assumptions. In this first run, those choices did not demonstrate an advantage over a simple scripted procedure.

## What was actually compared?

| Stage | Original Welch baseline | Agent procedure | Simple Welch cross-screening comparator |
|---|---|---|---|
| Source subgroup | Not used | Inspect source observations and select promising measurements | Rank measurements using source Welch statistics or p-values |
| Hypothesis family | Every measurement, both directions: 2m hypotheses | Frozen subset; usually one source-selected direction, sometimes both | Frozen subset and directions chosen before target evaluation |
| Target analysis | One-sided Welch two-sample tests | Artificial-difference t-tests, conservative unequal-variance t-tests, or exact permutation tests | One-sided Welch two-sample tests |
| Multiplicity | Holm for FWER; BY for FDR, over all 2m hypotheses | Same correction types, over the frozen family | Same correction types, over the frozen family |
| Target budget | 0.05/3 per target group | 0.05/3 per target group | 0.05/3 per target group |

The original comparison changed both the hypothesis family and the testing method. It therefore evaluated the entire agent-designed pipeline, rather than isolating whether agents chose better tests than Welch.

The fixed transfer cycle was source 1 to target 2, source 2 to target 3, and source 3 to target 1. The target observations were independent of the observations used to design their incoming analysis. No target results were returned to agents for redesign.

## What did the agents do at the screening stage?

Their common screening score was

\[
T_i = \frac{\bar X_i-\bar Y_i}{\sqrt{s_{X,i}^2/n_X+s_{Y,i}^2/n_Y}},
\]

which is the ordinary Welch t-statistic. Agents retained either the top few absolute scores or those exceeding a chosen threshold. Most froze the source-estimated sign; two designs retained both signs for every selected measurement to permit target sign reversals.

A replay of the saved source observations established that **all 24 frozen hypothesis families are reproduced by taking the top K absolute Welch statistics**, using each design's actual number of selected coordinates and its one-direction or both-direction policy. This is a statement about the resulting families, not evidence that agents used one common prespecified K. They chose different shortlist sizes through exploratory analysis.

Ranking by absolute t-statistic and ranking by two-sided Welch p-value need not agree: the Welch degrees of freedom vary across measurements. Using the smallest two-sided p-values reproduced 20 of the 24 families exactly; each remaining family changed only one or two coordinates.

Thus the suggestion to select promising measurements using Welch and pass them to the next group describes almost exactly what happened at the screening stage.

## Why were the final tests different?

The agents were not given the generator's normality, variance, dependence, or effect-sign assumptions. Their explanations emphasized conditional error-control arguments under explicit working models.

* **17 designs used one-sample t-tests on artificial row differences.** They subtracted the control observation in row j from the exposed observation in row j. Under iid normal sampling in independent groups, these differences yield an exact Student t pivot without equal population variances. The pairing was fixed by row order, not based on matched subjects or observed outcomes. They acknowledged fewer degrees of freedom and sensitivity to the arbitrary pairing. Welch instead estimates the two group variances separately and uses the approximate Welch–Satterthwaite degrees of freedom.
* **5 designs used conservative unequal-variance t-based tests.** These used a smaller degrees-of-freedom choice than ordinary Welch; one additionally enlarged the denominator and doubled the tail probability. Their stated aim was a finite-sample conservative bound under a normal working model.
* **2 designs used exact permutation enumeration.** This avoided normality and Monte Carlo error, but their directional mean-test justification required a common-shape location-shift model. It was not a distribution-free test of means under unrestricted unequal distributions.

All FWER designs used Holm and all FDR designs used Benjamini–Yekutieli. Their stated reason was protection under arbitrary dependence of valid null p-values. These were standard correction choices, also used by the baseline. Execution checks established that the code ran and respected the artifact contracts; they did not establish the modeling assumptions or empirical error-rate control.

## What if we simply used Welch for screening and testing?

A simple procedure would compute source Welch scores, choose a shortlist, freeze its directions, and send only that family to the next group's fixed Welch analysis. The next group would recompute every p-value from its own observations and apply Holm or BY over the complete frozen family at 0.05/3. It would not reuse source p-values or change directions after seeing target results. A receiving LLM is unnecessary for this fixed analysis.

For a clean interpretation, the selection rule must be specified: “most promising” could mean top K by absolute t, top K by p-value, or a fixed screening threshold. K should be fixed or determined solely from source data. Smaller families reduce the multiplicity penalty but can exclude target-specific effects. Similar source and target effects help power; target effects need not replicate for conditional error control if the target p-values themselves are valid. Welch's finite-sample calibration remains approximate.

We evaluated two replacements using the existing observations, without new agent calls or generated experiments:

1. **Keep the exact agent shortlist and use Welch on the target.** This holds the family, directions, correction, data, and target budget fixed and changes only the final raw p-values.
2. **Screen by source two-sided Welch p-values and test with target Welch.** This matches each original design's coordinate count and one-direction or both-direction policy. The inherited counts make this a matched post-hoc comparator, not an independently prespecified screening policy. Using absolute Welch t-statistics instead would reproduce the exact-shortlist comparator, since all 24 families matched that ranking.

For illustration, in the 1,000-measurement, higher-power FDR scenario:

| Procedure | Realized fraction of target signals discovered |
|---|---:|
| Original agent designs | 27.3% |
| Exact agent shortlists, target Welch | 29.5% |
| Source Welch p-value screen, target Welch | 29.5% |
| Original Welch baseline, all measurements and both signs | 64.1% |

On these observations, Welch on the exact agent families produced at least as many correct discoveries as the agent tests in every scenario, with ties in two scenarios. Most of the difference from the unscreened baseline persisted after replacing the final tests. This points to the importance of which target effects the source-selected family permits us to discover. It does not prove screening is generally harmful, identify an optimal shortlist size, or establish a population-level ranking of the methods. A selected family also changes multiplicity and directional coverage, so the unscreened comparison is not a pure test-choice comparison.

## Interpretation and reproducibility

The methodological finding is that the agents chose conventional Welch-style screening and conservative confirmatory inference. Their written explanations made the assumptions and transfer limitations explicit, but this run did not show that adaptive agent design improved discovery over scripted Welch cross-screening. A more informative future evaluation would compare prespecified screened-Welch policies with agent designs across repeated independent experiments, separately examining selection and final testing. That future evaluation has not been run.

This was one realization per scenario, with no additional simulation draws or agent calls for the comparison. All numbers are realized outcomes, not estimated FWER or FDR. The original frozen designs and live report were preserved. All 24 original Welch baseline score rows were reproduced, and all frozen artifact hashes were checked before and after the replay.

Reproduce from the project root with `Rscript --vanilla analyses/compare_welch.R`. Outputs are in `results/welch-method-comparison/`: `global-scores.csv`, `scores.csv`, `screen-overlap.csv`, per-design hypothesis/result CSVs under `evaluations/`, and `comparison.json` recording the source hash, input hashes, and replay specification.
