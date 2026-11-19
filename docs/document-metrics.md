## Appendix: measures and interpretation

### Source and notation

The comparison below uses Section 3 and Table 1 (page 3) of *K-team cross screening (K > 2)*, `nsf_bsf_2025 (1).pdf` (SHA-256 `6cffa81d028ece2cc920a2fbe803682045f234773706215e6c044d8ab5a07817`). Section 3 and Table 1 were also checked in the earlier `nsf_bsf_2025.pdf`; their scoring instructions agree. We use m for outcomes, consistently with Section 1; Table 1 labels its last outcome K. The number of studies is fixed at three.

For one simulation setting, let j∈{1,2,3} index studies, i∈{1,…,m} index outcomes, and a index the analysis approach. Define

\[
h_{ji}=\mathbf 1\{\eta_{ji}\ne0\},\qquad
r_i=\sum_{j=1}^{3}h_{ji},\qquad \alpha=0.05.
\]

Thus r_i is the true number of subgroups with a nonzero effect. It is obtained from simulation truth only for scoring; agents and algorithm selection do not receive it. Let \(P_{ji}^{\prime(a)}\) denote the **outcome-level multiplicity-adjusted value** produced when approach a analyzes study j. For readability, omit a below; every formula is applied separately and identically to each approach.

- For agents, use the selected frozen design's outcome-level output. If it tests both directions, its own code supplies the combination, with outcome rejection equal to at least one directional rejection. The framework does not impose a minimum-p rule.
- For the competitor, use the Holm- or BH-adjusted two-sided Welch p-value among all m outcomes in study j.
- A nonselected outcome receives adjusted value 1. A missing study evaluation makes the scenario-level scores incomplete; it is not assigned value 1 or zero discoveries.

### Decisions and lower bounds

Define the study-level discovery indicator and reported lower bound by

\[
D_{ji}=\mathbf 1\{P'_{ji}\le\alpha/3\},\qquad
L_i=\sum_{j=1}^{3}D_{ji}\in\{0,1,2,3\}.
\]

A study contributes at most one to L_i even if both directions reject. L_i is a *reported* lower bound on r_i; it need not be correct in every realization. It is correct for scoring when L_i≤r_i. This concerns the number of affected subgroups, not their identities or signs.

### Global null and replicability

The global null and the null of no replicability for outcome i are

\[
H^{\mathrm G}_{0i}:r_i=0,\qquad
H^{\mathrm R}_{0i}:r_i\le1.
\]

Following Table 1 exactly, apart from capping values at 1, define

\[
G_i=\min\!\left\{1,3\min_{j\in\{1,2,3\}}P'_{ji}\right\},
\]

\[
R_i=\min\!\left\{1,3\min_{1\le j<k\le3}\max(P'_{ji},P'_{ki})\right\}
    =\min\{1,3P'_{(2)i}\},
\]

where \(P'_{(2)i}\) is the second-smallest of the three study values. There is **no further multiplicity correction** after this aggregation. At the reporting threshold,

\[
\{G_i\le\alpha\}=\{L_i\ge1\},\qquad
\{R_i\le\alpha\}=\{L_i\ge2\}.
\]

Capping does not affect these decisions because α<1. A true global null discovery is a correct rejection of the global null (r_i≥1). A true replicability discovery has r_i≥2. Neither definition requires effects or discoveries to have the same direction across studies.

### The six reported measures

All sums below run over i=1,…,m. They are counts, without normalization.

| Name in Section 3 | Mathematical definition used in the report | Saved CSV field |
|:--|:--|:--|
| Total number of lower bounds | \(B=\sum_iL_i=\sum_i\sum_jD_{ji}\) | `claimed_studies` |
| Total number of correct lower bounds | \(B_{\mathrm{correct}}=\sum_iL_i\mathbf1\{L_i\le r_i\}\) | `correct_lower_bound_credit` |
| Number of global null discoveries | \(N_{\mathrm G}=\sum_i\mathbf1\{G_i\le\alpha\}=\sum_i\mathbf1\{L_i\ge1\}\) | `global_discoveries` |
| Number of true global null discoveries | \(T_{\mathrm G}=\sum_i\mathbf1\{G_i\le\alpha,\ r_i\ge1\}\) | `true_global_discoveries` |
| Number of replicability discoveries | \(N_{\mathrm R}=\sum_i\mathbf1\{R_i\le\alpha\}=\sum_i\mathbf1\{L_i\ge2\}\) | `replicability_discoveries` |
| Number of true replicability discoveries | \(T_{\mathrm R}=\sum_i\mathbf1\{R_i\le\alpha,\ r_i\ge2\}\) | `true_replicability_discoveries` |

In particular, \(B\le3m\), \(B_{\mathrm{correct}}\le\sum_i r_i\), and each global/replicability count is at most m. Reported totals across settings sum these setting-specific counts; they are not probabilities or averages over repeated simulation draws.

### Alignment with the supplied document

| Document location | Finding |
|:--|:--|
| Section 3, item 1: total lower bounds | Exact match to its explicit count of the 3m adjusted values at most α/3: \(\sum_iL_i\). |
| Section 3, item 1: correct lower bounds | Correctness condition L_i≤r_i matches. **The aggregation wording is ambiguous**; the report retains the previously agreed weighted sum \(\sum_iL_i\mathbf1\{L_i\le r_i\}\), rather than claiming this weighting is unambiguously specified in the PDF. |
| Table 1, fifth column; Section 3, item 2 | Exact decision/count match for G_i, global null discoveries and true global null discoveries. Capping at 1 only changes display values above 1. |
| Table 1, sixth column; Section 3, item 3 | Exact decision/count match for R_i, replicability discoveries and true replicability discoveries. |
| Table 1 caption: nonselected outcomes | Adjusted values and displayed raw values are 1. |
| Section 3: competitor | All outcomes; two-sided testing; Holm for FWER or BH for FDR within each study, followed by the same aggregation. Welch is our implementation choice; the PDF does not name a particular two-sided test. |
| Table 1: one direction displayed per study/outcome | Allowing both directions is an agreed interface extension. The design supplies the combined outcome-level value; raw and adjusted values for both directional tests remain available. |
| Section 1 versus Section 3 | The analytic planning power Π_j(n) and target c select n; they are separate from these six discovery-count summaries. c=0.9 was an agreed addition to the document's 0.2 and 0.6. |

**The ambiguity concerns weighting, not the condition for correctness.** One reading of “total number of correct lower bounds” is the number of outcomes with a positive correct bound,

\[
C_{\mathrm{positive}}=\sum_i\mathbf1\{1\le L_i\le r_i\}.
\]

The current report counts the units of lower-bound evidence retained after removing overclaims. A correct L_i=2 contributes 2. The positive-outcome count would contribute 1. Zero bounds contribute nothing to either yield summary. The PDF leaves the aggregation convention open. `analyses/audit_measures.R` exports the alternative in `lower-bound-alignment-counts.csv`.

### Examples that distinguish the measures

| True count r_i | Reported L_i | Contribution to B | Contribution to B_correct | Contribution to C_positive | Replicability discovery |
|--:|--:|--:|--:|--:|:--|
| 3 | 1 | 1 | 1 | 1 | None |
| 3 | 2 | 2 | 2 | 1 | True |
| 2 | 2 | 2 | 2 | 1 | True |
| 2 | 3 | 3 | 0 | 0 | True |
| 1 | 2 | 2 | 0 | 0 | False |
| 0 | 1 | 1 | 0 | 0 | None |

For r_i=2 and L_i=3, the bound overstates the true count and earns zero correct-bound contribution, while the claim of an effect in at least two subgroups is still true. If effects occur in studies 1/2 but discoveries occur in 1/3, then L_i=r_i=2: both count-based summaries give full credit despite one wrong-study discovery. Those errors are reported separately.

### Exact oracle procedure and maximum true discoveries {#oracle-and-maximum}

The oracle is a **truth-informed testing reference**, applied to the same observations and scored with the same six definitions. It receives the true population variances and true effect signs, information withheld from agents and ordinary Welch testing. Its implementation is `doc_oracle()` in `R/document.R`.

For study j and outcome i, use the known unit variances to calculate

\[
Z_{ji}=\frac{\overline Y_{ji}-\overline X_{ji}}{\sqrt{2/n_j}},\qquad
d^*_{ji}=\begin{cases}-1,&\eta_{ji}<0,\\+1,&\eta_{ji}\ge0,\end{cases}
\qquad p^{\mathrm{or}}_{ji}=\Phi(-d^*_{ji}Z_{ji}).
\]

Here n_j is the sample size in each exposed/control arm of that study. A null effect has no true sign; the code assigns it +1. Because this generator has only positive nonzero effects, the oracle uses +1 for every outcome in this run. It uses true signs, not true effect magnitudes, in the test.

Within **each study separately**, apply Holm for FWER or BH for FDR to these m one-sided p-values. Reject at adjusted value at most α/3. Then compute L_i, G_i, R_i and all six totals exactly as for the other methods. The oracle tests **every outcome, including true nulls**; it does not restrict testing to true signals, fit a design, select among algorithms, or optimize weights/error allocation. False discoveries and missed signals remain possible.

Consequently, **Oracle (realized) is not an upper bound** on what another method can discover in this particular draw, and it is not a solution to an optimization problem over all valid procedures. Its columns display saved testing results, not the total number of effects available.

For the latter, perfect knowledge would identify every true effect and produce no errors. The ceilings on the three correct totals are

\[
B_{\mathrm{correct}}^{\max}=\sum_{i=1}^{m}r_i,\qquad
T_{\mathrm G}^{\max}=\sum_{i=1}^{m}\mathbf1\{r_i\ge1\},\qquad
T_{\mathrm R}^{\max}=\sum_{i=1}^{m}\mathbf1\{r_i\ge2\}.
\]

These maxima are attained by the hypothetical perfect decision set D_ji=h_ji. They need not be attainable by a statistical procedure using finite observations without truth. For the alternative positive-correct-bound count, the maximum is \(C_{\mathrm{positive}}^{\max}=\sum_i\mathbf1\{r_i\ge1\}\).

The main tables show **Maximum true discoveries** for the three correct totals. Raw discovery totals can exceed the truth counts through mistakes, so those cells contain dashes. Aggregated ceilings sum the per-setting ceilings over the same complete paired settings as the observed methods. `per-setting-results.csv` includes the oracle scores and truth ceilings. `analyses/audit_oracle.R` checks the saved oracle calculations against the original observations and exports `oracle-verification.csv`.

### Planning power and additional scores

Section 1 defines analytic planning power for a known-variance, one-sided Bonferroni z procedure. With \(\mathcal I_j=\{i:\eta_{ji}>0\}\),

\[
\Pi_j(n)=\frac{1}{|\mathcal I_j|}\sum_{i\in\mathcal I_j}
\left[1-\Phi\!\left(z_{1-\alpha/m}-\sqrt{n/2}\,\eta_{ji}\right)\right],
\qquad n_* = \min\{n\in\mathbb N:\min_j\Pi_j(n)>c\}.
\]

This is undefined if a study has no positive effects. It is neither an agent-performance score nor the standard comparator used after planning. The strict inequality and the planning level α/m follow the document; final study-level testing uses α/3.

The subsequently agreed **study-count recovery** is an additional normalized score, not a Section 3 measure. Put \(m_+=\sum_i\mathbf1\{r_i>0\}\). For m_+>0,

\[
\overline U=\frac{1}{m_+}\sum_{i:r_i>0}
\frac{L_i}{r_i}\mathbf1\{L_i\le r_i\}.
\]

For m_+=0 it is undefined. It weights nonnull outcomes equally, can credit wrong studies or signs, and gives zero to overclaims. Its results remain in Supplement I.

The separate realized **directional power** in study j is

\[
\widehat{\operatorname{Pow}}^{\mathrm{dir}}_j=
\frac{\sum_{i:\eta_{ji}\ne0}\mathbf1\{\text{at least one rejected direction }d\text{ satisfies }d\eta_{ji}>0\}}
{\sum_i\mathbf1\{\eta_{ji}\ne0\}},
\]

when the denominator is positive. A rejected direction with dη_ji≤0 is a false directional discovery, and directional FDP is their number divided by the number of directional rejections (or 1 if none). An outcome can have a correct directional discovery and an additional wrong-sign claim, which contributes to directional FDP. The two-sided Welch comparator makes no directional claims.

Section 3 calls its six summaries measures of “power”; we retain those names while reporting their **realized counts from one iteration**. Repeated draws would be needed to study their expected values or long-run error rates. Matching the aggregation formulas and executable interfaces does not establish statistical validity of every submitted procedure, nor replicability FDR control from study-level FDR control alone.
