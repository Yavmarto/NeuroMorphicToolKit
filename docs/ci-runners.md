# CI/CD runners and the release pipeline

Developer-only document. End users never touch any of this — they download an
installer from the repository's Releases page, and the app handles the backend
itself.

## How a runner is chosen

No workflow hardcodes `self-hosted` any more. Every release job resolves its
runner from a repository variable with a GitHub-hosted fallback:

| Variable | Used by | Fallback |
| --- | --- | --- |
| `RELEASE_RUNNER_LINUX` | version resolution, Linux AppImage, Python wheels, release creation, Akida manifest gate, dev→main promotion | `ubuntu-latest` |
| `RELEASE_RUNNER_WINDOWS` | Windows installer | `windows-latest` |
| `RELEASE_RUNNER_MACOS` | macOS DMG | `macos-14` |
| `RELEASE_RUNNER_DOCKER` | the 15 GHCR images | `ubuntu-latest` |

Unset means the hosted runner, so a release works with no hardware at all. Set
one to a self-hosted runner's label to move that build in-house:

```bash
gh variable set RELEASE_RUNNER_WINDOWS --body nmtk-win
```

Only a *single* label is supported, because `runs-on` cannot expand a variable
into a label array. Give each self-hosted runner one unique label
(`nmtk-mac`, `nmtk-win`, `nmtk-linux`) rather than relying on the
`[self-hosted, Windows, X64]` combination.

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

Unsigned builds still release; macOS and Windows will warn the user on first
launch. Check what is configured with `gh secret list`.
