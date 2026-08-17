---
name: cmux-screen-layout
description: Arrange, name and resize cmux panes and tabs so several agent lanes stay readable at once. Use when opening more than one lane, when panes have become too narrow to read, when tabs are unnamed and you cannot tell which lane is which, or when the user says "the screen is a mess", "I can't read the panes", "optimize the layout", "split better", "rename the tabs". Complements `cmux-orchestration`, which covers dispatching and verifying lanes rather than where they sit on screen.
---

# Laying out cmux so three lanes are still readable

**The failure this prevents:** you run `cmux new-split right` four times, end up with four columns
about 40 characters wide, and every codex TUI wraps into unreadable soup. The lanes work fine. You
cannot see them, and neither can the user, who is watching the same screen.

Everything below was verified against cmux on 2026-08-13; flags are not guessed.

## The one distinction that decides everything

| | Command | Effect | Space per lane |
|---|---|---|---|
| **Pane** | `cmux new-split <left\|right\|up\|down>` | splits the current pane in two | **shrinks** with every lane |
| **Tab** | `cmux new-surface --pane <ref>` | adds a surface **inside** an existing pane | **full pane**, one visible at a time |

A pane is *simultaneous but smaller*. A tab is *full size but one at a time*.

**And here is the point most people miss:** an orchestrating agent reads lanes with
`cmux read-screen`, which works perfectly on a tab that is not currently visible. **Simultaneous
visibility is for the human, not for you.** So the question is never "how do I see all six at
once" — it is "how many does the person actually need to glance at."

## The layout rule, by lane count

| Lanes | Layout | Why |
|---|---|---|
| **1** | one split | nothing to decide |
| **2** | `new-split right` — two columns | both still wide enough for a TUI |
| **3–4** | **grid**: split right, then `new-split down` inside each column | four readable quadrants beats four unreadable columns |
| **5+** | **tabs**: one or two panes, extra lanes as `new-surface --pane` | past four, splitting makes every lane useless; tab them and switch |
| different project | `cmux new-workspace --name "<slug>"` | it has its own name flag, unlike `new-split` |

### Ask the CLI what you actually built

`cmux tree` prints every pane at the same level, so it cannot tell a grid from a row of columns.
**`cmux list-panes --json` can** — it returns a `pixel_frame` (`x`, `y`, `width`, `height`) plus
`columns`/`rows` for every pane. Read the geometry instead of guessing at it:

```bash
cmux list-panes --workspace workspace:N --json | python3 -c '
import json, sys
panes = json.load(sys.stdin)["panes"]
for p in sorted(panes, key=lambda p: (p["pixel_frame"]["x"], p["pixel_frame"]["y"])):
    f = p["pixel_frame"]
    print("%-9s x=%5.0f y=%5.0f %7.1fx%-7.1f %dx%d" % (
        p["ref"], f["x"], f["y"], f["width"], f["height"], p["columns"], p["rows"]))
'
```

Two panes sharing an `x` but differing in `y` are stacked; two sharing a `y` and differing in `x`
are side by side. That is the whole test, and it takes one command.

### The one-call grid: `new-workspace --layout`

A `--layout` child may itself be a `direction`/`children` node instead of a `pane`, and that
nesting is what produces a real grid — no `new-split` sequence, no rename pass, and the geometry
is declared rather than discovered. Layout surfaces carry their own `command` (and per the CLI
contract, their own `env`).

Measured 2026-08-14 on a 1591×1096 pane area, `split: 0.55` horizontal wrapping a nested vertical
pair: lead pane `875.1×1096.0` at `x=240` → **108×59**; the two stacked panes both `715.9×548.0`
at `x=1115`, `y=28` and `y=576` → **88×28** each. A true grid, and every pane twice the ~40-column
width where a codex TUI stops being readable.

⚠️ **Still unverified: `cmux new-split down --surface <s>`.** On 2026-08-13 it added another flat
pane rather than splitting inside that surface's column. That measurement stands and has not been
retaken — but you no longer need a human eye to settle it, because `list-panes --json` above will
tell you in one command. Prefer `--layout` when you know the shape up front.

⚠️ **Never split more than twice in the same direction.** Three `new-split right` in a row gives
three narrow columns; the third is already too tight for codex's box drawing, and you will misread
its state — which is how a finished lane gets reported as running.

## Always name the tab — `new-split` cannot

`new-split` has **no `--name` or `--title` flag**. A fresh split is anonymous and `list-panes`
prints only `pane:281`. Fix it in the same breath:

```bash
cmux new-split right                                     # → OK surface:431 workspace:5
cmux rename-tab --surface surface:431 "A1 auth-refactor"  # → OK action=rename tab=tab:431
```

Then the layout reads itself:

```
--- pane:281 ---   * surface:431  A1 auth-refactor
--- pane:282 ---   * surface:432  A2 rate-limit
```

**Name with the lane ID from the brief** (`A1 auth-refactor`, `A2 rate-limit`), never a description —
the ID is what the plan file, the dispatch string and the commit message all use, and a prettier
name breaks that chain.

⚠️ `rename-tab` takes `--surface` but renames the **tab** that owns it (`tab=tab:431`). There is no
`rename-surface`.

## Fixing a layout that is already a mess

```bash
cmux list-panes                                   # panes only — no names
cmux list-panes --json                            # + pixel_frame and columns/rows per pane
cmux list-pane-surfaces --pane pane:N             # surfaces AND their names, per pane
cmux resize-pane --pane pane:N -R --amount 20     # tmux-compatible: -L -R -U -D
cmux swap-pane / join-pane / break-pane / split-off
cmux move-surface / reorder-surface               # move a tab between panes
cmux close-surface --surface surface:N            # closes one tab, not the pane
```

Recovery order, cheapest first:

1. **Name everything** — often the whole problem was not knowing which pane was which
2. **Resize** the pane you are actually reading, rather than rebuilding the layout
3. **`join-pane`** the narrow ones back together and re-add lanes as tabs
4. Rebuild only if the above fails — and remember that closing a pane holding a live lane **kills
   the agent mid-task**. Its file edits are safe on disk; everything it had worked out is not (see
   `cmux-orchestration` §5.2/§5.3)

## Before you close anything

⚠️ **Surface refs are renumbered on every create/close.** Re-fetch with `list-pane-surfaces`
immediately before closing; never close by a number you read a few minutes ago. Names survive
renumbering, which is the second reason to set them.

⚠️ **Check the pane is not running a lane.** `cmux read-screen --surface surface:N --lines 10` —
if it shows `Working (` or `Waiting for background`, the lane is alive. Closing it kills the agent
mid-task; its file edits remain on disk but its reasoning does not.

## A worked example — four lanes, readable

```bash
# two columns
cmux new-split right                                    # → surface:A
cmux rename-tab --surface surface:A "W0-A classification"
cmux new-split right                                    # → surface:B
cmux rename-tab --surface surface:B "B7 cache-layer"

# split each column downward instead of adding a third column
cmux new-split down --surface surface:A                 # → surface:C
cmux rename-tab --surface surface:C "W0-C facts"
cmux new-split down --surface surface:B                 # → surface:D
cmux rename-tab --surface surface:D "W0-D onboarding"

# confirm the map before dispatching anything
for p in $(cmux list-panes | grep -oE 'pane:[0-9]+'); do
  cmux list-pane-surfaces --pane "$p"
done
```

Four quadrants, each named, each wide enough to read. Compare with four `new-split right`, which
gives four columns nobody can use.

## Related

- `cmux-orchestration` — choosing the tool, writing the brief, the five dispatch steps, verifying
  results, the orchestration loop. **That skill owns *what* runs in a pane; this one owns *where
  the pane is*.**
