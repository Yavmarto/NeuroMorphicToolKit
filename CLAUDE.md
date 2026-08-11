<agent_instructions>
  <initialization>
    Read `AGENTS.md` first, then `CODING_STYLE_GUIDE.md`. If a top-level module has its own `AGENTS.md`, read that module file before editing files in that module.
  </initialization>
  <cleanup>
    Always clean up after yourself. Delete any temporary scripts, patch files, or intermediate files created during execution to keep the repository clean.
  </cleanup>
  <task_management>
    Always check the `current tasks` directory at the repository root for ongoing or dated task histories. When creating or saving new tasks, always save them inside `current tasks/` under a subfolder named with the current date.
  </task_management>
  <communication>
    Plain English, short. Target under 150 words for a normal task; the work can be deep, the write-up is not. Lead with the answer — first sentence says what was wrong or what changed, with no preamble and no restating the request. Describe the user-visible effect rather than the internal mechanism unless asked, and whenever you name a symbol, file, or error code, gloss it in ordinary words in the same sentence. One clickable link per changed file, not a tour of every hunk. Shell commands go in a fenced `bash` block, one per block.

    Cut: "Great question" / "You're absolutely right" / "Let me explain", summaries of what you are about to say, lists of files you read or searches you ran, options you rejected, anything already established earlier in the conversation, and narration of your own corrections — fix it and move on. Do not use a table or nested bullets where two sentences would do.

    Report failures plainly: if tests fail, say so and show the output; if you skipped part of the scope, name the part and why. Never imply green when it is not. See root `AGENTS.md`, "Talking to the User", for worked examples.
  </communication>
  <end_of_task_reporting>
    Close every answer with what the problem was (exactly 2 sentences), how it was solved (exactly 2 sentences), and where to notice the difference plus restart info (exactly 2 sentences). All in plain English. This is a summary, not a second copy of the explanation above it — do not repeat sentences verbatim.
  </end_of_task_reporting>
  <deployment>
    User's standard command to run/test the app: `flutter run -d macos`, run from `nmtk/neuro_toolkit`. The dev backend at `moosebun2@192.168.68.53` is already running — this does not deploy or rebuild anything, it just launches the Flutter macOS app locally. `make docker-ex-m` / `scripts/run_dev.sh` are deprecated — do not suggest or use them (see root `AGENTS.md`, "Updating the backend"). Since plain `flutter run` passes no `--dart-define` pointing at the remote host, the app boots against its hardcoded `127.0.0.1` default and lands on `/setup` with no backend found — use the "Already have a server running?" field on that screen (`backend_setup.dart`) to connect directly to `192.168.68.53`.
  </deployment>
  <end_user_paths>
    End users operate the app only — they never open a terminal. Never present SSH, `make`, `docker`, a shell script, or systemd as an end-user instruction, including for installing or updating the backend: the app owns that (Backend Setup deploys it; an "Update backend" banner appears when a release is newer). Terminal commands in `AGENTS.md` under "Developer paths" are for pushing unreleased source to a dev host — developer-only. If an in-app path is missing for something a user needs, propose building it in the app rather than handing over a command.
  </end_user_paths>
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
