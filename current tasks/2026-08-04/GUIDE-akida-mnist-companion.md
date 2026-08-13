# Guide: full-MNIST PyTorch → ONNX → Akida 2.0 in CNL Studio

> **This is not the CNL Studio canvas walkthrough.** It runs a prebuilt companion notebook that
> trains its own CNN and bundles it for the card; it never touches the Model, Training or Eval
> canvases, the CNL spec, or Studio's training history. Read it as a hardware-bundle demo.
>
> If you want to build and train a network on the canvases yourself, that is
> [GUIDE-mnist-fcn-studio.md](../2026-07-28/GUIDE-mnist-fcn-studio.md).
>
> **For the PYNQ-Z2 FPGA, see [GUIDE-pynq-z2-hardware.md](../2026-08-13/GUIDE-pynq-z2-hardware.md).**
> The device flow is deliberately the same shape as this one — pair a remote device over SSH, let the
> app install its runtime, deploy, run — so that guide points here for the parts that are identical.
> Two differences matter: PYNQ's fixed overlay caps a network at 256 neurons across two populations,
> and it has no bundle, so trained weights do not reach the board yet (its §0).
>
> **The two paths now meet.** As of 2026-08-06 an **Akida Exporter** node converts a canvas-trained
> model to a real `akida.Model` and writes the same kind of `*.akida-bundle.zip` this demo produces,
> so **Use Latest Bundle** in §4 below deploys either one to the same card. What differs is only
> what is inside the bundle: this demo ships ONNX for the host to quantize, the canvas path ships an
> already-converted model. See §10 of the canvas guide.

Last verified against the app on **5 August 2026**. Every button name below is a label that
exists on screen; every claim about what gates a control was read out of the code.

This follows BrainChip's
[documented PyTorch MNIST workflow](https://doc.brainchipinc.com/examples/general/plot_7_global_pytorch_workflow.html):
train a conventional CNN in Studio's embedded Jupyter environment, export ONNX, then convert and
run it on a physical Akida card.

## Before you start

**Do I need to create a `neurochip` user on the Akida host? No.** The app creates it. When the
runtime is installed, the provisioning script checks `id -u neurochip` and runs
`useradd --system --create-home --shell /usr/sbin/nologin neurochip` if it is missing, chowns the
install root to it, builds the virtualenv as it, and installs two systemd units that run as it.
The account is a *service* account and is unrelated to the SSH login you type into the app — you
never log in as `neurochip`.

The one thing that must be true: **the SSH login you enter has to be able to sudo** — either
passwordless, or with the password you give the app. That is the only host-side prerequisite.

If it cannot sudo, provisioning does not fail. It silently falls back to a **user-space install**:
no `neurochip` account, no systemd, the runtime installed under the SSH user's
`~/.local/share/neurochip-akida-host` and running as that user. That host still works for
diagnosis but **can never earn the Hardware verified badge**, and the app will tell you so with
"Runtime is installed in user space. Enable passwordless sudo for '<user>', then re-run Provision
Runtime…". If you see that message, fix sudo on the host and install again.

Nothing else needs preparing by hand. You do not open a terminal at any point in this guide.

**One caveat for a host that already runs Neurochip.** If a `neurochip` service was installed on the
host outside this app, the app does not know the API token that service was configured with, and
reads from it will be rejected until the app installs the runtime once itself (**Install** in the
Akida Runtime panel). The app tries to recover the token over SSH first, so this only bites when the
token is not where the app's own installs put it.

## What this demo proves

| Chain | Where training runs | Interchange | Where inference runs | Status |
|---|---|---|---|---|
| CNL → snnTorch → trained NIR → Sinabs | backend/Jupyter | trained NIR | Sinabs | approximate inference/codegen |
| PyTorch → ONNX → QuantizeML → Akida | backend/Jupyter | `AkidaModelBundleV1` | selected Akida card | hardware verified only when `runtime_target=hardware` |

Akida is not trained on-card in this workflow. The card runs the converted CNN; Akida edge learning
is separate future work.

## 0. Update the backend and the selected Akida runtime

Open **Backend Setup** in the NMTK app. If **Backend update available** appears, choose **Update
backend** once. Workspaces, notebooks, converted models, credentials, and backend volumes are
preserved; the currently selected Akida runtime is updated afterwards, automatically.

An Akida-only failure finishes as an optional-capability warning, not a failed backend deployment —
core services stay ready.

**When does "Retry Akida update" appear?** It is not always on screen. It shows up when any of
these is true for the selected Akida host:

- a newer runtime version is available for it;
- its last runtime-update job failed;
- it is in a degraded state — *Degraded*, *Degraded Optional Capability*, *Simulator Only*,
  *Preflight Failed*, *Provision Failed*, *Blocked*, or *Error*;
- a backend deployment finished with an Akida optional-capability warning.

In the degraded case the banner reads **"Selected Akida runtime needs attention — <state>"** and
prints the host's own reason underneath, so you can tell "no card enumerated" from "SDK components
missing" before pressing anything. Retrying only touches that host: no image pull, no container
recreation.

If no Akida host is paired yet, the backend update skips this phase entirely. Pair one in the next
section, then use **Install** in the Akida Runtime panel.

## 1. Pair the host in Studio Setup

1. Open **CNL Studio** and go to **Setup**.
2. Under **Target platform**, add **Akida**.
3. Choose **Manage Targets**, then add or edit the Akida host.
4. Enter a display name, the host address, and the host's SSH login name. Choose the saved password
   or SSH-key authentication for that login. (This is the login that needs sudo — see above.)
5. Leave **Advanced settings** collapsed unless the host deliberately uses a nonstandard contract.
   Studio derives the native runtime URL on port 8002 and the Akida remote-control URL on port
   8091; the target service account defaults to `neurochip`.
6. Choose **Save and test connection**. This saves the host, then logs in over SSH and reports back —
   it works before the runtime is installed and needs no token, so it is the fastest way to confirm
   the address, login, and credential are right. A saved host can be re-tested any time from the
   test button on its row in **Manage Targets**.

You never enter an API key anywhere in this flow. The runtime does use one, but the app generates it,
stores it, and re-reads it from the host when needed. If you ever see a message about an API token,
it means the app could not read back its own — see **In-app recovery** below.

If you leave the password field showing `********`, the saved password is kept untouched. Clearing
the field deliberately removes the stored password.

Target discovery and storage go through the suite launcher-control service on port 8090. A pairing
error says whether launcher control, SSH access, or the Akida host needs attention rather than
showing a raw client exception.

### Reading the status dot next to "Akida"

The small dot beside **Akida** in the Target platform list reports **the paired remote host**, via
launcher control. Hover it — the tooltip names the host, its state, and the reason.

| Dot | Meaning |
|---|---|
| Green | *Ready*. The host has a physical card and a deployable SDK. |
| Amber | *Degraded*, *Degraded Optional Capability*, or *Simulator Only*. The host answers, but cannot be hardware-verified. The tooltip says why. |
| Red | *Blocked*, *Preflight Failed*, *Provision Failed*, or *Error* — or launcher control itself is unreachable. |
| Blue | An install, bootstrap, or SDK verification is in progress. |
| Grey | No host paired yet, or the state is not yet known. Hovering says which. |

Two things worth knowing. First, this dot used to probe the *backend container* for a local Akida
SDK and a local PCIe card, which is not where your card is — so it read red for a perfectly healthy
remote host. That is fixed; it now reads the same source the Akida Runtime panel uses. Second, the
dots for the other targets (the simulators, SC-NeuroCore, Lava) still describe the backend
container, correctly, and now show the backend's own words on hover.

## 2. Open the Akida Runtime panel

Go to **Results** → **Deploy to Hardware** → select **Akida** in the target selector. The section
titled **Akida Runtime** is the deployment surface. It is deliberately not a separate page in
Backend Setup or a standalone Neurochip frontend.

**You do not need a training run to get here.** On a fresh workspace the Results step shows "No
training results yet." with two buttons: **Deploy to Hardware** and **Go to Training**. Take
**Deploy to Hardware**. Training curves need a run; hardware deployment does not — the Akida bundle
path reads a notebook-produced file and never touches the CNL canvas, spec, or training history.

Choose **Check Readiness**. If software is missing or stale, choose **Install**; this runs the same
asynchronous, checksum-deduplicated updater Backend Setup uses, and shows validation, packaging,
upload, install, restart, and verification progress in the panel.

Readiness is **not** polled. The panel only refreshes it when you press **Check Readiness**, so a
stale-looking status usually just means nothing has asked recently.

When something is wrong, the panel now names it rather than summarising it: the host's readiness
reason ("Why"), the SDK issue detail, the per-component verdicts for host, Python, TensorFlow,
`cnn2snn`, and `akida_models`, and the full list of SDK issues. A missing `cnn2snn` and an unplugged
card no longer look the same.

Software-update success and card readiness are separate concerns. A healthy, fully updated service
can still report that the card is absent, and that state cannot receive a hardware-verification
badge.

### The panel's two workflows

The panel hosts two unrelated workflows targeting the same host, under separate headings.

**Host and trained-model bundle** — this guide's path:

| Control | What it does | Disabled when |
|---|---|---|
| **Check Readiness** | Re-runs host preflight | a job is running |
| **Install** | Installs/updates the Neurochip runtime on the host | no host selected |
| **Create MNIST Demo** | Generates the companion notebook and opens it | a job is running (no host needed) |
| **Use Latest Bundle** | Finds the newest compatible bundle in the workspace and submits it | no host selected |
| **Choose Bundle** | Pick a `.zip` bundle by hand | no host selected |
| **Sample index** | Which test-set sample to run | appears only once a model job exists |
| **Run Model Sample** | Runs one sample on the card | until the model job is **hardware verified** |

**CNL spec export** — maps the canvas spec straight onto the host. **Map Runtime**, **Generate
Package**, **Run Inference**, plus the **Akida Version**, **Weight quantization**, and **Run input
vector** controls. Not used by this guide; ignore this group for the MNIST demo.

The single most common "is it broken?" moment is **Run Model Sample** staying greyed out. It is
gated on hardware verification, so a simulator conversion — however successful — leaves it
disabled. That is by design.

## 3. Create and train the companion

Choose **Create MNIST Demo**. Studio opens an embedded notebook containing the documented CNN
shape, full MNIST, ten epochs at batch size 128, Adam at `1e-4`, PyTorch evaluation, ONNX export,
and ONNX Runtime parity evaluation.

Run all cells. The notebook asserts its own acceptance criteria: PyTorch accuracy at least 98%, and
ONNX accuracy within 0.1 percentage point of it. It then writes
`akida_mnist_v1.akida-bundle.zip` into the workspace. No address, API key, filesystem path, or
service command is needed.

## 4. Convert and verify on the card

Return to **Results → Deploy to Hardware → Akida → Akida Runtime** and choose **Use Latest
Bundle**. Studio picks the newest compatible bundle automatically; **Choose Bundle** remains as a
fallback.

Progress advances through validation, quantization, conversion, mapping, and evaluation. The host
validates the versioned manifest, safe archive paths, size, SHA-256 checksums, array shapes, and
dtypes before QuantizeML sees the model, persists `model.fbz`, and maps it to a physical Akida
device.

Completion receives **Hardware verified** only when all four of these hold:

- PyTorch accuracy is at least 98%;
- ONNX differs by at most 0.1 percentage point;
- Akida accuracy is at least 96%; and
- the runtime reports `hardware`.

A simulator conversion stays useful for diagnosis but never receives the badge.

## 5. Run a physical sample

Enter a test-set **Sample index** and choose **Run Model Sample**. Studio displays the prediction,
expected label, output values, runtime target, physical-device state, and telemetry. The action
stays disabled until the model job has a physical-hardware verification result.

## Bundle contract

`AkidaModelBundleV1` contains a versioned manifest, `model.onnx`, 128 normalized float32
calibration samples, raw uint8 evaluation inputs, int32 labels, preprocessing metadata, class
labels, dependency versions, source/ONNX measurements, and per-file SHA-256 checksums. Identical
submissions reuse the same active or completed job by bundle checksum; a failed job can be
resubmitted after recovery.

`AkidaModelBundleV2` (`schemaVersion: 2`) is the canvas Akida Exporter's shape: `model.fbz` instead
of `model.onnx`, no calibration set, and `sourceMetrics` reporting the accuracies measured before
submission. The host skips quantization and conversion for it and goes straight to mapping. Its
accuracy rules differ deliberately — a converted spiking model is reported at whatever it scores
and only refused below 20%, where the V1 gates above (98% source, 96% Akida) would have rejected a
legitimate result. Both kinds share the same archive-safety, checksum, and hardware-verification
rules; **Hardware verified** means `runtime_target=hardware` either way.

## In-app recovery

| Studio message | What to do |
|---|---|
| Launcher control is unavailable | Open **Backend Setup**, wait until launcher control is ready, then retry pairing. |
| SSH unreachable or authentication failed | In **Setup → Manage Targets**, edit the selected host's SSH login or saved credential, then **Save and test connection**. |
| A message about an API token being rejected | You have no key to supply — the app manages it. It first tries to re-read the token from the host over SSH; when that fails, the host is usually running a runtime installed outside this app. Choose **Install** in the Akida Runtime panel to reinstall it and regenerate the token. |
| Runtime is installed in user space | The SSH login cannot sudo. Grant it sudo on the host, then **Install** again. Until then, no hardware verification. |
| Akida runtime update failed | **Retry Akida update** in **Backend Setup**, or **Install** in **Akida Runtime**. |
| Simulator Only / Degraded Optional Capability | Read the "Why" line and the per-component verdicts in the panel — they name the missing component or the absent card. |
| No bundle found | Run all companion notebook cells, then choose **Use Latest Bundle** again. |
| Bundle validation failed | Re-run the final notebook bundle cell, or choose the newly generated bundle. |
| Physical hardware required | Check the card connection and **Check Readiness**; simulator output stays unverified. |
| Conversion failed | Update the selected Akida runtime, then resubmit the bundle. |

## Current measured status

BrainChip's reference reports PyTorch accuracy above 98% and Akida accuracy of 98.99%. The
repository's 4 August 2026 read-only check found launcher control healthy on port 8090 and the
native Neurochip runtime healthy on port 8002, but the old Akida control service on port 8091
closed its connection and the saved readiness record still reported software fallback with missing
SDK components. The corrected backend could not be deployed from the implementation sandbox because
outbound SSH approval was unavailable, so this repository does not yet claim a local Akida accuracy
or **Hardware verified** result. Replace this paragraph only after a run reports
`runtime_target=hardware`; never substitute a simulator result.

The fixed PYNQ/SC-NeuroCore overlay is outside this demo: it supports 256 neurons, two populations,
and 15,360 synapses, far below the existing 794,000-weight FCN.
