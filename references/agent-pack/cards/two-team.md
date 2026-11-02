# Two-team exploration, confirmation, and replication

Roy, Bogomolov, Heller, Claridge, Beeson, and Small (2026), *Exploration,
Confirmation, and Replication in the Same Observational Study*, JASA.
DOI: 10.1080/01621459.2026.2668130. Relevant PDF pages: 6–7 and 10–13.

Each team explores only its own subgroup and proposes a complete analysis for the
other subgroup. Design choices include which outcomes matter, alternative directions,
choice of test statistics, and how to allocate testing effort. The application
contains both gatekeeping and ordered testing, as well as investigation of unexpected
findings before deciding what to forward. This is methodological inspiration for
reasoned design, not a requirement to reproduce the application's tests or priorities.

The paper's two-team FWER allocation and downstream rules are specific to that
design. Use the level and transfer arrangement supplied in your session instead.
Do not import its matched-pair structure, observational sensitivity model, clinical
outcomes, or causal claims into independent exposed/control data. In the current
interface, preserve the supplied measurements and the population-mean estimand.
An application-specific distribution-equality test is not automatically a test of
unrestricted population means.

The `design` and `gatekeeping` sections provide short source excerpts. Their
application details explain the authors' reasoning, not the current generator.
