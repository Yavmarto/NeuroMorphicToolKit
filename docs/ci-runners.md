# CI/CD runners and the release pipeline

Developer-only document. End users never touch any of this — they download an
installer from the repository's Releases page, and the app handles the backend
itself.

## How a runner is chosen

Two mechanisms:

**Release jobs** (`release-desktop.yml`, `release-docker.yml`,
`release-promote.yml`) resolve their runner from a repository variable with a
GitHub-hosted fallback, so a release works with no hardware at all:

| Variable | Used by | Fallback |
| --- | --- | --- |
| `RELEASE_RUNNER_LINUX` | version resolution, Linux AppImage, Python wheels, release creation, Akida manifest gate, dev→main promotion | `ubuntu-latest` |
| `RELEASE_RUNNER_WINDOWS` | Windows installer | `windows-latest` |
| `RELEASE_RUNNER_MACOS` | macOS DMG | `macos-14` |
| `RELEASE_RUNNER_DOCKER` | the 15 GHCR images | `ubuntu-latest` |

Unset means the hosted runner. Set one to a self-hosted runner's label to move
that build in-house:

```bash
gh variable set RELEASE_RUNNER_WINDOWS --body nmtk-win
```

Only a *single* label is supported, because `runs-on` cannot expand a variable
into a label array. Give each self-hosted runner one unique label
(`nmtk-mac`, `nmtk-win`, `nmtk-linux`) rather than relying on the
`[self-hosted, Windows, X64]` combination.

**CI jobs** (`ci.yml`, `nmtk-ci.yml`) pin self-hosted labels with no variable
fallback, because they need the real target OS and toolchains. These are the
label groups the fleet must provide:

| Label group | Used by |
| --- | --- |
| `nmtk-linux` | `nmtk-ci.yml` `test`, `build-linux` |
| `nmtk-mac` | `nmtk-ci.yml` `build-macos`, `integration-test-apple` |
| `[self-hosted, Linux, X64]` | `ci.yml` Linux jobs (the same WSL2 runner) |
| `[self-hosted, macOS, ARM64]` | `ci.yml` macOS jobs (the same Mac) |
| `[self-hosted, Windows, X64]` | `ci.yml` Windows jobs |

A runner registered without `nmtk-linux` or `nmtk-mac` never picks up the
`nmtk-ci.yml` jobs, even if it is otherwise a Linux or macOS runner. The
scheduled health check below watches both label styles.

`runner.environment` is used inside jobs where hosted and self-hosted need to
differ — the disk-reclaim step in `release-docker.yml`, for example, only runs
on hosted machines.

## Cost note

The repository is private, so hosted minutes are billed, and macOS bills at
10× the Linux rate. A full tagged release is roughly four short jobs plus 15
Docker builds. Moving Docker and macOS in-house is where the savings are; Linux
and the Windows installer are cheap enough to leave hosted.

## Waking a sleeping runner on demand

Yes, this works, and it is the right setup for a desktop PC you do not want
running 24/7. Three pieces:

1. **Something always-on sends the wake packet.** A Wake-on-LAN magic packet is
   a LAN broadcast — GitHub cannot send one into your network, so a machine on
   the same subnet has to poll for queued work and wake the runner. The dev
   backend box is already always-on and is the natural host.
   [`scripts/ci/runner-wake.sh`](../scripts/ci/runner-wake.sh) does the polling.
2. **The runner suspends itself when done.**
   [`scripts/ci/runner-idle-suspend.sh`](../scripts/ci/runner-idle-suspend.sh)
   runs on the runner host and sleeps it after a configurable idle period,
   holding off while a job is executing or still queued.
3. **The queue tolerates the delay.** GitHub holds a job waiting for a matching
   self-hosted runner for up to 24 hours, and wake-to-claiming-work is well
   under a minute, so nothing is lost by being asleep.

### Setup on the always-on box

```bash
sudo install -Dm755 scripts/ci/runner-wake.sh /opt/nmtk/scripts/ci/runner-wake.sh
sudo install -Dm644 scripts/ci/systemd/nmtk-runner-wake.service /etc/systemd/system/nmtk-runner-wake.service
sudo useradd --system --home /opt/nmtk --shell /usr/sbin/nologin nmtk-ci
```

Then write `/etc/nmtk-runner-wake.conf` (`chmod 600`, owned by `nmtk-ci` — it
holds a token):

```bash
GITHUB_REPO="Completed-Spoon-6/NeuroMorphicToolKit"
GITHUB_TOKEN="github_pat_..."       # fine-grained, Actions: read-only
RUNNER_MAC="a4:bb:6d:11:22:33"      # wired NIC of the sleeping PC
RUNNER_HOST="192.168.2.91"          # to test whether it is already awake
WAKE_LABELS="nmtk-win,nmtk-linux"
BROADCAST="192.168.2.255"           # subnet broadcast beats 255.255.255.255
```

```bash
sudo systemctl enable --now nmtk-runner-wake
```

Verify without waiting for a real release by queueing a job and running
`sudo -u nmtk-ci /opt/nmtk/scripts/ci/runner-wake.sh --once`.

### Setup on the Windows + WSL2 box

The runner itself lives in the Ubuntu WSL2 distro; only the sleep call reaches
out to Windows.

1. **BIOS/UEFI**: enable Wake on LAN / "Power on by PCIe" and turn off ErP or
   Deep Sleep, which cut power to the NIC.
2. **Windows NIC**: Device Manager → the adapter → Power Management → check
   *Allow this device to wake the computer* and *Only allow a magic packet to
   wake the computer*. Advanced tab → enable "Wake on Magic Packet".
3. **Use wired Ethernet.** Wi-Fi wake (WoWLAN) is unreliable on desktop NICs and
   is the usual reason this setup appears not to work.
4. **Turn off Fast Startup** (Control Panel → Power Options → Choose what the
   power buttons do). With it on, a shutdown leaves a hybrid state that many
   NICs will not wake from. Sleep (S3) is the target state; it is also the state
   WSL2 survives, keeping the runner registered and ready.
5. **Runner as a service**, so no login is needed after wake:

   ```bash
   cd ~/actions-runner
   ./config.sh --url https://github.com/Completed-Spoon-6/NeuroMorphicToolKit --labels nmtk-linux
   sudo ./svc.sh install && sudo ./svc.sh start
   ```

   This needs systemd inside WSL: `/etc/wsl.conf` must contain

   ```ini
   [boot]
   systemd=true
   ```

6. **Start WSL at Windows boot.** WSL2 does not auto-start. Create a Task
   Scheduler task, trigger *At system startup*, running
   `C:\Windows\System32\wsl.exe -d Ubuntu -- /bin/true`, with *Run whether user
   is logged on or not*. This covers reboots and hibernation; plain sleep/wake
   keeps the distro running and needs nothing.
7. **Idle suspend**, inside the distro:

   ```bash
   sudo install -Dm755 scripts/ci/runner-idle-suspend.sh /opt/nmtk/scripts/ci/runner-idle-suspend.sh
   sudo install -Dm644 scripts/ci/systemd/nmtk-runner-idle-suspend.service /etc/systemd/system/nmtk-runner-idle-suspend.service
   sudo systemctl enable --now nmtk-runner-idle-suspend
   ```

   It reads the same config file; `IDLE_MINUTES` (default 10) is the grace
   period. Dry-run it first: `sudo /opt/nmtk/scripts/ci/runner-idle-suspend.sh --once --dry-run`.

### Known limits

- A laptop using Modern Standby (S0ix) instead of S3 will not wake from a magic
  packet reliably. Desktops on S3 are fine.
- Windows can be configured to disallow wake from hibernate (S4) or soft-off
  (S5). Sleep is what this design assumes.
- Docker builds on this box need Docker reachable *inside* WSL
  (Docker Desktop's WSL integration, or a native `docker` install in the
  distro). Without it, leave `RELEASE_RUNNER_DOCKER` unset.

## Runner health monitoring

The runners have no automatic fallback, so something has to notice when one
disappears. `.github/workflows/runner-health.yml` runs every 30 minutes on a
**GitHub-hosted** runner (`ubuntu-latest`) — deliberately, because it is the
check that must keep working when every self-hosted runner is down.

It raises these alerts:

| Alert | Meaning |
| --- | --- |
| `CIRunnerMissing` | No runner is registered with a required label group at all. That workflow can never start. |
| `CIRunnerOffline` | Every runner in a group that must stay online is offline. |
| `CIJobStuckQueued` | A job has waited longer than `QUEUED_THRESHOLD_MINUTES` (default 30) for a matching runner. |

Being offline is normal for the Wake-on-LAN runners, so the check only notes it
for `nmtk-linux`, `[self-hosted, Linux, X64]` and `[self-hosted, Windows, X64]`;
a stuck queued job is what raises the alert for those. The always-on Mac
(`nmtk-mac`, `[self-hosted, macOS, ARM64]`) alerts as soon as it is offline.

Alerts are delivered to two places:

1. **Alertmanager** when the `ALERTMANAGER_URL` repository secret is set. The
   check posts to `<ALERTMANAGER_URL>/api/v2/alerts`. This is the hook into the
   monitoring stack (CEL-310/CEL-312). Until that stack runs and the secret is
   set, delivery falls back to the tracking issue.
2. **A tracking issue** titled `[monitor] CI runner health`, always. The check
   opens it on the first alert, comments only when the alert set changes, and
   closes it when the fleet is healthy again.

`RUNNER_ADMIN_TOKEN` is a fine-grained token with **Administration: read**. The
workflow's automatic `GITHUB_TOKEN` cannot list runners, so the offline check is
skipped (with a note) until the secret exists; the stuck-queue check works
without it.

The same workflow runs `scripts/ci/validate_workflows.py`, which fails on a
workflow file that cannot be parsed or that references a job which does not
exist. `ci.yml` also wires that check into `ci-passed` as `validate-workflows`,
so an invalid workflow fails the branch gate instead of silently never running.
The scheduled copy exists because a broken `ci.yml` cannot lint itself.

Test the check with no writes:

```bash
GITHUB_REPOSITORY=Completed-Spoon-6/NeuroMorphicToolKit \
GITHUB_TOKEN=... RUNNER_ADMIN_TOKEN=... \
python3 scripts/ci/runner_health_check.py --dry-run
```

## When a required runner is down

1. **Get the blast radius.** `CIJobStuckQueued` names the labels and the job.
   A stuck `nmtk-linux` job blocks `nmtk-ci.yml`; a stuck
   `[self-hosted, Linux, X64]` job blocks the whole `ci.yml` gate.
2. **Look at the fleet.** Needs a token with Administration: read.

   ```bash
   gh api repos/Completed-Spoon-6/NeuroMorphicToolKit/actions/runners \
     --jq '.runners[] | "\(.name)\t\(.status)\t\(.busy)\t\([.labels[].name] | join(","))"'
   gh run list --status queued --limit 20
   ```

3. **If the box is only asleep** (the Wake-on-LAN runners), check the wake
   service on the always-on box and poll once by hand:

   ```bash
   systemctl status nmtk-runner-wake
   sudo -u nmtk-ci /opt/nmtk/scripts/ci/runner-wake.sh --once
   ```

4. **If the runner host is dead, pick a failover in this order:**
   - Wake or reboot the host and wait for the runner to re-register.
   - Re-point a spare machine's labels to the missing one, then restart the
     runner service. The GitHub UI shows the remove token; `--labels` replaces
     the label set.

     ```bash
     cd ~/actions-runner
     ./config.sh remove --token <remove-token>
     ./config.sh --url https://github.com/Completed-Spoon-6/NeuroMorphicToolKit --labels nmtk-linux
     sudo ./svc.sh stop && sudo ./svc.sh start
     ```

   - For **release jobs only**, delete the variable so the job falls back to the
     GitHub-hosted runner. CI jobs (`ci.yml`, `nmtk-ci.yml`) have no fallback.

     ```bash
     gh variable delete RELEASE_RUNNER_MACOS
     ```

   - Run the blocking build on your own machine while the runner is down:

     ```bash
     cd nmtk/neuro_toolkit && flutter build macos --no-tree-shake-icons
     ```

5. **Recover.** Re-run the stuck run, confirm the runner is online, and confirm
   the monitor closes its tracking issue.

   ```bash
   gh run rerun <run-id> --failed
   python3 scripts/ci/runner_health_check.py --dry-run
   ```

6. **Record the incident** in the date folder under `current tasks/`, and add
   the cause to the Known limits above if it is likely to repeat.


## What still needs a decision

- **Android**: `nmtk/neuro_toolkit/android` exists but nothing builds it. An APK
  or AAB on the release needs an upload keystore in secrets
  (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`)
  and Gradle signing config. Not wired up.
- **iOS**: GitHub Releases cannot distribute an installable signed iOS build.
  The realistic target is TestFlight, which needs an App Store Connect API key.
  Not wired up.
- **Web**: 13 files under `nmtk/neuro_toolkit/lib` import `dart:io`, so
  `flutter build web` cannot compile the launcher as it stands. Not a CI gap.
- **`.deb`/`.rpm`**: only an AppImage is produced for Linux.

## Required secrets

| Secret | Needed for |
| --- | --- |
| `NMTK_SUBMODULE_TOKEN` | every checkout — `GITHUB_TOKEN` cannot read the six private submodules. Needs *write* for `release-promote.yml`, which pushes submodule branches and tags. |
| `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY` | signing the DMG |
| `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` | notarizing the DMG |
| `WINDOWS_CERTIFICATE_P12`, `WINDOWS_CERTIFICATE_PASSWORD`, `WINDOWS_SIGNING_THUMBPRINT` | signing the installer |
| `RUNNER_ADMIN_TOKEN` | the runner-health offline check — fine-grained, Administration: read. Optional; the check runs without it. |
| `ALERTMANAGER_URL` | alert delivery to the monitoring stack — base URL, no `/api/v2/alerts` suffix. Optional until CEL-312 lands a receiver. |

Unsigned builds still release; macOS and Windows will warn the user on first
launch. Check what is configured with `gh secret list`.
