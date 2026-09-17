# User Guide: Sharing Studio Workspaces with Neurohub

Neurohub lets you save, version, and share your NeuroStudio workspaces on
**GitHub**. Each shared workspace is a private GitHub repository by default;
every save creates one commit, sharing adds collaborators, and publishing
makes the repository visible.

You do everything from inside the NeuroStudio app — no terminal, no GitHub
URLs, no tokens to paste (other than a one-time sign-in code).

## 1. Connect your GitHub account

1. In the Studio toolbar, open **Save to Neurohub** (cloud upload icon), or
   open the **Profile** button in the launcher header.
2. Neurohub shows a sign-in dialog with a short **device code** and a link to
   `github.com/login/device`.
3. Open the link, sign in to GitHub, and enter the code. GitHub asks for the
   permissions Neurohub needs to manage your workspace repositories.
4. Back in the app, sign-in completes automatically. Your account stays
   connected for future sessions — you will not need to repeat this step on
   every launch.

If your saved sign-in ever expires, the app notices and asks you to sign in
again.

## 2. Save (commit) the current workspace

1. In the Studio toolbar, tap **Save to Neurohub** (the cloud upload icon).
2. If this is the first time for the workspace, Neurohub asks for a
   **workspace name**, an optional description and tags, and whether to
   **publish** it. Workspaces start **private**; publishing makes them
   discoverable in Explore.
3. Neurohub creates the workspace repository and stores your current canvas
   and CNL project state in it — one atomic revision.

On later saves the workspace updates in place. Every save is one commit, so
you always have a history of your work.

## 3. If someone else changed the workspace

When another collaborator saved a newer revision while you were editing,
Neurohub detects that your copy is out of date and opens a conflict dialog:
**"This workspace changed elsewhere."** Your local work is still safe in
Studio — nothing is overwritten silently.

You choose what happens next:

- **Reload saved version** — discard your local edits and load the newest
  saved revision from GitHub.
- **Compare changes** — preview your Studio workspace next to the latest
  saved version, side by side, then decide.
- **Save as new workspace** — keep your work as a separate private workspace
  without touching the shared one.
- **Keep editing** — do nothing for now and continue working locally.

## 4. Browse, open, and share workspaces

- The launcher **Profile** button and the **Share** surface list the workspaces
  you can access: your own and ones shared with you.
- Select a workspace to preview its model, train, and evaluate stages.
- Workspaces you can edit show a save action; read-only workspaces can be
  previewed and forked as a copy, but not modified.
- **Open on GitHub** jumps to the repository so you can inspect history,
  issues, and collaborators there.

## 5. Managing access

Workspace owners control who can read or save:

- **Private** workspaces are visible only to you and the collaborators you
  add.
- **Published** workspaces appear in Explore so anyone can discover and fork
  them.
- Collaborators you add can save changes; read-only viewers can only preview
  and fork.

## Troubleshooting

- **"Sign in to Neurohub" fails** — the GitHub sign-in code may have expired;
  tap **New code** in the dialog to request another.
- **A save is rejected as too large** — Neurohub keeps workspaces under 10 MB
  in Git storage. Remove unused datasets or exports, then save again.
- **"Neurohub is unavailable"** — your work stays saved locally in Studio.
  Retry in a moment; nothing you did is lost.
- **The Share surface says Neurohub is not configured** — the account owner
  must register a GitHub OAuth App once and set its Client ID in the
  Neurohub backend environment (`GITHUB_OAUTH_CLIENT_ID`). Device flow needs
  no client secret and no callback URL. Ask the person who owns the GitHub
  organization.
