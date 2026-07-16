# The five complexity dimensions

Each feature is scored **0–10 per dimension**, as the *marginal* complexity it adds. The set is deliberately cross-framework: two path/understandability metrics, two coupling metrics, one change-cost metric. Together they separate "hard to write" from "hard to own" — the distinction LOC hides.

For every score, capture two sentences for the methodology table: **what the number means here** and **how you derived it this run** (which artifact you counted, which tool you ran, or that you estimated and why).

---

## 1. Cyclomatic (McCabe)

- **Means:** independent execution paths the feature introduces — decision points (`if`, `&&`, `||`, `?:`, `case`, loops, `catch`) + 1 per function, summed over the feature's functions.
- **Why it matters:** testability — the minimum number of test cases to cover it. Weak proxy for understandability (it over-counts flat guard clauses).
- **Measure:** `escomplex` / `typhonjs-escomplex`, ESLint `complexity` rule, or count decision points in the diff by hand.
- **Estimate:** count the branch keywords in the proposed pseudocode.
- **Anchors:** 0–2 straight-line glue · 3–5 a couple of branches · 6–9 one branchy function · 10 multiple heavily-branched functions.

## 2. Cognitive (SonarSource)

- **Means:** how hard the feature is to *read*. Increments for breaks in linear flow, and **extra increments for nesting** (a `.some()` inside a `.some()` costs more than two flat guards). Flat early-returns are nearly free.
- **Why it matters:** understandability during maintenance — the metric built to fix cyclomatic's "nesting problem."
- **Measure:** SonarQube / SonarLint cognitive-complexity report.
- **Estimate:** count flow-breaks, then add the nesting depth at each. Flat guard-heavy code scores *low* even at high cyclomatic.
- **Anchors:** 0–2 linear · 3–5 branchy but flat · 6–8 nested control flow · 9–10 deep nesting / interleaved conditions.

## 3. Coupling (fan-out + layer spread)

- **Means:** how many modules the feature touches and how many architectural layers it crosses (types → utils → config → server → UI → store …). Widened function signatures and new cross-module imports count.
- **Why it matters:** blast radius — a change here ripples outward.
- **Measure:** `madge` / `dependency-cruiser` for the dependency edges the feature adds; count distinct files and layers in the diff.
- **Estimate:** count the files the feature would span and the distinct layers among them.
- **Anchors:** 0–2 one module · 3–5 a few modules, one layer · 6–8 several modules across 2–3 layers · 9–10 spans 4+ layers / a full cross-cutting data path.

## 4. Connascence (Page-Jones)

- **Means:** the strength × locality of coupling the feature adds. Score up for each connascence introduced, weighted by kind and distance: name < type < meaning < position < algorithm (weakest→strongest), and worse when the coupled sites are far apart.
- **Why it matters:** the *kind* of coupling predicts refactor difficulty. A magic-string name shared across four layers, or two functions that must implement the same rule, is far worse than a local shared constant.
- **Measure:** no clean tool — inspect for: the same literal bound in N places (name), optional-field "absent means X" invariants (meaning), duplicated domain logic (algorithm).
- **Estimate:** enumerate the connascences and rate by kind+distance.
- **Anchors:** 0–2 local/weak only · 3–5 one cross-file name/type binding · 6–8 meaning or duplicated-logic coupling across files · 9–10 connascence of algorithm across layers, or an invariant pinned into persisted data.

## 5. Change-amplification (Ousterhout)

- **Means:** how many places must change together for one logical change to this feature. Duplicated knowledge and multi-site name bindings drive it up; a deep module behind one interface drives it down.
- **Why it matters:** the dominant long-term maintenance cost — "A Philosophy of Software Design"'s first symptom of complexity.
- **Measure:** trace one plausible future change (e.g. "redefine what counts as X") and count edit sites.
- **Estimate:** same trace, on the proposed design.
- **Anchors:** 0–2 change is local · 3–5 two coordinated sites · 6–8 several sites, easy to miss one · 9–10 the same knowledge duplicated across independent implementations.

---

## Reading the scores back

- **Deep module** (good): high cyclomatic/cognitive, *low* coupling/connascence/change-amp. Expensive to write, cheap to own. Behind a narrow interface. Usually worth keeping.
- **Shallow-and-wide** (suspect): low cyclomatic, *high* coupling/connascence/change-amp. Cheap to write, expensive to own. Little logic behind a fat, cross-layer interface. Prime candidate to cut or fold in.
- Sum the last three (coupling + connascence + change-amp) into an **"ownership cost"** subtotal — it's the number that best predicts what the feature costs *after* it ships.
