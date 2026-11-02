# CoFilter: conditional testing after filtering

Dickhaus, Heller, Hoang, and Rinott (2026), *A procedure for multiple testing of
partial conjunction hypotheses based on a hazard rate inequality*, Bernoulli 32,
274–298. DOI: 10.3150/25-BEJ1858. Relevant PDF pages: 1–2.

CoFilter addresses the conservativeness of multiple testing of partial-conjunction
p-values. It filters using a selection threshold and then tests conditional
partial-conjunction p-values within the selected set. Conditioning is part of the
method's calibration; filtering and testing cannot be separated and substituted
arbitrarily while retaining its guarantee.

The abstract specifies uniform true-null p-values and Fisher combination for the
validity of its conditional p-values. Study independence and additional conditions
for particular FDR procedures must also be checked in the full method before use.
Its guarantees are not a license to assume uniform p-values or independence for
your data.

A single-source session does not possess the multi-study p-value matrix required
to implement this replicability method directly. It may use the principle that a
filter should be calibrated with the subsequent inference and its target claim.
Do not reinterpret a target-subgroup rejection as a partial-conjunction rejection.
