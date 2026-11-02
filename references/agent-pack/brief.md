# Designing an analysis for independent target data

## Purpose and limits

Cross-screening separates exploratory design from confirmatory execution. One team
uses its own observations to propose an analysis for another team's observations.
Exploration can influence the measurement list, directions, test statistics, weights,
or testing order. The target analysis must then follow the frozen design, with the
requested error-control justification. The references explain methodological ideas;
they provide no information about the distribution, variances, effect signs, or
dependence structure of your observations. This brief is a curated synthesis, not a
quotation or an additional set of required analysis steps.

Your immediate task is to design a directional population-mean analysis for an
independent target subgroup. The broader research motivation includes discoveries
that hold in at least one subgroup and claims that effects recur across subgroups.
Those are different scientific claims. A discovery in one target subgroup does not
by itself establish replication. You are not being asked to combine unseen groups'
data or other agents' designs. Follow the session's actual contract and testing
level; the research proposal describes possible future aggregation stages, not
additional capabilities of your session.

## What exploration can contribute

The main example is Roy et al.'s two-team observational study (`two-team`, PDF
sections 2 and 4.2). Independent teams proposed different analyses after exploring
their own data. Their work included examining outcome definitions and unexpected
associations, comparing test statistics, checking sensitivity of substantive choices,
and prioritizing hypotheses through gatekeeping or ordered testing. The important
lesson is that analysis design can involve more than ranking small p-values. Their
specific outcomes, matching scheme, tests, and causal assumptions are features of
that application, not facts about the current task.

For your task, exploration might examine the distribution of observations, unusual
values, variability, dependence, and how sensitive a proposed ranking is to a few
observations. The value of a diagnostic is the design decision it informs. With
limited data, diagnostics need not discriminate reliably among distributional models.
Failure to detect an assumption violation is not proof that the assumption holds,
especially in another subgroup. If a method relies on an additional model, explain
that conditional interpretation rather than attributing the model to the data source.

## Discovery opportunities and multiplicity

A strong source association can make a measurement promising, but source and target
effects can differ. A smaller frozen family reduces the multiplicity burden while
also excluding possible target discoveries. These consequences should be considered
together. A source cutoff is a design choice, not automatically a significance rule
or an estimate of target replication probability. Source data reused to choose a
design and count its discoveries do not provide an independent assessment of target
performance.

Several strategies are available. Testing all measurements retains broad coverage.
A shortlist concentrates effort. Fixed weights can prioritize measurements with
strong source evidence while allowing others some opportunity in the target. An
ordered or hierarchical procedure may express substantive priorities or use a
gate before testing a family. These possibilities are not a mandated comparison or
a prescribed answer. Select and justify the strategy you believe most useful for
the target, and freeze all choices needed by its executable procedure. A weighting
or gating scheme needs a justification for the complete rejection algorithm, not
only for each individual test. Its weights, gates, and accounting for alternative
directions must agree with the requested family level and final hypothesis table.

## Independent confirmation and scientific interpretation

Zhao, Small, and Rosenbaum (`cross-screening-2018`) motivate using one sample to
choose an analysis carried out on another sample. Their observational-study setting
also involves sensitivity to unmeasured confounding. Neither their design rationale
nor a multiplicity correction supplies causal identification for a different problem.
Directions and testing choices learned from source data must be evaluated using fresh
target observations. Independence from target data is central to the separation of
exploration and confirmation; sharing methodological references does not permit
sharing source observations, histories, or other teams' discoveries.

For FDR, the requested practical preference is BH or a justified weighted version.
State the conditions supporting the procedure and what remains a practical rather
than universal guarantee. Validity of the individual p-values and the dependence
conditions of the multiple-testing procedure are separate issues. A dependence
correction does not repair an invalid individual test, and diagnostic checks do not
establish the conditions of a theorem. The same distinction applies to error control
for a hierarchical or ordered analysis.

## Replicability methods and their prerequisites

Bogomolov and Heller's two-study work (`replicability-2018`) addresses selecting and
testing features to make replicability claims, with conditions on independence,
selection, and within-study dependence. Wang et al.'s AdaFilter (`adafilter`) and
Dickhaus et al.'s CoFilter (`cofilter`) address multiple partial-conjunction
hypotheses, which concern effects in a specified number of studies. Their filtering
and subsequent testing are calibrated together; they do not justify an arbitrary
source threshold followed by an unrelated analysis. They require multi-study
information and method-specific assumptions that a single-source session does not
automatically possess.

The review by Bogomolov and Heller (`replicability-review`) distinguishes global-null
discovery, directional replicability, and partial-conjunction inference. Consult it
for orientation rather than treating these claims as interchangeable. The research
proposal (`proposal`) motivates independent teams, heterogeneous subgroups, and
possible computer aggregation of designs. Only a sanitized conceptual summary is
available here. When adapting any reference, identify the actual idea used, the
information it requires, its assumptions, and which parts of its scientific claim
are appropriate to your assigned target analysis.
