# 15 — When and by whom Suite Runner gets the generic unit format

Status: CLOSED 2026-10-04 (operator Q3 a). Q1 + Q2 answered by surn_productionize_map (surn_saas).

## Facts (read 2026-10-04, ~/suite-runner)

Note: local remote `origin` (/home/.../suite-runner-origin.git) main = 04f551e, 2026-09-18, stale. Real upstream = remote `github` (dw3105/suite-runner).

| Ref | Fact | Cite |
|---|---|---|
| github/main d6e86ee (2026-10-03 07:54) | split planner knows only `none` / `mutant` / `pytest-node` | src/suite_runner/split/planner.py:93, :128, :130 |
| github/main d6e86ee | split history junit names hard-coded per suite id (7 entries) | src/suite_runner/split/history.py:31-42 |
| local main dd695a9 (2026-10-04 07:33, 293 commits ahead of github/main) | recipe runner kind `generic` exists: collect line must be `a::b`, case_id = address (SR248) | src/suite_runner/recipe/kinds/generic.py; docs/tasks/SR248_recipe_contract_path.md:32 |
| local main dd695a9 | split planner unchanged: same 3 unit kinds | split/planner.py:93, :128, :130 |
| local main dd695a9 | spec story 22 = generic collect format (one JUnit address per line); runner kinds list | docs/wayfinder/saas/spec.md:53, :210 |
| local main dd695a9 | no spec story / task splits a generic recipe into chunks | grep "split" over docs/tasks/SR24x-29x + saas spec |
| local main dd695a9 | new consumers onboard as run recipes, not catalogue + Make + adapter; onboarding waits until saas-mvp merged + deployed to Azure by operator | docs/wayfinder/multicloud/spec.md:260 |

Two gaps, not one:
1. **Collect/verdict** for generic = built (SR248, on local main / saas-mvp; not on github/main yet).
2. **Split** for generic = not built: planner groups only pytest-node (`::` module) and mutant ids; history reads `_JUNIT` names, not a recipe's results glob.

Consequence for ticket 07 L3: catalogue/rrc.toml + adapters/rrc/ path is the old onboarding route; Suite Runner's own spec moves new consumers to recipes (multicloud spec.md:260). L3 wording likely changes to "RRC run recipe (generic kind) + test image"; confirm in Q2.

## Answers

- Q1 (surn_productionize_map = surn_saas, 2026-10-04, facts at saas-mvp 81a2fca): split for generic recipes is **unclaimed, not in saas spec**. Nearest owner surn_saas (recipe path on saas-mvp). **No date**: needs that session's operator go-ahead, not yet asked (surn_saas will put it to its operator and reply).
  - Today: recipes have no `split` field; `worker/recipe_attempt.py` runs one attempt. SR279 already names "recipe split support" as blocker for moving suite-runner itself onto a recipe (its adapter split=auto) -> RRC is not the only consumer.
  - Effort if approved: 1 Codex lane (recipe `split` + `unit_kind: junit-address` grouped by part before `::`; planner history from recipe `results` glob not `_JUNIT`; `{ids}` in test command; chunk JUnit merge) + maybe 1 small lane for worker chunk wiring. ~0.5 day lane time **after saas-mvp merges to main**; queue ahead: SR277, SR279, SR266 -> SR280 -> SR283, then full-suite loop. Azure deploy operator-gated after that.
- Q2 (surn_saas, 2026-10-04, saas-mvp 81a2fca): one-chunk generic recipe before split = **allowed by code; blocked by deploy**.
  - (a) Earliest cloud run = after saas-mvp merges to main AND operator deploys to Azure. Recipe path only on saas-mvp (not main, not deployed). legalcopilot install frozen, product never runs there -> nothing sooner.
  - (b) Custom image OK: recipe lock = one `pool_image` `<ref>@sha256:<64 hex>`. No size cap in code. `timeout_class` / `resource_class` free strings (schemas/v1/run-recipe.json); real limits = operator's Batch pool + timeout table. Multi-GB image pull + ~53 min one-chunk run **unmeasured**. Repo access: deploy key (operator) or App installation token (SR282, in progress).
  - (c) One-chunk wall time: **unknown** — no recipe has run in cloud yet; first measured run = operator-repo recipe proof after deploy.
  - Ticket 07 L3 changes: no catalogue/rrc.toml, no adapters/rrc/; RRC ships recipe (generic) + test image + lock.
- Q3 (operator 2026-10-04: a): round 56 builds cloud-free parts: L1, L2, L5 (split units + junit out), L7, plus RRC generic recipe + test image + lock. Cloud gate waits for saas-mvp merge + operator Azure deploy + generic split. Targets (suite <= 15 min, gate <= 10 min) move to **round 57**. No local pool (ticket 07 Out stays).

## Answer

| Item | Value |
|---|---|
| Owner of generic split | surn_saas (surn_productionize_map session), unclaimed until its operator says go |
| Effort | 1 Codex lane + maybe 1 small worker-wiring lane, ~0.5 day lane time |
| Date | none; starts after saas-mvp merges to main (queue SR277, SR279, SR266 -> SR280 -> SR283, full-suite loop), then operator Azure deploy |
| One-chunk fallback | allowed by code, same deploy gate; wall time unknown (no recipe run in cloud yet; 53 min serial local 2026-10-03, ~28.5 min after L1+L2 est.) |
| Round 56 order | L1, L2, L5, L7 + RRC recipe/image/lock; cloud gate + L4/L6 after deploy |
| Suite target met | round 57 |
| Ticket 07 L3 amend | recipe (generic kind) + image + lock, not catalogue/rrc.toml + adapters/rrc/ (multicloud spec.md:260) |
| Ticket 06 blockers | unchanged (none added) |
