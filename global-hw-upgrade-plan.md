# Global Hardware Upgrade Plan

Date: 2026-04-16

## Bottom line

Your HP ProDesk 400 G4 SFF is a good control-plane machine for the whole NMTK stack. It is not the right box to turn into a serious GPU workstation, but it is a very reasonable Linux host for:

- `nmtk` launcher work
- Docker and multi-service backend development
- Python, Flutter, and browser-based module development
- serial, USB, and board-management tasks
- one-board-at-a-time hardware bring-up for Akida, Teensy, PYNQ, and biosignal gear

If I were optimizing this machine for the complete NMTK development process, I would treat it as:

1. a stable Linux workstation
2. a hardware bench host
3. a module orchestration box
4. a light-to-medium simulation machine

I would not treat it as:

- a big parallel simulation server
- a serious GPU training machine
- a box worth expensive CPU-era upgrades

The highest-value move is to improve memory, storage, USB/serial ergonomics, backup, and bench instrumentation before chasing exotic PCIe cards.

## What this repo actually needs

The repo is not just one hardware target. The current suite needs a machine that can support all of this at once:

- `nmtk` launcher plus a Flutter desktop toolchain
- multiple Python backends and Docker Compose services
- `neurocnl` authoring and export workflows
- `Neurosim` and `Neurobench` CPU-heavy validation and comparison runs
- `Neurochip` deployment and board-management tasks
- `Neuro-Dream-Hand` serial, HITL, and optional EMG workflows
- `Neurosense` biosignal acquisition and replay workflows

That means the host bottlenecks are usually RAM, storage, I/O discipline, and peripheral management, not raw PCIe bandwidth.

## Current machine assessment

Your current configuration:

- CPU: Intel Core i5-7500
- RAM: 16 GB
- Storage: 256 GB SSD
- Chassis: HP ProDesk 400 G4 SFF / low-profile expansion

What that means in practice:

- The CPU is still usable for day-to-day development, launcher work, and modest simulation/benchmark runs.
- 16 GB RAM is the first obvious limit once Docker, browsers, Flutter, Python environments, and a few module backends are running together.
- A 256 GB SSD is too small for a full NMTK dev machine once you add Docker images, Python virtual environments, benchmark artifacts, recordings, FPGA images, and exported packages.
- The low-profile chassis makes PCIe choices more precious, so each internal slot should be used for something the machine truly cannot do externally.

## Best upgrades inside the ProDesk

### 1. RAM: move from 16 GB to 32 GB first

This is the first upgrade I would do.

Why:

- Docker + several module backends can eat memory quickly.
- browsers, Flutter tooling, and Python environments stack up fast
- benchmark runs, simulation sweeps, and local datasets get much more comfortable at 32 GB

Target:

- 32 GB total is the sweet spot for this machine class
- if you are currently on `2x8 GB`, replace it with `2x16 GB`

I would treat 32 GB as the practical target. If you need much more than that, it is usually time for a second newer workstation rather than a heroic upgrade path on this box.

### 2. Storage: upgrade the primary dev storage aggressively

The current 256 GB SSD is too small for the full suite.

Recommended target:

- primary fast SSD: `1 TB` minimum
- secondary project/artifact SSD: `1 TB to 2 TB` if you keep local datasets, Docker layers, recordings, overlays, benchmark outputs, or export bundles

Best storage layout:

- OS + active repos + virtual environments on the fastest SSD available
- Docker data, benchmark artifacts, session recordings, exported hardware packages, and large datasets on a second SSD if possible

Important Akida-related caveat:

- if you plan to use an internal M.2 accelerator, do not assume the storage M.2 slot and an Akida M.2 module are interchangeable
- verify keying, length, BIOS behavior, and whether the slot supports that class of device before buying
- if the internal M.2 path becomes your Akida slot, then budget for a large SATA SSD for normal storage duties

### 3. Clean thermals and update firmware

Before adding expansion cards:

- clean dust from heatsink, fan, and vents
- replace thermal paste if the system is old and noisy
- update BIOS and firmware
- verify stable memory settings after the RAM upgrade

On an older office machine, boring stability work matters more than marginal raw performance.

### 4. Use internal PCIe only for high-value functions

Good uses for scarce low-profile PCIe in this machine:

- an Akida-compatible card or adapter path that is actually verified for this chassis
- extra USB if you truly run out of reliable ports
- better networking if you add a NAS or isolated lab subnet later

Bad uses:

- low-profile GPU experiments just because a slot exists
- expensive niche cards that duplicate what a USB device can already do

## What I would not spend money on for this box

### 1. Do not optimize around a GPU-first NMTK workflow

That is not where this repo gets the most value.

The repo already leans toward CPU-first simulation and optional hardware paths. The existing `Neuro-Dream-Hand/GPU_RECOMMENDATION.md` also favors CPU parallelism over forcing a GPU backend for Nengo-heavy work.

For this machine specifically, a low-profile GPU is usually the wrong trade:

- expensive for the performance gained
- thermally awkward in SFF
- not strongly aligned with the current NMTK workflow

### 2. Do not overspend on old-socket CPU upgrades

An `i7-7700`-class upgrade only makes sense if it is cheap and easy.

It usually should not come before:

- 32 GB RAM
- at least 1 TB of good SSD storage
- a powered USB hub
- proper backup
- basic lab instrumentation

### 3. Do not use spinning disks as primary dev storage

Use SSD everywhere you can for:

- Docker
- Python environments
- Flutter build outputs
- benchmark artifacts
- session recordings
- FPGA images and deployment packages

## External gear that matters more than another internal card

These upgrades usually improve full-suite development more than a second internal card.

| Item | Priority | Why it matters |
| --- | --- | --- |
| Powered USB 3 hub | Very high | Teensy, OpenBCI, debug dongles, programmers, storage, and board UARTs quickly consume ports. |
| Good USB cables, labeled | Very high | Cheap cables cause a shocking amount of fake hardware instability. |
| External SSD or USB NVMe enclosure | Very high | Great for recordings, exports, datasets, and backup rotation. |
| UPS | High | Prevents corrupted Docker state, filesystem issues, and ruined flash sessions. |
| Second monitor | High | Huge quality-of-life improvement for launcher + backend + docs + serial console workflows. |
| Basic bench network switch | Medium | Helpful once you add PYNQ, NAS, or isolated hardware nodes. |
| 2.5 GbE upgrade | Medium | Useful for NAS or remote artifact storage, not required on day one. |
| ESD mat and storage bins | Medium | Helps once you have multiple boards, dongles, and cables in circulation. |

## Hardware by NMTK workflow

### `nmtk` launcher and whole-suite orchestration

This is the foundation layer.

Recommended host setup:

- Linux as the primary OS
- 32 GB RAM
- 1 TB SSD minimum
- dual-display desk setup if possible
- UPS
- reliable backup target

Why:

- the launcher sits on top of a multi-service world
- local orchestration, Flutter builds, health checks, and browser-backed module flows all want a stable workstation more than they want a fancy accelerator

### `neurocnl`, `Neurosim`, and `Neurobench`

This group cares most about CPU, RAM, and storage consistency.

Recommended priorities:

- RAM first
- SSD second
- CPU upgrade only if very cheap
- no GPU-first buying strategy

What helps most:

- 32 GB RAM so you can keep browsers, notebooks, Docker, and test runs alive together
- fast SSD for Python envs, cache, build outputs, and benchmark result sets
- external SSD or NAS for archived runs and large artifacts

What does not help much:

- spending heavily on a half-height GPU hoping it will transform Nengo-centric workloads

If you later want bigger sweeps or more CI-like parallelism, the better move is a second modern Linux box, not over-investing in this SFF chassis.

### `Neurochip` and Akida development

This is where your PCIe motivation makes the most sense, but it still needs disciplined buying.

Ground truth from the repo today:

- `neurocnl` currently treats Akida as approximate, not fully hardware-proven
- the repo separates scaffold exportability from real SDK-backed deployability
- the remaining repo gap is still real SDK-backed acceptance evidence in a supported environment

Practical recommendation:

- keep this HP box as your Linux-primary Akida host
- use it first for MetaTF / toolchain work, package generation, and SDK-side integration
- only then decide whether local physical Akida hardware is worth the money

Best Akida path order:

1. Linux host stability
2. SSD and RAM upgrade
3. MetaTF / Akida software workflow
4. Akida cloud or remote evaluation if available
5. local Akida hardware only after compatibility is clear

Why I would be conservative:

- BrainChip has current MetaTF developer tooling and has announced M.2-form-factor Akida options
- BrainChip also has cloud/remote evaluation paths in current public material
- that means you do not need to force your first Akida dollar into a possibly awkward SFF internal install

Important chassis advice:

- do not assume an M.2 Akida board will fit or enumerate correctly just because the PC has an M.2 storage slot
- do not assume a random low-profile PCIe adapter will give you a clean vendor-supported Akida path
- if you buy local Akida hardware, prioritize a vendor-documented path over a mechanically clever path

My recommendation:

- if your main goal is software bring-up and NMTK integration, use the ProDesk as the Akida host but delay physical-card buying until you have confirmed the exact module, keying, OS support, and SDK workflow
- if your main goal is real local Akida hardware validation, prefer the most official and least hacked-together dev hardware path available, even if that means external hardware instead of an internal-only install

### PYNQ and FPGA workflow

Ground truth from the repo today:

- the PYNQ path is meaningful but still partly artifact- and runtime-dependent
- the repo already distinguishes `exportable` from truly `deployable`
- current open work is still tied to board-ready overlay artifacts and evidence

Recommended hardware:

- `1x PYNQ-Z2` board
- `2x` good microSD cards, at least 8 GB, preferably 16 GB or larger
- dedicated micro-USB cable
- Ethernet cable
- board-specific power arrangement you trust
- labeled storage for overlays, bitstreams, and manifests

What I would not do:

- buy multiple FPGA boards immediately
- spend heavily on FPGA accessories before the single-board path is comfortable

One PYNQ-Z2 is enough to support:

- export artifact testing
- remote board setup
- overlay loading practice
- Neurochip deployment-flow development

### Teensy and `Neuro-Dream-Hand`

This is one of the most practical hardware paths to buy for.

Ground truth from the repo today:

- Teensy handoff, firmware generation, and flashing are already meaningful in the suite
- remaining proof work is mostly real-board evidence rather than total architecture absence
- `Neuro-Dream-Hand` already has a real serial bridge implementation with mocked tests

Recommended hardware:

- `2x Teensy 4.1` boards, not one
- known-good USB data cables
- powered USB hub
- breadboard and jumper kit
- level-shifting and signal-conditioning parts as needed
- simple enclosure or storage case for repeatable setup

Recommended bench tools:

- 8-channel logic analyzer minimum
- 2-channel oscilloscope, roughly 50 MHz to 100 MHz class is enough for most bring-up here
- bench power supply only if you add external actuators, sensors, or motor drivers

If the workflow extends to a real hand, motor drivers, or physical actuation:

- add a real emergency-stop strategy
- keep actuator power isolated from dev-board USB power
- do not debug mixed motor and USB power casually on your main workstation

### `Neurosense` biosignal acquisition

This is where disciplined hardware selection matters a lot.

Ground truth from the repo today:

- `NeuroSense` supports a broad device story in code and docs
- the active real-board validation target is currently `OpenBCI Cyton`
- `Neuro-Dream-Hand`'s EMG streaming implementation currently names `OpenBCI Ganglion`

That means the best purchasing strategy is not "buy every biosignal board." It is:

1. buy one primary validated path
2. close the acquisition loop
3. add secondary boards only when you need a specific workflow

My recommendation:

- buy an `OpenBCI Cyton` first if you want the best suite-wide credibility and a realistic `Neurosense` flagship path
- add `OpenBCI Ganglion` later only if you specifically want to exercise the current `Neuro-Dream-Hand` EMG path as written

What to budget beyond the board:

- dongle
- battery solution
- electrode leads
- disposable snap electrodes or cup electrodes
- paste/gel where appropriate
- labeled storage for reusable consumables

Safety note:

- use battery-powered, purpose-built acquisition hardware
- avoid improvised mains-referenced biosignal experiments

### Loihi, Lava, SpiNNaker, and other advanced targets

These should not drive your first hardware budget on this HP box.

Why:

- access is often gated by vendor or lab availability
- the repo support story is more varied here
- you can do meaningful software-side work without buying local hardware immediately

Practical recommendation:

- keep the ProDesk ready as a control node
- add network hygiene, storage, and documentation discipline
- only buy or borrow these platforms when you actually have a near-term validation objective

### `Neurohub` and cross-suite artifact management

`Neurohub` is not a hardware-first module, but it benefits from hardware discipline:

- larger local SSD
- external SSD or NAS
- stable network
- organized backups

This matters because the full suite will accumulate:

- benchmark outputs
- recordings
- deployment artifacts
- bitstreams and manifests
- exported model bundles

## Suggested purchase tiers

### Tier 1: do these first

- upgrade to 32 GB RAM
- replace or add storage so you have at least 1 TB of fast SSD space
- buy a powered USB 3 hub
- buy several known-good short USB data cables and label them
- add an external SSD for artifact storage and backup
- add a UPS

This turns the ProDesk into a credible full-suite daily driver.

### Tier 2: best next buys for real hardware work

- `2x Teensy 4.1`
- `1x PYNQ-Z2`
- `1x OpenBCI Cyton` kit
- logic analyzer
- modest oscilloscope
- bench network switch if you start isolating devices or using NAS

This tier gives you the broadest real-hardware coverage across the current repo.

### Tier 3: specialized or optional

- Akida physical hardware, only after exact compatibility is confirmed
- OpenBCI Ganglion for Dream-Hand-specific EMG work
- 2.5 GbE upgrade and NAS
- second Linux workstation or mini server for heavier sweeps and CI-like load
- nicer instrumentation, bench PSU, and actuator-safety gear

## Best use of the half-height PCIe constraint

Think of the internal slots as scarce, not as a shopping challenge.

Best order of use:

1. Akida hardware if you have an exact, validated card path
2. extra I/O if you have a proven bottleneck
3. networking if your lab grows

Worst order of use:

1. speculative GPU
2. novelty cards
3. anything that blocks airflow without meaningfully improving the full suite

## Recommended lab topology

I would set up the lab like this:

- HP ProDesk 400 G4 SFF as the main Linux host
- primary SSD for OS, repos, and environments
- external SSD for artifacts and backup rotation
- powered USB hub for:
  - Teensy
  - OpenBCI dongle or board interface
  - debug adapters
  - removable storage
- Ethernet to:
  - router or switch
  - PYNQ-Z2
  - optional NAS later
- one hardware tray or drawer for:
  - labeled cables
  - spare boards
  - SD cards
  - electrodes and consumables

This is a better full-suite setup than trying to force every function inside the chassis.

## Final recommendation

If your goal is complete NMTK development, the ProDesk is worth upgrading, but only in the right way.

Recommended strategy:

- make it a stable 32 GB Linux orchestration host
- expand SSD capacity aggressively
- optimize USB, backup, and bench workflow
- buy one board each for the most realistic hardware paths
- delay expensive Akida-specific physical hardware until the exact host compatibility path is confirmed
- avoid turning this machine into a pretend GPU tower

If you do that, this HP box can be the center of a very capable small neuromorphic lab.

If you later hit limits, the right next move is usually a second newer compute box, not more heroic SFF upgrades.

## Grounding for this plan

### Repo documents

- [`README.md`](README.md)
- [`SETUP_GUIDE.md`](SETUP_GUIDE.md)
- [`neurocnl/docs/support_matrix.md`](neurocnl/docs/support_matrix.md)
- [`issues/akida-studio-deployment-plan.md`](issues/akida-studio-deployment-plan.md)
- [`issues/teensy-studio-deployment-plan.md`](issues/teensy-studio-deployment-plan.md)
- [`issues/pynq-z2-studio-deployment-plan.md`](issues/pynq-z2-studio-deployment-plan.md)
- [`issues/neurosense-research-credibility-rollout.md`](issues/neurosense-research-credibility-rollout.md)
- [`Neuro-Dream-Hand/docs/hardware_interfaces.md`](Neuro-Dream-Hand/docs/hardware_interfaces.md)
- [`Neuro-Dream-Hand/GPU_RECOMMENDATION.md`](Neuro-Dream-Hand/GPU_RECOMMENDATION.md)

### External vendor references checked on 2026-04-16

- HP ProDesk 400 G4 SFF support page: <https://support.hp.com/us-en/product/setup-user-guides/hp-prodesk-400-g4-small-form-factor-pc/15292380>
- BrainChip MetaTF developer tools: <https://brainchip.com/metatf-dev-tools/>
- BrainChip M.2 Akida announcement: <https://brainchip.com/brainchip-brings-neuromorphic-capabilities-to-m-2-form-factor/>
- BrainChip Akida FPGA Cloud announcement: <https://investor.brainchip.com/brainchip-announces-immediate-availability-of-akida-pico-for-remote-evaluation-via-fpga-cloud/>
- PJRC Teensy 4.1 official page: <https://www.pjrc.com/store/teensy41.html>
- PYNQ-Z2 setup guide: <https://pynq.readthedocs.io/en/v2.5/getting_started/pynq_z2_setup.html>
- PYNQ-Z2 board features: <https://pynq.readthedocs.io/en/v3.1/pynq_overlays/pynqz2.html>
- OpenBCI Cyton getting started: <https://docs.openbci.com/GettingStarted/Boards/CytonGS/>
- OpenBCI Ganglion getting started: <https://docs.openbci.com/GettingStarted/Boards/GanglionGS/>
