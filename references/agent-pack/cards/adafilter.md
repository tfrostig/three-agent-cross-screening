# AdaFilter and partial-conjunction hypotheses

Wang, Gui, Su, Sabatti, and Owen (2022), *Detecting multiple replicating signals
using adaptive filtering procedures*, Annals of Statistics 50, 1890–1909.
DOI: 10.1214/21-AOS2139. Relevant PDF pages: 2 and 9–11.

AdaFilter targets many partial-conjunction hypotheses: whether a feature has an
effect in at least a specified number of studies. It uses filtering and selection
statistics constructed from ordered study-specific p-values. This calibrated
filtering differs from choosing a source t-statistic threshold by intuition.

Across-study independence is important. The paper's finite-sample FWER/PFER
theorem assumes independent valid base p-values. Its finite-sample FDR theorem
includes an inflation factor under its stated assumptions; separate asymptotic
FDR results allow specified weak within-study dependence and require additional
conditions. Practical simulation robustness should not be confused with a
finite-sample arbitrary-dependence theorem.

The method requires p-values across studies, which are not available to a
single-source design session. The useful general lesson is to match selection and
testing mathematically to the scientific claim and available information. Ordinary
target BH, AdaFilter BH, and an arbitrary screening step followed by BH are
different procedures with different justifications.
