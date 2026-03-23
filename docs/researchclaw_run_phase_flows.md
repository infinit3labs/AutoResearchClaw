# ResearchClaw `run --topic` Phase Flows

This page documents the internal execution flow for `researchclaw run --topic "..."` at the **phase level**, with explicit **handoff artifacts** between phases.

It is based on the current code path in:

- `researchclaw/cli.py`
- `researchclaw/config.py`
- `researchclaw/llm/__init__.py`
- `researchclaw/pipeline/runner.py`
- `researchclaw/pipeline/executor.py`
- `researchclaw/pipeline/stage_impls/*.py`

## Entry point into the phased pipeline

Before Phase A starts, the CLI path is:

1. `pyproject.toml` console script → `researchclaw.cli:main`
2. `researchclaw.cli.main()` parses the `run` subcommand
3. `cmd_run()` resolves config, loads `RCConfig`, applies CLI overrides, optionally runs LLM preflight, creates `run_dir`, `AdapterBundle`, and calls `execute_pipeline()`
4. `execute_pipeline()` iterates `STAGE_SEQUENCE`
5. `execute_stage()` validates required inputs, builds a stage-local `PromptManager` and LLM client, and dispatches to the phase's `_execute_*` function

## Phase-to-phase handoff summary

| Phase | Stages | Main outbound artifacts | Main consumers |
| --- | ---: | --- | --- |
| A. Research Scoping | 1-2 | `goal.md`, `hardware_profile.json`, `problem_tree.md` | Phase B, Phase D |
| B. Literature Discovery | 3-6 | `search_plan.yaml`, `queries.json`, `candidates.jsonl`, `references.bib`, `shortlist.jsonl`, `cards/` | Phase C, Phase G |
| C. Knowledge Synthesis | 7-8 | `synthesis.md`, `hypotheses.md`, `novelty_report.json` | Phase D |
| D. Experiment Design | 9-11 | `exp_plan.yaml`, `domain_profile.json`, `benchmark_plan.json`, `experiment/`, `experiment_spec.md`, `schedule.json` | Phase E |
| E. Experiment Execution | 12-13 | `runs/`, `results.json`, `time_budget_warning.json`, `experiment_final/`, `refinement_log.json` | Phase F, Phase H |
| F. Analysis & Decision | 14-15 | `analysis.md`, `experiment_summary.json`, `results_table.tex`, `charts/`, `decision.md`, `decision_structured.json`, `experiment_diagnosis.json`, `repair_prompt.txt` | Phase G, runner rollback logic |
| G. Paper Writing | 16-19 | `outline.md`, `paper_draft.md`, `draft_quality.json`, `reviews.md`, `paper_revised.md` | Phase H |
| H. Finalization | 20-23 | `quality_report.json`, `archive.md`, `bundle_index.json`, `paper_final.md`, `paper.tex`, `paper.pdf`, `references.bib`, `verification_report.json`, `paper_final_verified.md` | deliverables packaging |

## Phase A — Research Scoping

**Stages:** `TOPIC_INIT` (1), `PROBLEM_DECOMPOSE` (2)

**Primary handoff out:** `goal.md`, `hardware_profile.json`, `problem_tree.md`

```mermaid
flowchart TD
    A0["CLI hands control to execute_pipeline()<br/>from_stage defaults to TOPIC_INIT"] --> A1["Stage 1: _execute_topic_init()<br/>stage_impls/_topic.py"]
    A1 --> A2["PromptManager.for_stage('topic_init')<br/>optional llm.chat() -> research goal narrative"]
    A1 --> A3["detect_hardware()<br/>ensure_torch_available() when applicable"]
    A2 --> A4["Write stage-01/goal.md"]
    A3 --> A5["Write stage-01/hardware_profile.json"]
    A4 --> A6["Stage 2: _execute_problem_decompose()<br/>reads goal.md"]
    A5 --> A6
    A6 --> A7["PromptManager.for_stage('problem_decompose')<br/>optional llm.chat()"]
    A6 --> A8["Optional topic quality evaluation<br/>_detect_domain() + llm JSON check"]
    A7 --> A9["Write stage-02/problem_tree.md"]
    A8 --> A10["Optional stage-02/topic_evaluation.json"]
    A9 --> A11["Handoff to Phase B<br/>problem framing + goal + hardware profile"]
```

### Phase A handoff points

- `goal.md` seeds the problem decomposition prompt and later context preambles.
- `hardware_profile.json` is reused in experiment planning and code generation.
- `problem_tree.md` is the main input to search strategy generation.

## Phase B — Literature Discovery

**Stages:** `SEARCH_STRATEGY` (3), `LITERATURE_COLLECT` (4), `LITERATURE_SCREEN` (5), `KNOWLEDGE_EXTRACT` (6)

**Primary handoff out:** `queries.json`, `candidates.jsonl`, `references.bib`, `shortlist.jsonl`, `cards/`

```mermaid
flowchart TD
    B1["Stage 3: _execute_search_strategy()<br/>reads problem_tree.md + topic"] --> B2["_build_fallback_queries()<br/>PromptManager.for_stage('search_strategy')<br/>optional llm JSON/YAML planning"]
    B2 --> B3["Write stage-03/search_plan.yaml"]
    B2 --> B4["Write stage-03/sources.json"]
    B2 --> B5["Write stage-03/queries.json"]

    B5 --> B6["Stage 4: _execute_literature_collect()<br/>reads queries.json"]
    B6 --> B7["search_papers_multi_query()<br/>OpenAlex / Semantic Scholar / arXiv"]
    B6 --> B8["WebSearchAgent.search_and_extract()<br/>scholar + web + crawl augmentation"]
    B6 --> B9["Fallbacks<br/>load_seminal_papers()<br/>LLM candidate generation<br/>placeholder generation"]
    B7 --> B10["Write stage-04/candidates.jsonl"]
    B8 --> B11["Write stage-04/web_context.md + web_search_result.json"]
    B9 --> B12["Write stage-04/references.bib + search_meta.json"]
    B10 --> B13["Stage 5: _execute_literature_screen()<br/>reads candidates.jsonl"]
    B13 --> B14["_extract_topic_keywords() prefilter<br/>screening batch builder<br/>optional llm shortlist review"]
    B14 --> B15["Write stage-05/shortlist.jsonl"]
    B15 --> B16["Stage 6: _execute_knowledge_extract()<br/>reads shortlist + optional web context"]
    B16 --> B17["PromptManager.for_stage('knowledge_extract')<br/>optional llm card extraction"]
    B17 --> B18["Write stage-06/cards/"]
    B18 --> B19["Handoff to Phase C<br/>screened literature + extracted knowledge cards + bibliography"]
```

### Phase B handoff points

- `queries.json` is the execution plan for real literature search.
- `references.bib` becomes the citation source used later in paper drafting and verification.
- `shortlist.jsonl` narrows the candidate set before structured knowledge extraction.
- `cards/` is the direct input for synthesis.

## Phase C — Knowledge Synthesis

**Stages:** `SYNTHESIS` (7), `HYPOTHESIS_GEN` (8)

**Primary handoff out:** `synthesis.md`, `hypotheses.md`, `novelty_report.json`

```mermaid
flowchart TD
    C1["Stage 7: _execute_synthesis()<br/>reads stage-06/cards/"] --> C2["Assemble card snippets<br/>PromptManager.for_stage('synthesis')<br/>optional llm synthesis"]
    C2 --> C3["Write stage-07/synthesis.md"]
    C3 --> C4["Stage 8: _execute_hypothesis_gen()<br/>reads synthesis.md"]
    C4 --> C5["_multi_perspective_generate()<br/>debate roles from prompts"]
    C5 --> C6["_synthesize_perspectives()<br/>produce unified hypotheses"]
    C6 --> C7["Write stage-08/hypotheses.md"]
    C7 --> C8["check_novelty()<br/>compare against collected literature"]
    C8 --> C9["Write stage-08/novelty_report.json"]
    C9 --> C10["Handoff to Phase D<br/>hypotheses become experiment targets"]
```

### Phase C handoff points

- `synthesis.md` summarizes clustered findings and gaps.
- `hypotheses.md` is the main semantic input for experiment design.
- `novelty_report.json` is advisory but useful for downstream framing.

## Phase D — Experiment Design

**Stages:** `EXPERIMENT_DESIGN` (9), `CODE_GENERATION` (10), `RESOURCE_PLANNING` (11)

**Primary handoff out:** `exp_plan.yaml`, `experiment/`, `experiment_spec.md`, `schedule.json`

```mermaid
flowchart TD
    D1["Stage 9: _execute_experiment_design()<br/>reads hypotheses.md + goal context"] --> D2["detect_domain()<br/>optional BenchmarkOrchestrator.orchestrate()<br/>condition trimming by time budget"]
    D2 --> D3["Write stage-09/exp_plan.yaml"]
    D2 --> D4["Optional stage-09/domain_profile.json"]
    D2 --> D5["Optional stage-09/benchmark_plan.json"]

    D3 --> D6["Stage 10: _execute_code_generation()<br/>reads exp_plan.yaml + hardware profile"]
    D6 --> D7["Code path selection<br/>OpenCodeBridge.generate() OR<br/>CodeAgent.generate() OR<br/>legacy PromptManager + llm"]
    D7 --> D8["Validation and repair<br/>validate_code()<br/>deep_validate_files()<br/>alignment check<br/>ablation distinctness check"]
    D8 --> D9["Write stage-10/experiment/"]
    D8 --> D10["Write stage-10/experiment_spec.md<br/>validation_report.md<br/>code_agent_log.json when applicable"]

    D9 --> D11["Stage 11: _execute_resource_planning()<br/>reads exp_plan.yaml"]
    D11 --> D12["PromptManager.for_stage('resource_planning')<br/>optional llm schedule synthesis"]
    D12 --> D13["Write stage-11/schedule.json"]
    D13 --> D14["Handoff to Phase E<br/>experiment project + schedule + metric definitions"]
```

### Phase D handoff points

- `exp_plan.yaml` defines datasets, baselines, ablations, metrics, and compute budget.
- `experiment/` is the runnable project used by sandbox or other execution backends.
- `schedule.json` is the execution plan consumed by the run stage.

## Phase E — Experiment Execution

**Stages:** `EXPERIMENT_RUN` (12), `ITERATIVE_REFINE` (13)

**Primary handoff out:** `runs/`, `results.json`, `refinement_log.json`, `experiment_final/`

```mermaid
flowchart TD
    E1["Stage 12: _execute_experiment_run()<br/>reads experiment/ + schedule.json"] --> E2["create_sandbox() or ExperimentRunner<br/>sandbox.run_project() / run()"]
    E2 --> E3["Parse stdout + metrics<br/>capture results.json when present<br/>write run payloads"]
    E3 --> E4["Write stage-12/runs/*.json<br/>optional runs/results.json<br/>optional time_budget_warning.json"]

    E4 --> E5["Stage 13: _execute_iterative_refine()<br/>reads runs/ + experiment/ + exp_plan.yaml"]
    E5 --> E6["Loop: validate_code() -> llm repair prompt -> rerun sandbox"]
    E6 --> E7["Track best metric and best project version<br/>handle timeout / no-metric / saturation guards"]
    E7 --> E8["Write stage-13/experiment_vN/ snapshots"]
    E7 --> E9["Write stage-13/refinement_log.json"]
    E7 --> E10["Write stage-13/experiment_final/"]
    E10 --> E11["Handoff to Phase F<br/>raw run evidence + refined best code + refinement history"]
```

### Phase E handoff points

- `runs/*.json` provides raw evidence for result analysis.
- `refinement_log.json` captures iterative repair history and best metric/version.
- `experiment_final/` is later packaged into release artifacts.

## Phase F — Analysis & Decision

**Stages:** `RESULT_ANALYSIS` (14), `RESEARCH_DECISION` (15)

**Primary handoff out:** `analysis.md`, `experiment_summary.json`, `results_table.tex`, `charts/`, `decision.md`

```mermaid
flowchart TD
    F1["Stage 14: _execute_result_analysis()<br/>reads runs/ + refinement_log.json"] --> F2["_collect_experiment_results()<br/>merge refined metrics<br/>build condition summaries + paired comparisons"]
    F2 --> F3["Write stage-14/experiment_summary.json"]
    F2 --> F4["Write stage-14/results_table.tex"]
    F2 --> F5["PromptManager + debate roles<br/>produce analysis narrative"]
    F5 --> F6["Write stage-14/analysis.md"]
    F2 --> F7["FigureOrchestrator.orchestrate() or generate_all_charts()<br/>write stage-14/charts/"]

    F6 --> F8["Runner hook after Stage 14<br/>_run_experiment_diagnosis()<br/>optional _run_experiment_repair()"]
    F8 --> F9["Possible extra outputs<br/>experiment_diagnosis.json<br/>repair_prompt.txt<br/>experiment_repair_result.json"]

    F6 --> F10["Stage 15: _execute_research_decision()<br/>reads analysis.md + optional diagnosis"]
    F10 --> F11["_parse_decision()<br/>PROCEED / REFINE / PIVOT"]
    F11 --> F12["Write stage-15/decision.md + decision_structured.json"]
    F12 --> F13{"Runner branch"}
    F13 -- proceed --> F14["Handoff to Phase G"]
    F13 -- refine --> F15["Rollback target = Stage 13<br/>ITERATIVE_REFINE"]
    F13 -- pivot --> F16["Rollback target = Stage 8<br/>HYPOTHESIS_GEN"]
```

### Phase F handoff points

- `experiment_summary.json` is the structured data backbone for writing, quality checks, export, and verification.
- `analysis.md` provides the narrative interpretation of experimental evidence.
- `decision.md` controls whether the pipeline advances or recursively rolls back.

## Phase G — Paper Writing

**Stages:** `PAPER_OUTLINE` (16), `PAPER_DRAFT` (17), `PEER_REVIEW` (18), `PAPER_REVISION` (19)

**Primary handoff out:** `outline.md`, `paper_draft.md`, `draft_quality.json`, `reviews.md`, `paper_revised.md`

```mermaid
flowchart TD
    G1["Stage 16: _execute_paper_outline()<br/>reads analysis.md + decision.md + experiment context"] --> G2["PromptManager.for_stage('paper_outline')<br/>optional iteration feedback injection"]
    G2 --> G3["Write stage-16/outline.md"]

    G3 --> G4["Stage 17: _execute_paper_draft()<br/>reads outline + experiment_summary + references.bib"]
    G4 --> G5["Build anti-fabrication context<br/>VerifiedRegistry<br/>prebuilt tables<br/>raw metrics blocks<br/>chart references"]
    G5 --> G6["_write_paper_sections()<br/>3 sequential LLM passes:<br/>intro/related, method/experiments, results/discussion"]
    G6 --> G7["Write stage-17/paper_draft.md"]
    G7 --> G8["_validate_draft_quality()<br/>write stage-17/draft_quality.json"]

    G7 --> G9["Stage 18: _execute_peer_review()<br/>collect experiment evidence + draft quality warnings"]
    G9 --> G10["Write stage-18/reviews.md"]

    G10 --> G11["Stage 19: _execute_paper_revision()<br/>reads draft + reviews + draft_quality directives"]
    G11 --> G12["Length guard + review-driven rewrite<br/>retain data integrity constraints"]
    G12 --> G13["Write stage-19/paper_revised.md"]
    G13 --> G14["Handoff to Phase H<br/>revised manuscript + review trail + quality directives"]
```

### Phase G handoff points

- `outline.md` stabilizes the structure before the large drafting pass.
- `paper_draft.md` is reviewed both by peer-review stage logic and quality validators.
- `draft_quality.json` feeds revision directives into Stage 19.
- `paper_revised.md` is the manuscript evaluated by the final quality gate.

## Phase H — Finalization

**Stages:** `QUALITY_GATE` (20), `KNOWLEDGE_ARCHIVE` (21), `EXPORT_PUBLISH` (22), `CITATION_VERIFY` (23)

**Primary handoff out:** quality and archive reports, final paper artifacts, verified bibliography, verified paper

```mermaid
flowchart TD
    H1["Stage 20: _execute_quality_gate()<br/>reads paper_revised.md + experiment_summary.json"] --> H2["LLM scoring + fabrication cross-check<br/>write quality_report.json + fabrication_flags.json"]
    H2 --> H3{"score vs threshold"}
    H3 -- fail --> H4["StageResult FAILED<br/>pipeline stops unless degraded path is enabled"]
    H3 -- degraded --> H5["Write degradation_signal.json<br/>continue with sanitization path"]
    H3 -- pass --> H6["Continue normally"]

    H5 --> H7["Stage 21: _execute_knowledge_archive()<br/>write archive.md + bundle_index.json"]
    H6 --> H7

    H7 --> H8["Stage 22: _execute_export_publish()<br/>reads paper_revised.md"]
    H8 --> H9["_sanitize_fabricated_data()<br/>citation normalization<br/>markdown_to_latex()<br/>compile_latex()"]
    H9 --> H10["Write stage-22/paper_final.md<br/>paper.tex / paper.pdf<br/>references.bib<br/>charts/ code/ reports"]

    H10 --> H11["Stage 23: _execute_citation_verify()<br/>reads references.bib + paper_final.md"]
    H11 --> H12["verify_citations()<br/>filter_verified_bibtex()<br/>annotate_paper_hallucinations()"]
    H12 --> H13["Write stage-23/verification_report.json<br/>references_verified.bib<br/>paper_final_verified.md"]

    H13 --> H14["Runner post-loop packaging<br/>_build_pipeline_summary()<br/>extract_lessons()<br/>_metaclaw_post_pipeline()<br/>_package_deliverables()"]
    H14 --> H15["Final user-facing bundle<br/>deliverables/ + pipeline_summary.json"]
```

### Phase H handoff points

- `quality_report.json` determines whether the finalization path is pass, fail, or degraded.
- `paper_final.md` and `paper.tex` are the canonical publication outputs before citation verification.
- `verification_report.json` and `references_verified.bib` become the final citation integrity record.
- `deliverables/` is assembled after the pipeline loop ends, not as a standalone stage.

## Cross-phase control-flow notes

### Gate stages

- Stage 5 (`LITERATURE_SCREEN`)
- Stage 9 (`EXPERIMENT_DESIGN`)
- Stage 20 (`QUALITY_GATE`)

These are checked in `researchclaw/pipeline/stages.py` and enforced in `execute_stage()` via `gate_required()`.

### Recursive rollback points

- `REFINE` at Stage 15 rolls back to Stage 13 (`ITERATIVE_REFINE`)
- `PIVOT` at Stage 15 rolls back to Stage 8 (`HYPOTHESIS_GEN`)

The recursion is handled in `researchclaw/pipeline/runner.py` by a second call to `execute_pipeline(from_stage=rollback_target)`.

### Runner-managed side effects

These happen outside any single phase diagram but are important for handoff integrity:

- `checkpoint.json` updates after successful stages
- `heartbeat.json` updates after every stage
- optional knowledge-base writes via `write_stage_to_kb()`
- experiment diagnosis / repair hook after Stage 14
- lesson extraction and MetaClaw post-processing after the loop
- final `deliverables/` packaging after all stage execution is done
