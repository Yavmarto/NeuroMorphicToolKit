<agent_instructions>
  <initialization>
    Read `AGENTS.md` first, then `CODING_STYLE_GUIDE.md`. If a top-level module has its own `AGENTS.md`, read that module file before editing files in that module.
  </initialization>
  <end_of_task_reporting>
    Every answer must include a short description of what the problem is (exactly 2 sentences), how it was solved (exactly 2 sentences), and where to notice the difference and restart info (exactly 2 sentences). All in plain English.
  </end_of_task_reporting>
</agent_instructions>
## GBrain Configuration (configured by /setup-gbrain)
- Engine: pglite
- Config file: ~/.gbrain/config.json (mode 0600)
- Setup date: 2026-06-03
- MCP registered: yes (user scope)
- Memory sync: off
- Current repo policy: unset (run `/setup-gbrain --repo` to configure)
- Embedding: deferred — set OPENAI_API_KEY or VOYAGE_API_KEY then run `gbrain embed --stale`

**Always check Open Brain at task start:** `gbrain search "<topic>"` to retrieve relevant context, decisions, and prior workstreams before writing code.
