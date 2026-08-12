---
name: cmux-orchestration
description: Pick the right tool for parallel work — cmux lane (codex/grok) vs Claude teammate vs a new worktree+workspace — then write the brief, open the lane, verify it, check whether it finished, and clean it up. Use when the user says "spawn lane", "split into lanes", "run this in parallel", "spawn teammate", "worktree for this feature", "isolate this task", or when a large job needs cutting up for several agents. Also use to AUDIT lanes already running — "are the lanes done", "did codex finish", "check the lanes", "which lanes are still open", "close the finished lanes", "clean up the panes" — via `lane-status.sh` (§5.1), the recovery path when no watcher was armed. Requires cmux — for pure Claude teammates see `agent-teams`.
---

# Parallel work: lane, teammate, or workspace

Distilled from one session running ~20 lanes and 5 teammates on a real codebase. Every rule
here comes from a specific failure, not from theory.

## 1 · Picking the tool

| Job | Tool | Why |
|---|---|---|
| Writing/editing code with clear file boundaries | **cmux lane + codex** | codex runs inside the repo, can commit, is cheap |
| Read → synthesise → produce a document | **Claude teammate** (`Agent`) | needs judgment, web reading, prose |
| Competitor survey, market research | **Claude teammate** | same |
| Mapping a codebase, finding structural defects | **Claude teammate** | sees what file-by-file reading misses |
| A genuinely different project/repo | **new cmux workspace** | fully separate context |
| Repo-wide refactor | **one lane, running ALONE** | see §4 |

**Always keep one orchestrating chat.** The main chat holds the plan, writes the briefs,
**verifies the results**, and commits the coordination work. Lanes commit their own code; the
main chat commits `PLAN.md`. Never let both sides edit the plan file.

### 🔴 A "lane" means a **cmux pane**, not a backgrounded `codex exec`

The temptation: `Bash("codex exec ... &")` with `run_in_background` — looks the same, tidier,
no cmux involved. **It is not equivalent**, and here are three measured reasons, not preferences:

1. **You are blind for the whole run.** `codex exec ... | tail -40` prints nothing until it
   exits — the output file sits at **0 bytes** for the entire turn. You cannot tell whether it
   is reading, editing, or hung. In a cmux pane the user **and** you see every step.
2. **The user cannot intervene.** A lane heading the wrong way that only you can see runs to
   the end of its turn before it can be corrected. In a pane, the user stops it immediately.
3. **It cannot answer a prompt.** Anything needing one question-and-answer round leaves
   `codex exec` frozen or silently skipping.

Checking progress while blind means going the long way round: `git status`,
`find <dir> -newermt '-4 minutes'`, `ps -o etime,time` — all of it just to compensate for what
a pane shows for free.

**Rule:** writing code ⇒ **always** `cmux new-split` + `codex`. Use `codex exec` only for a
short one-shot command that needs no monitoring. If a project's own loop documentation tells
you to use `codex exec`, **fix that documentation** rather than following it.

### 1.1 · Worktrees — when to split one off, and where to put it

A lane running in the **current checkout** is the default: cheap, no extra disk, no
`node_modules` reinstall. Split off a **git worktree** only when one of these holds:

- two jobs **could touch the same file** — an `owns` boundary cannot cut them apart cleanly
- the job needs its **own branch** to open an independent MR
- the job runs **unattended**, and you don't want it touching the tree you're working in

```bash
WORKTREE_ROOT="$HOME/cmux/worktrees/$(basename "$(git rev-parse --show-toplevel)")"
mkdir -p "$WORKTREE_ROOT"
git worktree add "$WORKTREE_ROOT/<slug>" -b <type>/<slug>   # feature/ bugfix/ chore/ improve/
cd "$WORKTREE_ROOT/<slug>" && <your project's worktree setup>   # ← NOT optional, see below
cmux new-workspace --name "<type>/<slug>" --cwd "$WORKTREE_ROOT/<slug>" --focus true
```

🔴 **A fresh worktree looks like the repo and cannot run it.** `git worktree add` gives you
exactly the tracked files and nothing else — and the things it leaves out are precisely the ones
whose absence produces a *green-looking* failure rather than an error.

Four categories, each failing differently *(all four hit for real, 2026-08-11)*:

| Missing | Why it hurts |
|---|---|
| **gitignored config** — `.env*`, credentials, per-app tool config | usually the only honest error you get: "config not found" |
| **gitignored config that carries a server-assigned ID** | far worse: the tool does not error, it **creates a duplicate remote resource** instead of updating the existing one |
| **`node_modules`** — never shared between worktrees | module-not-found, or a lane silently reimplementing a missing library by hand |
| **build output the runtime points at** — compiled server bundles, static asset dirs | 🔴 **the worst class.** The stack reports itself healthy — "all services ready", HTTP 200 — while every handler behind it is dead |

The last row is the one to design against. The most expensive instance in the original session
was an **empty stub** of an env file: the client booted with no API key and hung on a spinner,
with no console error, no failed request, and every server-side check green. Hours.

**So: write one idempotent setup script, and have it enumerate what YOUR project needs.**
Everything gitignored that the app reads, plus every build artifact a config file points at.
Run it as the worktree's only setup step, and again whenever it fails — idempotent means you
never have to reason about whether it already ran.

```bash
git status --ignored --porcelain | grep '^!!' | head -40   # the candidate list, from the repo itself
```

🔴 **Tools that remember a per-directory selection will have nothing to remember.** Any CLI
that stores "which config/app/profile you picked" keyed to the working directory treats a brand
new worktree as a first-time run — so a command that works in your main checkout prompts, picks
wrong, or fails there. Pass the selection explicitly in the worktree, or bake it into a script.

🔴 **Killing a dev stack can leave an orphan holding a port.** A killed parent can leave a child
server alive, and a cleanup script run *from the worktree* will not sweep it, because the process
belongs to a different checkout. Find the holder and confirm its cwd before killing — another
project's server may be on that port:

```bash
for p in $(lsof -ti tcp:3000 -sTCP:LISTEN); do
  echo "$p $(lsof -a -p $p -d cwd -Fn | grep ^n | sed s/^n//)"
done
```

🔴 **With two checkouts of one repo, ask whose server the browser is talking to — first, every
time.** The same command above answers it. Editing the worktree while the main checkout serves the
page produces an unbroken run of green measurements and a page that never changes: correct file,
correct bundle, correct API key, wrong checkout. That consumed most of an evening, and no
individual check was wrong — they were all answering a question nobody had asked.

🔴 **Put worktrees OUTSIDE the repo tree.** A `<repo>/.something/worktrees/<slug>` convention
caused a real failure: a CLI that scans the whole tree recursively for its config files found
the same config duplicated across 3 nested worktrees and **refused to start** — the error
complained about duplicate configuration, naming a file the developer had not touched. Every
scan-the-whole-tree tool hits this class of bug: linters, test runners, monorepo tools, and any
framework CLI that auto-discovers apps. `~/cmux/worktrees/<repo>/<slug>` avoids it, which is the
same reason worktree managers like Conductor keep their workspaces outside the repo.

🔴 **A new worktree ⇒ the codex lane will hit the directory-trust prompt** *(hit for real
2026-08-11)*:

```
Do you trust the contents of this directory?   › 1. Yes, continue
```

`-a never` does **not** suppress this prompt — it only suppresses command-approval prompts.
And this is the **blind spot in §5.0 step 4**: the `touch` probe still passes, and
`ps aux | grep -c` still counts a live process, so the lane looks exactly like one that is
running while it sits there indefinitely. One more verification layer is mandatory:

```bash
cmux read-screen --surface surface:N --lines 15   # MUST show activity, not a question
cmux send-key --surface surface:N Enter           # if stuck at the prompt (option 1 preselected)
```

**A live process ≠ a lane making progress.** No signal from `ps` distinguishes the two.

### 1.1a · Tearing one down — merge, then remove, in this order

A worktree that outlives its feature is not free: it holds a checkout, a `node_modules`, a cmux
workspace in the sidebar, and a branch you will later fail to recognise. Clean up as soon as the
branch is merged — but in an order that cannot destroy work.

```bash
# 1 · Is anything uncommitted? A worktree lane CANNOT COMMIT (see §2 rule three), so the
#     answer here is "yes" far more often than in your main checkout.
git -C "$WT" status --porcelain          # MUST be empty before anything below

# 2 · Is anything unpushed? Local commits die with the branch.
git -C "$WT" log --oneline @{upstream}.. 2>/dev/null || git -C "$WT" log --oneline main..

# 3 · Nothing still running from inside it? A server whose cwd is deleted keeps its port.
lsof -a -d cwd -- "$WT" 2>/dev/null | tail -n +2

# 4 · Only now
cmux close-workspace --workspace <ref>   # the workspace outlives the directory otherwise
git worktree remove "$WT"                # refuses if 1 was not clean — that is the safety net
git branch -d <branch>                   # refuses if not merged — also a safety net
git worktree prune                       # clears stale admin entries
```

Four behaviours, measured rather than assumed — and each one is the reason a step exists:

| Command | What it actually does |
|---|---|
| `git worktree remove` | **refuses on modified *or untracked* files.** Untracked alone is enough. `--force` deletes them permanently |
| `rm -rf <worktree>` | git still lists the entry, marked `prunable`. `git worktree prune` clears it |
| removing a worktree | does **not** delete the branch. It stays, and later looks like someone else's |
| `git branch -d` | **refuses an unmerged branch** and suggests `-D`. Take the refusal as information |

🔴 **`--force` and `-D` are the two commands that turn cleanup into data loss** — and a worktree
is exactly where that hurts most, because a codex lane running in one **cannot commit at all**,
so everything it produced is sitting in the working tree by design. Reaching for `--force`
because "remove refused" is reaching past the guard that just told you the work is still there.

**If `remove` refuses, that is the whole message.** Go read what is uncommitted, harvest it —
commit it from the main checkout, or copy the files out — and only then remove.

⚠️ **Close the cmux workspace before deleting the directory**, not after. A workspace whose
`--cwd` no longer exists still appears in the sidebar, and its panes open in a directory that is
gone; you then have to identify it by elimination among workspaces that all look alike.

### 1.2 · The plan is the artifact; the dispatch is not

**`docs/plans/<slug>.md` is the brief**, and it is committed. Write it to be complete enough
to review on its own: the problem with `file:line` evidence, the design decisions and what was
rejected, and machine-checkable acceptance criteria. That is the same content a good brief
needs, so there is no second document to keep in sync — and it survives the lane, gets reviewed
in the MR, and is visible to everyone rather than sitting on one machine.

The **dispatch instructions** are a different thing and do not belong in it:

| Content | Where | Lifetime |
|---|---|---|
| Problem, evidence, design decisions, acceptance criteria | `docs/plans/<slug>.md` — **committed** | durable, reviewable |
| `owns` paths, "lane X holds Y — don't touch", "do not commit and why" | the `cmux send` string itself | one dispatch |

They are short enough to pass inline, and they are **wrong the moment that lane closes** — a
committed `owns` list misleads the next reader into thinking it is a real constraint. Point the
lane at the plan and state only the boundary:

```
codex -s workspace-write -a never -c sandbox_workspace_write.network_access=true \
  "Lane <ID>. Read docs/plans/<slug>.md and implement it.
   You own ONLY: <paths>. Do not edit anything else.
   Do NOT commit or git add — .git is outside this sandbox's writable root, so it would fail
   anyway. Your work stays on disk; report the full list of paths you touched."
```

⚠️ **Reads are NOT confined to the worktree; writes are.** Verified with
`codex sandbox -- cat <file outside the repo>` (succeeds) versus
`codex sandbox -- touch <file outside the repo>` (`Operation not permitted`). So a plan file
can live anywhere the lane can read — but anything the **lane writes** must be inside the
worktree. That applies to the §5.0 step-3 probe: it needs a gitignored scratch directory in the
repo (`.lanes/tmp/`), and `/tmp` will not work.

## 1.3 · Which model, and at what effort

Two separate decisions, and conflating them is how a two-line deletion gets `xhigh` while a
migration against live data gets the default.

### Who does what

| Role | Model | Why |
|---|---|---|
| **Orchestrating chat** — plan, briefs, verification, commits | **Opus** | it holds the whole session's context and is the only thing that verifies; a cheaper orchestrator produces cheaper verification, which is the one thing you cannot afford |
| **Writing code in a lane** | **codex** (default) or **Sonnet 5** via `Agent` | codex runs inside the repo and is sandboxed |
| **Read → synthesise → judge** | **Claude teammate** (`Agent`) | see §1 |
| **Second opinion / adversarial review** | **grok**, or a codex lane with a refute-only brief | a different model family is worth more than the same one twice |

### codex: `sol` vs `terra` — state of knowledge, honestly

```bash
codex -m gpt-5.6-sol   -c model_reasoning_effort=xhigh --strict-config "…"
codex -m gpt-5.6-terra -c model_reasoning_effort=high  --strict-config "…"
```

**Verified:** `~/.codex/config.toml` defaults to `model = "gpt-5.6-terra"`,
`model_reasoning_effort = "high"`. `gpt-5.6-sol` and `gpt-5.5` also exist.

⚠️ **`--strict-config` catches unknown config *keys*, not invalid *values*** — see the effort
section below, where `model_reasoning_effort=bogus` was accepted and echoed. Pass it anyway (it
catches a mistyped key name), but do **not** treat it as validation of what you set.

🔴 **What differentiates `sol` from `terra` is not documented anywhere I could find, and this
skill will not invent it.** What *is* recorded: one session ran ~20 `sol` lanes covering
two-line deletions, multi-table migrations with live-data backfill, a 30-minute corpus generator,
and adversarial review — all successful. There is no comparable `terra` sample.

**So: pin the model explicitly on every dispatch rather than inheriting the config default**, and
when you learn what actually distinguishes them, write it here. A matrix built on guessed model
characteristics is worse than an honest gap, because it gets followed.

### grok — different family, no sandbox

```bash
grok --effort xhigh --permission-mode acceptEdits "…"     # --effort aliases --reasoning-effort
```

Reports itself as **Grok 4.6** in the TUI footer. Good for a **second opinion** precisely because
it is a different family. ⚠️ It has **no filesystem sandbox and can run `git commit`** (§5.0.1) —
so "do not commit" is a sentence in your brief, not a property of the tool, and you verify with
`git log` afterwards, not by trusting `--deny`.

### Effort — the full ladder, and the trap in setting it

```bash
-c model_reasoning_effort=minimal|low|medium|high|xhigh     # codex
--effort minimal|low|medium|high|xhigh                      # grok (aliases --reasoning-effort)
```

🔴 **Neither CLI validates the value, and `--strict-config` does NOT help.** Verified
2026-08-13: `codex -c model_reasoning_effort=bogus --strict-config` starts normally and prints
`reasoning effort: bogus` in its own header. The string is passed through to the API. **A typo
does not fail — it silently becomes whatever the provider defaults to**, and you run a whole
session at an effort you did not choose.

So: **read the value back before trusting it.** codex echoes `reasoning effort: <value>` in the
`exec` header; grok renders it in the TUI footer as `Grok 4.6 (xhigh)`. Both echo what you typed,
so this catches your typos — it does not prove the provider honoured the value. Treat an
unrecognised value as *unknown effort*, not as your intended one.

### Choose by blast radius, not by how hard the task feels

**The question is not "is this complex" — it is "what does a wrong answer cost".**

| Effort | Use for | Examples |
|---|---|---|
| **`minimal`** | one-shot mechanical edits where the diff is the whole spec | rename a symbol repo-wide · bump a version string · delete a dead import |
| **`low`** | scripted or templated work with no judgment | generate boilerplate from an existing pattern · apply a codemod you already validated |
| **`medium`** | ordinary feature work, reversible, covered by tests | add a field to a form · a new read-only endpoint · wire an existing component |
| **`high`** | mechanical but consequential; needs the repo's conventions followed | delete a hardcoded constant · declare a relation the DB already enforces · add an audit row |
| **`xhigh`** | **irreversible, or arithmetic that reaches a customer** | any migration touching live data · anything computing a rate or denominator · adversarial review · a generator whose output everything else is graded against |

**Verified in practice:** one session ran `high` and `xhigh` lanes across ~20 dispatches — two-line
deletions through multi-table migrations with live backfill — and both behaved as briefed.
`minimal` / `low` / `medium` are the documented ladder positions; they have **not** been exercised
here, so treat the examples above as intent, not measurement, and correct this table when you use
them.

**Default when unsure: `high`.** It is the config default for a reason, and the cost gap between
`high` and `xhigh` is far smaller than the cost of one bad migration.

⚠️ **Do not raise effort to compensate for a vague brief.** Reaching for `xhigh` because you are
unsure what the lane should do means the fix belongs in `## done`, not the flag. In one session
the regression that escaped came from an `xhigh` lane that did exactly what its brief said — the
brief named a prohibition without an enforceable check, and the lock test used a fixture
incapable of failing. **Effort buys care. Acceptance criteria buy correctness.**

## 2 · The lane brief — mandatory sections

A brief missing any section below fails in a way it has already failed for real:

```markdown
# Lane <id> — <one-line description>

## owns — edit ONLY these
<list of paths>
Lane <other> is running and holds <path> — do not touch.
Need a file outside this scope ⇒ write it under `## Blocked on`, do not edit it yourself.

## Problem
<concrete evidence: file:line, query output, a measurement — not a general description>

## Direction
<design constraints, known traps, precedent already in the repo>

## done — acceptance criteria
- [ ] <machine-checkable, not "fixed it">

## Before committing
<the exact test command> · No `git add -A` · **MUST write tests**
```

### 🔴 Rule one: derive `owns` from the **acceptance criteria**, not from where you spotted the bug

Got this wrong four times in one day, each time at a different layer:

- assigned the rule "numbers must belong to one series" but `owns` was missing a page → a later lane had to clean up
- assigned a three-state rule, but the lane could not reach a page outside `owns`
- wrote the criterion *"both pages read the same source"* then granted edit rights to only one page
- assigned phases from a draft, after which the final version changed the target shape

**Ask before writing `owns`:** *what does this acceptance criterion require touching?* Then
list all of it. A rule reaches exactly the files in `owns` — not one line further.

### 🔴 Rule two: a long brief is a cost, not diligence

Context helps **you** think. For an executor, too much context makes it **read instead of act**.

Seen for real: a brief that required reading four documents (architecture, plan, conventions,
a directory survey) before writing the first line. The lane ran **16 minutes, produced 0
files**, and never responded. Rewritten to 41 lines — **6 hard constraints** in place of three
pages explaining *why* — and ended with:

> *Do not read `PLAN.md` or `architecture.md` — everything you need is above.*

**Rule:** a brief carries **conclusions**, not the reasoning that produced them. Instead of
recounting a finding, write the constraint:

```
❌ three paragraphs on where RLS is off, which policy consumes which setting, why it is safe
✅ "The JOIN in workspaceForAuthUser is the only line of defence. Do not weaken it."
```

Exception: an **audit / survey lane** needs full context, because its deliverable *is*
judgment. An execution lane does not.

### 🔴 Rule three: a lane running inside a **git worktree** CANNOT COMMIT

*(2026-08-10 — a lane wasted an entire turn because its brief told it to "commit as soon as
you're done".)*

```text
fatal: Unable to create '<main-repo>/.git/worktrees/<name>/index.lock':
       Operation not permitted
```

Inside a worktree, `.git` is **not a directory** but a **file pointing back at the main repo**.
Both `index.lock` and the **object store shared across all worktrees** sit **outside** the
writable root of `-s workspace-write`, so `git add` is blocked **before it can even stage**.

**You can open it with `--add-dir <main-repo>/.git` — but think hard first.** That grants write
access to git metadata **shared by EVERY worktree**: one bad lane can move the `main` ref. If
the project has a "never touch `main`" rule, this route **contradicts that rule**.

**The safer shape, and nothing is lost:**

```
lane reports done + lists EVERY path it created/modified
   → lead runs acceptance itself (§3)
      → lead commits
```

Nothing is lost because §3 **already** requires the lead to run acceptance; and it's better:
**nothing enters history before it has been checked**. The trade-off is that the brief must
demand the **complete path list** — the lead `git add`s exactly that list, so a missing line
is a lost file.

⚠️ **Write the REASON into the brief**, not just "don't commit". Without the reason the lane
assumes it hit an environment fault and starts looking for a way around: `git add -A`,
`git stash`, changing `--git-dir`, or writing into `.git` directly. State it plainly: *your
work sits on disk untouched; not committing loses nothing.*

### Three sentences to state outright, or the lane will skip them

- **`MUST write tests`** — a lane fixing the right thing without writing a test is routine; the
  suite stays flat and the orchestrator has to make it up afterwards.
- **`No git add -A`** — another lane has work in flight; one `add -A` sweeps it all in.
  *(Inside a worktree a lane cannot stage anything at all — see rule three. This sentence is
  for the lead, and for lanes running outside a worktree.)*
  Happened for real: four lanes running in parallel, the typography-scale lane committed with
  `git add -A` and **swept up** two other lanes' work — lane A's engine-label + 7 routes,
  lane B's `components.json` + `skeleton.tsx` — into one commit titled *"define typography
  tokens"*. No work was lost, but three lanes ended up in a single commit that is
  **unreviewable and cannot be reverted separately**, and the other two lanes suddenly saw a
  clean `git status` and assumed they had done nothing.
  ⇒ Write it into the brief as an **instruction with a list**: *"`git add` only the exact paths
  in `owns`, listed one by one"* — `No git add -A` alone is **not enough**, because it states
  what not to do without stating what to do.
- **Environment traps** — occupied ports, environment variables, the exact command to run. A
  lane cannot guess these, and will burn a round discovering them.

## 3 · Verification — do not trust the report

A lane reporting "done" is **not** evidence. Both failure shapes have been seen:

- fixed the behaviour **correctly**, wrote **no** test → breaks silently at the next edit
- code **correct**, the number on screen **wrong** → only visible by opening the page

**Procedure after every lane:**
1. run typecheck + the full test suite + smoke — **run it yourself**, don't re-read the lane's words
2. count the tests: did the number go up? If not and the brief demanded tests ⇒ the lane skipped them
3. **open the page / run the query** and check the real number
4. take any single claim from the report and verify it yourself

In the original session, every serious defect was found by **opening the page and looking**,
not by tests. Typecheck green, tests green, smoke green — and the number on screen still wrong.

## 4 · The parallelism ceiling — tell the user the truth

"More parallel is better" has a hard limit:

- **A repo-wide refactor cannot be split.** Two lanes moving files at once = a broken repo.
  It is the critical path: run it alone, close the other lanes first.
- **Don't give lane B work that lane A is going to delete.** That's rework, not parallelism.
- **Real parallelism = completely disjoint `owns`.** One overlapping file is enough to break it.

When the user wants more lanes than the work supports, **state the constraint** instead of
opening lanes for the sake of it. The fastest route to the goal is usually to close the current
lanes and run the critical path alone.

## 5 · Operating cmux

```bash
cmux new-split down                        # create a pane
cmux rename-tab --surface surface:N "<ID>" # NAME IT — see below, this is not optional
cmux list-panes                            # is the pane still alive?
cmux list-pane-surfaces --pane pane:N      # get the surface AND its name
cmux send --surface surface:N "<command>"  # send
cmux send-key --surface surface:N Enter    # Enter must be sent separately
cmux close-surface --surface surface:N     # close the lane
```

### 🔴 Name every lane the moment you create it

`new-split` has **no `--name` / `--title` flag** — a fresh split is anonymous, and
`cmux list-panes` prints only `pane:281`, `pane:282`. With three lanes open you are holding a
mental map from surface number to lane ID, and surface refs get **renumbered** on every
create/close (§5), so that map goes stale exactly when you are busiest.

The fix is one command, run immediately after `new-split`:

```bash
cmux new-split right                                    # → OK surface:431 workspace:5
cmux rename-tab --surface surface:431 "A1 auth-refactor" # → OK action=rename tab=tab:431
```

`list-pane-surfaces` then answers "which lane is this" without you remembering anything:

```
--- pane:281 ---
* surface:431  A1 auth-refactor  [selected]
--- pane:282 ---
* surface:432  A2 rate-limit  [selected]
```

**Name it with the lane ID from the brief**, not a description — `A1 auth-refactor`, `A2 rate-limit`,
`B7 cache-layer`. The ID is what the plan file, the dispatch string, the commit message and your
own notes all use; a prettier name breaks that chain.

Three reasons this earns its one line:

1. **The user sees it too.** They are watching these panes. An unnamed tab tells them nothing about
   what is running; the lane ID lets them match it to the plan and stop the right one.
2. **A dead lane becomes visible as an absence with a name attached** (§5). Reconciling
   "surfaces I dispatched" against "surfaces alive" is far easier when both sides read `A2`
   instead of `432`.
3. **Renumbering stops mattering.** The name survives; the number does not.

⚠️ `rename-tab` takes `--surface` and renames the **tab** that owns it (`tab=tab:431`). That is the
correct call — there is no `rename-surface`.

🔴 **Renaming a pane in ANOTHER workspace needs `--workspace` too, or it fails `not_found: Tab
not found`** *(measured 2026-08-13)*. `--surface` alone is resolved within the caller's own
workspace, so the moment you `new-split --workspace workspace:N` you must carry that flag through
to the rename — and to `send`, `send-key` and `read-screen` for the same surface:

```bash
cmux new-split right --workspace workspace:39                       # → OK surface:455
cmux rename-tab --workspace workspace:39 --surface surface:455 "DEMO-1"
``` `tab-action --action rename --title <text>` is the
longer equivalent if you ever need the other flags.

### 5.0 · Five steps to open a lane — in this exact order

```bash
# 0. baseline BEFORE you dispatch, or step 4's count proves nothing
pgrep -x codex | wc -l

# 1. brief to a FILE, never stuffed into the send string — and a TRACKED one
Write docs/plans/briefs/<ID>.md

# 2. create the pane, take the surface from new-split's own output
cmux new-split right          # → OK surface:33 workspace:5
cmux rename-tab --surface surface:33 "<ID>"   # NAME IT NOW — anonymous panes cost you later
#    --panel/--surface take a SURFACE ref; passing a pane ref fails "Surface not found".
#    To split inside another workspace: cmux new-split right --workspace workspace:N

# 3. PROBE — make the shell prove it is reading keystrokes
#    ⚠️ probe INSIDE the repo, not /tmp: step 4's sandbox cannot write outside the worktree
cmux send --surface surface:33 "touch .lanes/tmp/lane-probe-<ID>"
cmux send-key --surface surface:33 Enter
ls .lanes/tmp/lane-probe-<ID> # the file MUST appear. If not ⇒ close the pane, create it again.

# 4. only now send the real command, and it is ONE SENTENCE pointing at the brief
cmux send --surface surface:33 'codex -s workspace-write -a never --strict-config -m gpt-5.6-sol -c model_reasoning_effort=xhigh -c sandbox_workspace_write.network_access=true "Lane <ID>. Read docs/plans/briefs/<ID>.md and follow it."'
#    ↑ pin the model and effort explicitly (§1.3) — never inherit the config default
#    ↑ --strict-config catches unknown CONFIG KEYS. It does NOT validate the effort VALUE:
#      a typo'd effort is echoed back and silently becomes the provider default (§1.3).
cmux send-key --surface surface:33 Enter
pgrep -x codex | wc -l                     # MUST be baseline+1. Same as baseline ⇒ it never ran.

# 5. READ THE SCREEN. A live process is not a working lane.
cmux read-screen --surface surface:33
```

🔴 **Step 5 is not optional, and it is the one people drop.** A first run in a new worktree stops
on `Do you trust the contents of this directory?`, which `-a never` does **not** suppress: the
process is alive, the probe passed, the count went up, and the lane has done nothing. The screen
is the only place that shows it. It also catches the opposite — a lane that already finished and
is sitting on its report while you assume it is still thinking.

🔴 **Do NOT count with `ps aux | grep '<your search string>'`** *(hit for real 2026-08-11)*.
The shell running your `grep` carries that string in its own command line, so the pattern
**matches the grep's own shell** and you count a lane that does not exist. The inverse bites
too: the count looks non-zero after a lane has died, and you nearly `kill` your own shell.
Match on the **process name** and confirm by cwd instead:

```bash
pgrep -x codex                                       # by name — cannot match your grep
lsof -p <pid> -a -d cwd -Fn | grep '^n' | cut -c2-   # confirm it belongs to THIS repo
```

🔴 **`--yolo` NO LONGER EXISTS — do not type it** *(corrected 2026-08-10; this document used to
teach that exact flag, and it burned two orchestration rounds)*. `--full-auto` is gone too. The
current CLI only has:

```
codex --help  →  -s, --sandbox <read-only|workspace-write|danger-full-access>
                 -a, --ask-for-approval <untrusted|on-request|never>
                 --approve-for-me · --dangerously-bypass-approvals-and-sandbox
```

Type a flag that doesn't exist and codex **exits immediately**, while `cmux send` **still
returns `OK`** — so it looks exactly like a running lane. **This is the trap step 3 does NOT
catch:** the pane is still at a shell, the `touch` probe still passes, only the lane doesn't
exist. That is why step 4 needs its own count line, and a bare `pgrep codex` is **not enough**
when the machine is running lanes from other worktrees:

```bash
pgrep -fl codex | grep -c network_access    # only the lane you just dispatched has this flag
pgrep -fl codex | grep -o 'Lane <ID>\.'     # exactly the lane you dispatched
```

🔴 **`-a never` is MANDATORY, not optional.** The lane runs in the background in a pane nobody
is watching. With `on-request` or `untrusted`, codex stops to ask for approval at the first
command it needs to run, and the lane **sits there indefinitely** — looking exactly like a lane
that is thinking. Many monitoring rounds were lost to precisely this: four panes open, none
making progress, the cause being four approval dialogs.

⚠️ **Two consequences of `-s workspace-write` MUST BE WRITTEN INTO THE BRIEF — the lane cannot
guess them:**

- **The sandbox has NETWORK OFF by default.** Any lane calling a real API without
  `-c sandbox_workspace_write.network_access=true` dies at exactly the point it matters most,
  and the error message never mentions the sandbox.
- **File writes are confined to the worktree** ⇒ **`/tmp` is not writable**. Every temp file
  must live inside the repo, in a gitignored directory *(e.g. `.lanes/tmp/`)*. This is also why
  step 3 moved where it probes.

🔴 **Two directories, and the line between them is what gets cited.**

| | Where | Tracked? |
|---|---|---|
| **Briefs, reports, verdicts** — anything a plan will ever cite | `docs/plans/briefs/`, `docs/plans/lane-reports/`, `docs/engineering/` | **yes** |
| **Probe files, scratch, sampler output** — read once, then dead | `.lanes/tmp/` | no, gitignored |

Put a brief in the gitignored directory and it becomes a citation with nothing behind it.
Measured 2026-08-13 in this repo: `PLAN.md` and two sibling plans cited **23** `.lanes/` paths;
**5 of the files were already gone**, including a lane report a slice's `done:` criterion named
as its evidence. Nobody deleted them on purpose — they were never saved, because the directory
was ignored. A brief for a slice still `[ ]` is the task statement itself; losing it loses the
work order.

⚠️ The rule is about **who will cite it**, not about how long it lives. A probe file is dead in
30 seconds and belongs in `.lanes/tmp/`. A brief outlives its lane by however long the plan
keeps pointing at it.

### 5.0.1 · Grok lanes — same pattern, one dangerous difference

`grok` (at `~/.grok/bin/grok`) takes a prompt argument like codex and drives a pane the same way,
so all five opening steps apply unchanged. Baseline with `pgrep -x grok`.

```bash
cmux send --surface surface:N 'grok --permission-mode acceptEdits \
  --deny "Bash(git commit:*)" --deny "Bash(git add:*)" --deny "Bash(git push:*)" \
  "Read docs/plans/briefs/<id>.md and carry it out exactly."'
```

🔴 **Grok has no filesystem sandbox.** `--cwd` only sets a working directory. Everything below
that codex enforces at the OS level, grok enforces **not at all**:

| | codex `-s workspace-write` | grok |
|---|---|---|
| Can it write outside the worktree? | No — kernel-enforced | **Yes** |
| Can it `git commit`? | No — `.git` of a linked worktree points outside the writable root | **Yes** |
| Network | Off unless `network_access=true` | On |

So "do not commit" stops being a property of the sandbox and becomes **a sentence in your brief**
— the only thing standing between you and a lane that commits half-finished work. Write it
explicitly, and **verify afterwards with `git log` rather than trusting the `--deny` flags**,
whose effect has not been confirmed here.

Prefer `--permission-mode acceptEdits` over `--always-approve`: the latter auto-approves *every*
tool execution, including bash, which is a much wider grant than editing files.

**Scope grok narrowly.** It is a good fit for a self-contained slice — one page, one component,
one document — and a poor fit for anything that must agree with another lane's in-flight
signature. When a codex lane is mid-way through writing a service, do not hand grok the
controller that imports it: give it the UI and a **frozen fixture**, and wire the two together
yourself afterwards.

⚠️ **If the lane-opening command is blocked by the harness's permission classifier** *(often at
`-a never`, since that is self-approval on behalf of another agent)*: **do not work around it**
by sending a bare `codex` and calling it done — that trades a self-running lane for one that
will hang. Do not rewrite the command to slip past the filter either, and ⛔ **do not add a
permission rule for yourself** *(that path is blocked too, and rightly so)*. Isolate the cause
with `cmux send 'echo test'` — if that works, `cmux` isn't blocked, only the command content
is. Then **tell the user**, so they can decide whether to allow it or run it themselves with
`! <command>` in the session.

🔴 **Step 3 cannot be skipped.** `cmux send` returns `OK` **even when the command falls into the
void** — `OK` means "the keys were typed", not "something read them". The only way to tell the
difference is to make the pane produce a **side effect visible from outside**. Verifying with
`cmux` itself means verifying with the thing that may be broken.

🔴 **Step 1 is not about tidiness.** Stuffing the whole brief into the `send` string means
typing thousands of characters through a **simulated keyboard**: quotes, backticks, newlines,
and unicode can all be reinterpreted by the terminal or the shell. With the brief in a file the
lane reads it **exactly as written**, and revising it mid-flight is just editing the file and
telling the lane to re-read it.

⚠️ **Take the surface from `new-split`'s output**, don't infer it from `list-panes`.
`new-split` prints `OK surface:33` directly; `list-panes` prints **panes** (`pane:30`) — two
different numbering systems, and guessing wrong sends the command into a different lane.

⚠️ **Panes die silently.** If the user closes a pane the lane is gone, **having committed
nothing**, and `cmux send` reports `not_found`. **Always `list-panes` before sending**, and
check `git log` rather than assuming the lane is running.

⚠️ **Surface refs get renumbered** when panes are created/closed. Re-fetch every time; don't
memorise.

🔴 **`pane:N` and `surface:M` do NOT run in parallel — never infer one from the other.** Measured
in a real session: `pane:35→surface:37` · `pane:36→surface:38` · `pane:37→surface:36` ·
`pane:38→surface:39`. The order is **completely scrambled**. `list-panes` prints only **panes**;
to know which pane runs which lane you must run `list-pane-surfaces --pane pane:N` for **each
one**. Closing by a guessed pane number closes the wrong lane.

🔴 **A dead lane does NOT show up in `list-panes` — it shows up as an ABSENCE.** You detect it by
listing every pane's surfaces and **comparing against the list of surfaces you dispatched**;
whichever is missing is a lost lane. Seen for real: a lane died at 10:27 and I reported it as
*"running"* for **three hours** across several rounds, because I was counting panes instead of
reconciling surfaces. Its work sat uncommitted the whole time.
**Rule: every round, compare the `mtime` of the files that lane holds against now.** A file
unchanged across several rounds **with no long-running process** ⇒ the lane is dead, not thinking.

⚠️ **`mtime` proves nothing about an agent that writes once at the end.** Seen for real
2026-08-11: a translation teammate showed an unchanged `mtime` for 7 minutes because it composes
the whole file and issues a single `Write` at the end. The `mtime` rule above is for **codex
lanes**, which edit incrementally. For a Claude teammate the only trustworthy signal is
**whether it has reported idle** — idle without a report means stopped, not working.

🔴 **Don't run the full test suite while a lane is writing files.** Seen for real: one run gave
`1 failed | 335 passed`, and the two runs immediately after gave `336 passed`. The cause was
another lane editing files mid-run. ⇒ A **single** red run while lanes are active is **not
evidence**; re-run before concluding, and don't report it as a finding.

Scope can be revised mid-flight — `cmux send` into a running lane. If the design changes after
the brief was sent, **stop the lane immediately**; don't let it build exactly to the brief and
wrong to the architecture.

🔴 **STUCK surface — `send` returns `OK` but never arrives.**

After a codex session exits, a surface can end up in a state where nothing reads keystrokes any
more. cmux still accepts `send`, still returns `OK`, still shows the pane in `list-panes` — but
**every command falls into the void**. `send`, `send --workspace`, and `send-panel` all fail the
same way.

**The decisive check:** create a new pane and send to it. A new pane always accepts. If the old
pane doesn't accept and the new one does ⇒ the old surface is stuck ⇒ **close it, don't try to
rescue it**.

⚠️ This is why `lane-health.sh` no longer concludes "BUSY": no answer has **two** meanings —
genuinely busy, or stuck. Distinguish with `ps` (is there a new process?), don't guess.

🔴 **`cmux send` sends KEYSTROKES, not commands.** It types characters into whatever currently
owns the terminal.

If a codex session is **still running** in that pane, the command you send — including
`codex '...'` — goes into **codex's input box**, not the shell. It never runs. No error, no
signal; the lane simply does nothing, and it takes 10 minutes to notice.

**Rule:** to run a new command, **close the old pane and create a new one**. Far cheaper than
guessing what state the terminal is in.

```bash
cmux close-surface --surface surface:N
cmux new-split right                                       # → OK surface:M
cmux send --surface surface:M "touch .lanes/tmp/probe-M"   # the §5.0 step-3 probe
cmux send-key --surface surface:M Enter
ls .lanes/tmp/probe-M                                      # the file MUST appear
cmux send --surface surface:M 'codex -s workspace-write -a never -c sandbox_workspace_write.network_access=true "Read docs/plans/briefs/<ID>.md and follow it."'
cmux send-key --surface surface:M Enter
pgrep -fl codex | grep -c network_access                   # MUST be ≥1
```

⚠️ Probing with `pwd` is **worthless**: the output stays inside the pane where you cannot read
it from outside, so "sent it, saw no error" gets misread as "it ran". A probe must leave a
**trace on disk**.

### 5.1 · What state is every lane in? — start here

⚠️ **Two facts about CLAUDE_PLUGIN_ROOT, and they pull in opposite directions** *(both
measured on a real install, 2026-08-13)*:

- Claude Code **substitutes** that placeholder when it loads a skill or command markdown
  file — including inside ordinary prose, which is why this paragraph spells the name out
  instead of writing it as a shell variable.
- It is **not an environment variable**. Type it into a Bash command yourself and the shell
  expands an unset name to nothing, so the path collapses to `/skills/…` and the script
  "does not exist".

So resolve it explicitly in any command you compose, and it works either way:

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -d "$ROOT" ] || ROOT="$(ls -d "$HOME"/.claude/plugins/cache/*/cmux-workflow/*/ 2>/dev/null | sort -V | tail -1)"
[ -d "$ROOT" ] || ROOT="$(ls -d "$HOME"/.claude/plugins/marketplaces/*cmux-workflow 2>/dev/null | tail -1)"
```

```bash
"$ROOT"/skills/cmux-orchestration/lane-status.sh --all      # or: /cmux-workflow:lanes
```

**Run this before anything else in §5**, and always when picking up a session whose lanes you
did not dispatch. It reads cmux's own turn-hook session store
(`~/.cmuxterm/<agent>-hook-sessions.json`, field `agentLifecycle`) and classifies every surface
as **RUNNING · DONE · BLOCKED · DEAD · EMPTY**, then prints what still needs verifying,
committing or closing. It is read-only — it never sends a keystroke — and it is the only check
here that can say **finished** rather than merely **alive**.

It is also the **recovery** path: if lanes were dispatched and no watcher was armed, this
reconstructs what happened after the fact, including lanes that finished unnoticed. That
failure is not hypothetical — 2026-08-13, two codex lanes in this repo ended at 18:53 and
18:57 and nothing reported it.

⚠️ It skips the caller's own pane, and it **excludes `claude` surfaces from every close
suggestion**: those are the orchestrating chat or a teammate, and closing one destroys
everything it has read. Never sweep them up with "close the DONE ones".

### 5.1a · A stalled lane — alive but not progressing

Only reach for this when §5.1 says `RUNNING` and you doubt it — a lane with no session-store
entry at all, or one you suspect never received its brief.

**The method: make the shell prove it is listening.**

```bash
"$ROOT"/skills/cmux-orchestration/lane-health.sh          # every pane
"$ROOT"/skills/cmux-orchestration/lane-health.sh 169 170  # specific surfaces
```

The script sends `touch <temp file>` into each pane and checks whether the file appears.
**File appears = the pane is at a shell = NO lane is running there.** If a lane should be
working but its pane reports idle, the command fell into the void — close the pane, create a
new one, send again.

⚠️ The script **excludes the calling session's own pane** (via `cmux identify`). Without that
step it types commands into the user's own input box — which happened once.

Indirect inference (when you cannot run the script):

```bash
find <directories the lane touches> -newermt '-3 minutes' ! -path '*node_modules*' | wc -l
pgrep -fl "npm|yarn|pytest|go test|cargo|tsc |docker build"
```

- **files changed within 3 minutes** ⇒ working, leave it alone
- **0 files changed BUT a long-running process exists** (`docker build`, a dependency install, a test
  suite) ⇒ **it is running its own acceptance, not stalled.** Do not touch it. Seen for real: a
  lane looked frozen for 5 minutes because it was running `docker build` — which was its
  acceptance criterion.
- **0 files changed AND 0 processes** across two consecutive rounds ⇒ genuinely stalled

### 5.2 · When to close a lane

Close it; don't leave it sitting there:

| Situation | What to do |
|---|---|
| Design changed, the old brief aims at the wrong target | `send` a stop instruction → wait for confirmation it hasn't edited files → `close-surface` |
| Its work will be deleted by another lane | close immediately; that's rework, not parallelism |
| Genuinely stalled across two rounds | close, re-brief more clearly — a vague brief is usually the cause |
| Done and committed | close to free the slot; **verify before closing**, once closed the context is gone |

⚠️ **A finished lane left open makes you misread the state.** Four open panes look like four
running lanes; in reality three committed long ago and only one still has work. The user looks
at it and asks *"why is nothing running"* — and they are right, just not in the way you think.
`list-panes` counts **panes**, not **work**.

⚠️ **Before closing any lane: ask whether it has edited files.** Closing a lane holding
uncommitted changes loses that work outright. If it has edited, tell it to **report the file
list, not commit and not revert**, then decide yourself whether to keep or drop it.

⚠️ **Don't let panes accumulate.** Dead panes still appear in a previous session's
`list-panes`; surface refs get renumbered on create/close, so a long list full of stale panes
is the fastest way to send a command into the wrong lane.

### 5.3 · 🔴 Killing a lane mid-flight — its work IS STILL ON DISK

Stopping a lane does **not** undo what it edited. The files are still there and `git status`
still shows them. These are two opposite mistakes, and both have cost real work:

- **Deleting it by accident:** the reflex to "clean up before re-dispatching" with
  `git checkout <file>` — a command that **restores the entire file to HEAD**, sweeping away
  what the lane just wrote. A turn's worth of correct work was lost exactly this way.
- **Forgetting it:** dispatching a new lane without saying anything ⇒ it finds a dirty working
  tree of unknown origin and either cleans it up, starts over, or builds on top of something
  half-finished.

**Procedure when you deliberately stop a lane:**

```bash
git status --short        # capture: which files are in flight
git diff --stat           # capture: how far along
# NO git checkout. NO git stash. Leave it exactly as is.
```

Then **write this at the very top of the new brief**, above even `owns`:

> ⚠️ The working tree **already contains** in-flight work from a previous turn that was stopped
> mid-way (stopped deliberately, not a crash). Run `git diff` and `git status` **first**. Your
> job is to **continue and finish it**, not to start over. Fix whatever is heading the wrong
> way, but **do not `git checkout`** to wipe it.
>
> In flight: `<list every file>`

Without that paragraph, switching tools mid-flight **loses the work** rather than transferring it.

## 6 · Claude teammates

Use `Agent` with `run_in_background: true`. The brief needs:

- **context to read first** — which files in the repo tell it where we are
- **questions as the acceptance criteria**, not "research X". A report that answers no question
  is decoration.
- **a no-invention rule**: every non-obvious claim needs a source; if something cannot be
  verified, **say it cannot be verified**
- **separate "they advertise it" from "verified"**
- safety boundaries: no signing up for accounts, no filling in forms, no entering personal data
- **write the file early and update it incrementally** — a teammate dying mid-run on a network
  error is a real occurrence; without an early write everything is lost

If a teammate dies, **re-spawn it**, don't wait. Verify by the files it produced, not by an idle
notification.

⚠️ **An idle notification without a report means STOPPED, not working.** Its final text is the
only thing that reaches you, and it sent none. Seen for real 2026-08-11: a research teammate
reported `idle · available` twice, including after a direct nudge.

🔴 **But idle is not dead, and "drop it after two idles" is WRONG — that rule cost an entire
research area.** `idleReason: "available"` means the agent ended its turn; the process and its
whole context are still there, and a `SendMessage` resumes it exactly where it stopped. One
more nudge costs one message; dropping costs everything it read and synthesised. The
terminating condition is **a response** — an answer, or the agent saying explicitly that it
cannot answer — never a count of nudges.

**Degrade the ask instead of dropping it**, and change the *shape* of the question, not just
its size: "send what you have, mark gaps as unverified" → hand it what you have since learned
and narrow to the two questions only it can answer → ask for one sentence, a URL, a yes/no.
Cover the area yourself **in parallel**, not instead. Full procedure and the incident that
rewrote this rule: `orchestration-loop` § *Idle is not done*.

**Verify load-bearing claims yourself before acting on them.** In the original session a
teammate proposed a public argument built on a correct finding — but using it would have
backfired. A report is an input, not a decision.

## 7 · The orchestration loop — lanes will not remind you

Lanes run in the background. Without a check rhythm they get **forgotten**: commits sit local
and unpushed, panes die silently, finished work goes unverified and the next step never gets
dispatched.

**The mechanism lives in the `orchestration-loop` skill** — read it before opening
the first lane, not after. In one line: a bounded background command, because the harness
re-invokes you when it exits and nothing else will.

```bash
# Bash(run_in_background: true) — arm it the moment the lane is dispatched
"$ROOT"/skills/cmux-orchestration/lane-watch.sh 440 442 --timeout-min 60
```

It waits on `agentLifecycle: idle` in cmux's own turn-hook session store, compared against a
baseline stamped at arm time, and exits early if a lane's pid dies without ever going idle.
That beats `pgrep -x codex`, whose baseline drifts as other projects open their own lanes.

**Forgot to arm one?** `lane-status.sh --all` (or `/cmux-workflow:lanes`) reconstructs the state of every
lane after the fact — see §5.1. Reach for it first, before re-reading screens.

⚠️ `/loop` is a **user-typed built-in you cannot invoke.** This skill used to say "start /loop the
moment you spawn the first lane", which is not an action available to an agent — so the step
quietly became nothing, and three lanes finished unnoticed *(2026-08-11)*. If the user has started
one, each firing is a round below; otherwise the watcher above is your only mechanism.

**What a round checks that is specific to lanes:**

1. `git status --porcelain` — and specifically, **did anything change outside every lane's `owns`
   list**. A running dev server can rewrite generated files (a tunnel URL, a manifest, a lockfile) on
   its own; those belong to no lane and get swept into a broad `git add`.
2. `cmux read-screen` on each lane, and `cmux list-panes` for ones that died. **A dead pane is a
   lost lane** — with codex, usually with nothing committed, because it cannot commit.
3. **Run the gate yourself** and compare the count to before. Reading the lane's reported count is
   reading its summary of its own work.
4. **Push.** Lane work sits local; a user looking at the remote sees nothing and concludes nobody
   did anything. This is a real failure — five lanes had finished and the user reported *"none of
   them committed anything"* because nothing had been pushed.
5. **Chase idle teammates that never reported.** Idle ≠ still working — see §6.

**Stop the loop** when the goal is reached, or when everything left is waiting on a user
decision. A loop that keeps running with no work is just noise.

## 8 · Sequencing multiple waves

```
wave 1   lanes with disjoint owns          → run in parallel
         (close them all before wave 2)
wave 2   the critical path                 → ONE lane, running alone
wave 3   wide fan-out on the now-stable base
```

After each wave: the orchestrating chat verifies, updates the plan, commits — and only then dispatches the next wave.

## Scripts in this skill

| Script | Answers | Sends keystrokes? |
|---|---|---|
| `lane-status.sh` | **what state is every lane in** — RUNNING/DONE/BLOCKED/DEAD/EMPTY, plus what to verify, commit, close (`/cmux-workflow:lanes`) | no |
| `lane-watch.sh` | **tell me when these lanes finish** — run with `run_in_background: true` | no |
| `lane-health.sh` | **is this pane at a shell** — for a surface with no session-store entry, or a brief you suspect fell into the void | **yes** — §5.1a only |

## Related

- **`cmux-screen-layout`** — where the panes go: splitting vs tabs, the grid rule for 3–4 lanes,
  naming, resizing, and repairing a layout that has become unreadable. **This skill owns *what*
  runs in a pane; that one owns *where the pane is*.** Read it before opening the third lane —
  three `new-split right` in a row produces columns too narrow to read a codex TUI, and a
  misread pane is how a finished lane gets reported as still running.
