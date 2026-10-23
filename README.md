# cmux-workflow — retired

This repository is archived.

Avada now uses **Orca** as the canonical runtime for durable handoffs and
supervised multi-agent delivery. The useful workflow contract has moved into:

- [`avada-orca-workflow`](https://github.com/thomasavada/avada-stack/tree/main/plugins/avada-stack/skills/avada-orca-workflow)
- [`multi-session-program`](https://github.com/thomasavada/avada-stack/blob/main/plugins/avada-stack/skills/avada-mode/references/playbooks/multi-session-program.md)
- [`docs/integrations.md`](https://github.com/thomasavada/avada-stack/blob/main/docs/integrations.md)

Install the replacement:

```text
/plugin marketplace add https://github.com/thomasavada/avada-stack.git
/plugin install avada-stack@avada
```

The migration preserves the parts that mattered:

- durable briefs;
- explicit write ownership;
- positive completion proof;
- independent verification;
- cleanup accounting.

It deliberately does **not** carry forward:

- cmux pane layout;
- cmux session-store watchers;
- the custom Orca screen-scraping watcher;
- demos and compact-survival hooks tied to the retired plugin.

Orca now provides structured Runs, Tasks, Dispatches, inbox/reply, settlement,
and cleanup. Avada Stack supplies task shape, business/product boundaries,
evidence contracts, and verdicts. CLI details are loaded from the running Orca
binary so they stay version-matched.

The old implementation remains in Git history for incident archaeology. Do not
install it for new Avada work.
