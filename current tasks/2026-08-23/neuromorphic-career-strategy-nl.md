# Getting a neuromorphic job in the Netherlands with NMTK as the portfolio piece

Date: 2026-08-23
Author: prepared for Yoshi Martodihardjo-Bink
Status: strategy document, not a task plan

---

## 0. The one-paragraph version

You are not going to get hired as a chip designer or a device physicist, and you should stop
trying to compete on that axis. You are an eight-year professional software engineer with a
cognitive-psychology and applied-AI background who has, alongside a full-time job and a full-time
master's, architected and shipped (largely through agentic development, which you should say out
loud — see §11.5) the exact
layer the Dutch national action plan says is missing: a hardware-agnostic authoring, simulation,
benchmarking and deployment toolchain for spiking neural networks. The Action Plan for
Neuromorphic Computing (Nov 2025) budgets €15M for a "market driven application lab" whose listed
deliverables are benchmark methodologies, easy access to neuromorphic hardware, demonstrators, and
"the creation and integration of neuromorphic application developer toolsets such as open SDKs and
reference designs to lower barriers for adoption." That is a description of NMTK. Your entire job
search should be built on that single sentence.

---

## 1. Where you actually fit

### 1.1 Your real profile, stated honestly

| Asset | Strength | How it reads to a neuromorphic employer |
|---|---|---|
| 8 yrs professional software engineering, lead role | Strong, verifiable | Rare in this field. Most neuromorphic people are researchers who write research-grade code. |
| Cross-platform UI/UX (Flutter, Android, Unity/Godot) | Strong | Unusual and *useful* — every SNN vendor has a terrible GUI story. |
| MSc Applied Cognitive Psychology + BSc Psychology + started BSc Cognitive AI | Strong differentiator | Genuine brain-side literacy. Neuromorphic is explicitly interdisciplinary; the roadmap repeatedly asks for "people who connect disciplines." |
| MSc Applied AI (JKU Linz), in progress | In progress | Needs a thesis. This is a lever, not a liability — see §5. |
| NMTK: multi-module SNN toolchain, CNL→IR→NIR compiler, canvas, simulators, real Akida + PYNQ-Z2 deployment, benchmarking, ~1100 commits | Very strong, under-marketed | This is the portfolio. It is bigger than most people's theses. |
| Hardware depth (RTL, analog, memristors, device physics) | Absent | Do not fake it. Say so plainly in interviews and pivot to the stack layer you own. |
| Publications | None yet | Fixable, cheaply — see §6.4. |

### 1.2 Which of the six whitepaper areas you occupy

The Dutch whitepaper splits the field into Materials, Devices, Circuit Design, Hardware
Architecture, **Algorithms**, **Applications**. You are Applications, with a foot in Algorithms and
a strong claim on the cross-cutting "tooling / hardware-software co-design" theme that both the
Roadmap and the Action Plan name as a gap. Every conversation you have should start there. If you
open with materials or devices you will be out-argued in ninety seconds by a second-year PhD.

### 1.3 Role titles to search for

Use these literal strings on LinkedIn, company career pages, AcademicTransfer and Ashby/Greenhouse
boards:

- Machine Learning Applications Engineer / Edge AI Applications Engineer
- SDK Engineer, Toolchain Engineer, Compiler Engineer (ML), Runtime Engineer
- Developer Experience / Developer Relations Engineer (deep-tech hardware)
- Field Application Engineer (this is the classic entry route into a chip company for a
  software person; Innatera has posted these)
- Research Engineer / Research Software Engineer (universities, SURF, TNO, imec)
- Neuromorphic Algorithms Engineer, Spiking Neural Network Engineer
- Systems / Integration Engineer, Embedded ML

Deliberately *not*: Digital Design Engineer, Physical Design, Analog IC, Device Engineer.

---

## 2. Where to apply — Dutch neuromorphic core

Ranked by fit for your profile, best first.

### Tier 1 — Direct hits

**1. Innatera Nanosystems** — Delft HQ, offices Rijswijk. ~€30M+ raised. Spiking Neural Processor
(T1 / Pulsar), the first commercial neuromorphic microcontroller. TU Delft spin-off.
- Why you: they sell a chip that nobody knows how to program. Their entire commercial bottleneck is
  developer onboarding — SDK, model zoo, encoding presets, deployment flow. That *is* NMTK.
- Roles seen: Staff Embedded Software Engineer, Field Application Engineer, Research Scientist in
  Neuromorphic AI, ML engineers. They recruit continuously.
- Contact anchor: Amir Zjajo (CTO-level, quoted in the Roadmap interviews).
- Apply via https://www.innatera.com/careers/ and https://jobs.ashbyhq.com/innatera. Also email a
  hiring manager directly — a 13-person job board means a small company where a good direct mail
  lands.

**2. Axelera AI** — Eindhoven HQ + Amsterdam, plus Leuven, Zurich, Milan, Florence, Paris, Bristol.
~€200M raised, ~250–750 staff depending on source, aggressively hiring (job postings roughly
doubled 2025→2026). In-memory computing AI accelerator (Metis), commercially shipping.
- Why you: they are past the research phase and into the "customers must be able to use this"
  phase. Voyager SDK, model conversion, quantization, runtime, evaluation tooling. Your
  quantization/export/fidelity-matrix work maps straight onto it.
- Caveat: they are "neuromorphic-adjacent" (in-memory digital, not spiking). Do not lead with SNN
  purism; lead with toolchain and deployment.
- Apply: https://axelera.ai/careers. Remote-from-anywhere-in-Europe options exist.

**3. Snap (ex-GrAI Matter Labs), Eindhoven** — the Eindhoven site owns architecture exploration,
hardware design and **AI tools**. Orlando Moreira (interviewed in the Roadmap) is there.
- Why you: "AI tools" is literally the team name for what you built.
- Harder to find postings; go via LinkedIn people-search on the Eindhoven site + direct message.

**4. SURF** — Amsterdam/Utrecht. National e-infrastructure. Sagar Dolas runs the Emerging
Technology Platform, which the Action Plan names as the model for the €15M application lab.
- Why you: SURF is the most likely organisation to be *funded to build what you already built*. A
  research-engineer role here is the single cleanest fit in the country, and it is a public
  institution so hiring is transparent and the bar is "can you engineer", not "do you have a PhD".
- Watch https://www.surf.nl/en/about-surf/working-at-surf and AcademicTransfer.

**5. imec Netherlands / Holst Centre** — Eindhoven. µBrain and SENeCA neuromorphic accelerators.
Named as prototyping-facility host in both the Roadmap and the Action Plan. Kanishkan Vadivel
(interviewed).
- Why you: they need people to make their accelerators usable by third parties.

**6. TNO** — partner in NC-NL, applied research, defence/security/industry programmes. Research
software engineer and applied-scientist roles appear regularly. Good for someone with industry
experience and no PhD.

### Tier 2 — Smaller / earlier, but real

- **Hoursec** — brain-inspired software and chips for more efficient AI training. Alexandra Pinto.
  Very small; a direct mail with a working toolkit will be read by a founder, not a recruiter.
- **IMChip** — in-memory HPC chips. Same logic.
- **Op-Net** — Taras Matselyukh; edge anomaly detection. Named in the Roadmap interviews.
- **Single Quantum** (Delft) — quantum/neuromorphic crossover, already in a Horizon Europe project
  with Dutch universities.
- **Nowi / Nexperia, Sencure, Salland Engineering, Bruco, ICsense (NL/BE)** — low-power and
  mixed-signal shops that touch edge inference.

### Tier 3 — Non-Dutch but reachable and highly relevant

- **SynSense** (Zurich / Chengdu) — DYNAP-CNN, Speck. Your Neurochip already has a Speck target;
  that is a concrete conversation opener. Remote/EU roles exist.
- **Prophesee** (Paris) — event cameras; co-authors on the NeuroBench paper.
- **BrainChip** (Akida) — you have deployed to real AKD1000 silicon and written an on-device
  benchmark. Very few applicants anywhere can say that. Their EU presence is thin but a strong
  community contribution gets noticed.
- **Intel Labs / Lava community** — you already integrate Lava. Contributing upstream is a free
  credential.

---

## 3. Adjacent Dutch deep-tech worth targeting

If neuromorphic-pure roles don't land fast enough, these are the realistic pivots that keep you in
the same story (low-power, edge, event-driven, sensor-to-inference) and keep the neuromorphic
thesis alive on the side.

**Semiconductor & high tech (Brainport / Eindhoven, Nijmegen, Delft, Twente):**
NXP Semiconductors (eIQ edge-AI tooling, Eindhoven/Nijmegen), ASML, ASM International, Nearfield
Instruments, Sioux Technologies, Prodrive Technologies, Demcon, Technolution, TOPIC Embedded
Systems, Thermo Fisher Eindhoven.

**Defence / radar / space — currently very well funded in NL:**
Thales Nederland (Hengelo — radar, low-power sensing, exactly the event-driven use case),
Airbus Defence & Space Leiden, cosine, S[&]T, Astron (Dwingeloo — LOFAR is named in the whitepaper
as a neuromorphic-relevant data-volume problem; a genuinely great fit for your benchmarking work).

**Photonics (the crossover the Roadmap explicitly wants to explore):**
PhotonDelta ecosystem, SMART Photonics, EFFECT Photonics, PHIX, Lionix. TU/e's photonic
neuromorphic group (Patty Stabile, Martijn Heck) is the academic anchor.

**Health / wearables / medtech:**
Philips Research (Eindhoven), Onera Health, Byteflies (BE), Salvia BioElectronics, Nemo Healthcare.
Neuromorphic wearables are named as a target application in the Action Plan.

**Users / end-user side named in the Roadmap:**
ING (Mariana Gómez de la Villa, Cees van Wijk — they were interviewed for the Roadmap and are
looking at emerging compute), Alliander (grid state estimation is a named use case), Toyota,
Dutch Data Center Association members.

---

## 4. Academic and institute routes (and this is where your thesis lives)

You need an MSc thesis. Doing it *inside* the Dutch neuromorphic ecosystem solves the job problem
and the degree problem in one move: an external thesis is a six-month paid-or-unpaid audition, and
in this field it converts to an offer far more often than a cold application does.

| Lab | People to approach | Why it fits you |
|---|---|---|
| **CogniGron, RUG** (Groningen) | Beatriz Noheda (director), Herbert Jaeger (algorithms/theory), Elisabetta Chicca (circuits), Dirk Pleiter (HPC), Farhad Merchant | They are running a **Demonstrator Programme** connecting industry problems to fundamental research and were recruiting Research Leads for it in mid-2026. A demonstrator programme needs demonstrator *tooling*. Also leads the KIC-LTP national consortium application. |
| **Radboud / RNCI + Donders** (Nijmegen) | Marcel van Gerven, Johan Mentink (NC-NL coordinator), **Mahyar Shahsavari** (neuromorphic software/hardware mapping) | Shahsavari is the closest supervisor match in the country to what you built. Mentink is the person who convenes the national ecosystem. |
| **TU Delft** | **Charlotte Frenkel** (neuromorphic HW + strong open-source/tooling ethos), Said Hamdioui (computer engineering), Guido de Croon (MAVLab — neuromorphic drones) | Frenkel's group cares about the hardware/software interface and about honest benchmarking. De Croon's drone work is a ready-made application demo. |
| **TU/e** (Eindhoven) | **Federico Corradi** (SNN algorithms + hardware), Manil Dev Gomony, Henk Corporaal, Patty Stabile (photonic NC) | Corradi is an obvious thesis supervisor for an SNN-tooling topic and sits inside the Brainport industry network. |
| **UT** (Twente) | **Amir Yousefzadeh** (ex-imec, SENeCA — toolchains and accelerators), Wilfred van der Wiel (BRAINS/MESA+) | Yousefzadeh is the toolchain person; SENeCA needs software. |
| **CWI** (Amsterdam) | Sander Bohté | SNN learning algorithms; strong publication route. |
| **SURF** | Sagar Dolas | Internship/thesis on benchmarking infrastructure — direct line to the application lab. |

**How to approach them:** one short email, three paragraphs. What you built (one sentence + link +
90-second video), the specific thesis question you propose that serves *their* agenda, and the fact
that you are a working senior engineer who will deliver working software rather than a prototype
that dies at submission. Attach nothing; link everything.

**Thesis topics that would land** (pick one that produces a paper *and* a demo):
1. *A hardware-independent NIR-based deployment path: quantifying fidelity loss across Akida, Loihi,
   PYNQ and CPU simulators.* You already have the export targets and a `faithful / approximate /
   unsupported` fidelity scale. Turn that matrix into measured numbers. This is publishable and
   nobody has done it well.
2. *Reproducing the NeuroBench algorithm-track benchmarks through a single authoring front-end.*
   You have already replicated the braille letter-reading task at 86.43% — which is a NeuroBench
   benchmark. Extend to the other tracks and report cross-target energy/latency.
3. *Developer experience as a bottleneck in neuromorphic adoption: a controlled study.* Your
   cognitive-psychology MSc makes you uniquely able to run a real usability study (time-to-first-
   working-SNN, error rates, cognitive load) comparing NMTK against raw vendor SDKs. This is a
   genuinely novel contribution, it is cheap to run, and it is exactly the "derisking adoption"
   evidence the Roadmap says the field lacks. **This is the one I would pick.** It is the only
   topic on this list where your psychology background is a competitive advantage rather than a
   footnote.

---

## 5. The single highest-leverage move: contact NC-NL

Neuromorphic Computing NL launched as a formal alliance in January 2026, coordinated through
Digital Holland / Topsector ICT, with RUG, Radboud, TU Delft, TU/e, UT, SURF, TNO, imec, CWI,
Axelera AI and Innatera as founding participants.

- Contact: `nc-nl@digital-holland.nl` — Bezuidenhoutseweg 12, 2594 AV Den Haag.
- Follow Digital Holland and NC-NL on LinkedIn; the ecosystem is small enough that visible
  contributors get pulled in.

**What to send them:** not a CV. Send a one-page brief titled something like *"An open-source
reference implementation for the NC-NL Application Lab toolset"* that maps NMTK's existing modules
onto the four bullets under Action Plan §II, states honestly what works and what needs hardware,
and offers it as a contribution. Ask for a 30-minute conversation, not a job.

Why this works: the alliance is brand new, has ~€5M of ecosystem-development money on the table,
needs demonstrable assets to justify the €15M application lab, and has almost no software people.
An unsolicited, working, AGPL-licensed toolkit that already talks to Akida, PYNQ, Lava, Nengo,
snnTorch, Rockpool, Sinabs, Brian2 and SpiNNaker is not a job application — it is an asset they can
point at in a funding proposal. Being the person attached to that asset is worth more than twenty
applications.

Do the same, separately, with **Mission 10X** and the **NL-ECO** coalition (Hans Hilgenkamp, UT).

---

## 6. How to present the work

### 6.1 The narrative, in the order you should always tell it

1. **The problem, in their words, not yours.** "The Dutch roadmap says companies are hesitant
   because adoption isn't derisked and there's no standardised hardware-software co-design
   framework. I hit that wall personally and built one."
2. **What it is, in one sentence.** "A cross-platform app plus backend that lets you author a
   spiking network in controlled English or on a canvas, compile it to NIR, simulate it, benchmark
   it, and deploy it to real neuromorphic hardware without assembling any vendor toolchain."
3. **Proof it is real, not a mockup.** Real Akida AKD1000 silicon. Real PYNQ-Z2 FPGA with a
   root-privileged bitstream loader you had to build because user-space couldn't program the
   fabric. Nine Jupyter kernels. ~1,100 commits.
4. **Proof you are honest about it.** Your README's three-term support vocabulary — `works`,
   `needs hardware`, `not implemented` — plus the per-target `faithful / approximate / unsupported`
   fidelity scale. **Lead with this in interviews.** In a field drowning in overclaiming, a
   candidate who ships a document that says "this path does not work today" is instantly credible.
   This is your strongest single signal and it is currently buried in a README.
5. **What you learned that is not in any paper.** The war stories: the PYNQ overlay that returned
   silence because a register-map key was dropped in transit; simulators that ran a network of
   zeros because CNL carries shape but not values; tau discretisation unified across targets. These
   are exactly the integration failures the ecosystem has not yet hit at scale, and telling them
   proves you have actually been to the bottom of the stack.

### 6.2 Artefacts to produce, in priority order

1. **A 90-second and a 4-minute demo video.** You already have 18 screenshots and screen
   recordings. Cut them. No voiceover perfectionism — just narrate. Host unlisted on YouTube. Every
   email links to the 90-second one. Without this, nobody will clone your repo.
2. **A one-page PDF project brief.** Problem, screenshot, architecture diagram, "what works today"
   table, link. This is what you attach to applications and hand out at events.
3. **A public README hero section.** Your current README is excellent as documentation and weak as
   a pitch. Add, at the very top: one screenshot, one GIF, one sentence, and the "what works today"
   table. Reviewers spend 20 seconds.
4. **A written technical post (2000 words) on the NIR round-trip problem.** There is a `paper/`
   directory already — turn it into something. Post to arXiv (cs.NE) *and* as a blog. An arXiv
   preprint costs you nothing and converts "hobby project" into "research output" on a CV.
5. **A benchmark result table.** Same network, measured on Akida, PYNQ-Z2, and CPU simulation:
   accuracy, latency, energy where measurable. Even a small honest table beats a large vague claim.

### 6.3 Two things to fix before you show anyone

- ~~**The `Neurobench` module name is a collision.**~~ **Corrected 2026-08-24 — I was wrong, three
  times over.** Your module already *is* the integration I was recommending. Verified in
  `Neurobench/neurobench/app/services/neurobench_executor.py`: it imports
  `neurobench.benchmarks.Benchmark`, `neurobench.datasets` (WISDM, MackeyGlass, PrimateReaching,
  SpeechCommands), `neurobench.metrics.static`, `neurobench.metrics.workload`,
  `neurobench.models.NeuroBenchModel` and `MFCCPreProcessor`. So there is no name collision to
  apologise for — it is an integration. **But it is not finished** (established 2026-08-24): it is
  not wired end-to-end from CNL Studio. The Setup benchmark dropdown only stores a selection,
  Review's benchmark result field is never populated, and the bridge passes CNL text rather than the
  trained checkpoint, NIR weights, test set or Akida bundle. Describe it as an in-progress
  standardised benchmarking workbench, never as a shipped feature, and keep it off the CV until the
  handoff works. Do not rush a connection either — a quick wire-up would return CPU-estimated
  numbers that look like measurements of the trained model or the hardware, which is worse than
  having none. Smallest honest milestone: one MNIST handoff carrying the exact trained artifact and
  test set, returning accuracy, latency and provenance into Review. Then rename to **NeuroBench UI**
  and credit the upstream package in `THIRD_PARTY_NOTICES.md`.
- **Your CV says "Python: Basic knowledge."** Your repository is overwhelmingly Python — FastAPI
  services, a compiler pipeline, hardware workers, a test suite. Either that line is four years
  stale or you are underselling yourself into the reject pile. Fix it before you send anything.

### 6.4 CV rewrite, concretely

Your current CV is a chronological employment record. For this field it needs to become an
evidence document. Restructure to:

1. **Header + one-line positioning statement.** e.g. *"Senior software engineer (8 yrs) moving into
   neuromorphic computing. Built and shipped an open-source SNN authoring, benchmarking and
   hardware-deployment toolchain covering Akida, PYNQ-Z2, Lava and six simulators."*
2. **Selected project: NeuroMorphicToolKit** — put it *above* work experience, with 5–6 bullets,
   each with a number, and a link. This is the reason anyone will call you.
3. **Work experience**, rewritten toward transferable signal: lead role, cross-platform delivery,
   R&D, testing discipline, UX. Keep it short.
4. **Education** — move the JKU Applied AI MSc up; name the thesis topic once you have one.
5. **Technical skills** — rewrite entirely. Add: Python, FastAPI, PyTorch, snnTorch, Nengo,
   Rockpool, Sinabs, Brian2, Lava, NIR, Akida SDK, PYNQ, Docker/Podman, CI, Flutter/Dart, Riverpod.
   Drop SPSS. Drop the "Assembling pc / repairing smartphones" hardware line — it reads as
   hobbyist and actively undercuts a technical CV at this level.
6. Two pages maximum. Dutch and English versions.

**LinkedIn:** headline should say what you are moving *to*, not what you are: "Software Engineer →
Neuromorphic Computing | SNN tooling, NIR, edge deployment". Post the demo video once. Post the
technical writeup once. Comment substantively on NC-NL, CogniGron, Innatera and Axelera posts —
in a field of a few hundred Dutch people, consistent visible competence is a recruiting channel.

### 6.5 What to say about the gaps

Rehearse these answers; they will be asked.

- *"You don't have a hardware background."* — "Correct. I'm not a circuit designer and I won't
  pretend to be. I work at the layer between a trained model and silicon, and I've taken that layer
  all the way to running bitstreams on an FPGA and inference on an AKD1000. What I bring is
  production software engineering discipline to a field that mostly has research code."
- *"Why should we hire a psychologist?"* — "Because adoption is the field's bottleneck, and I can
  measure and fix why people bounce off your SDK. That's a cognitive-ergonomics problem and it's
  literally what I was trained in."
- *"No publications?"* — Have the arXiv preprint by then. If not: "One in preparation; here's the
  benchmark data."
- *"This is a solo project — how do we know it's good?"* — Point at the support matrix, the test
  suites, the ADRs in `docs/ADR-claude/`, the CI, and the honest `not implemented` labels.

---

## 7. Events, communities, and where the network actually is

- **NC-NL / Neuromorphic Now days** — the Dutch community's main gathering. Attend the next one.
  Non-negotiable.
- **Mission 10X** and **NL-ECO** — the two predecessor coalitions; both still active as networks.
- **Bits&Chips Event / Brainport / High Tech Campus Eindhoven** meetups — where the semicon-adjacent
  hiring managers are.
- **NICE** (Neuro-Inspired Computational Elements) and **ICONS** — the field's two main conferences;
  NICE is often in Europe and is small and friendly to newcomers.
- **Telluride Neuromorphic Cognition Engineering Workshop** — three weeks, competitive, and the
  single densest networking event in the field. A toolkit like yours is an excellent application.
- **DATE / ISCAS** — more hardware-oriented, lower priority for you.
- **Open source as networking:** contribute to NIR, Lava, snnTorch, or the NeuroBench harness. A
  merged PR in NIR puts your name in front of exactly the right ~50 people. This is the cheapest
  credential available to you and you are already fluent in these codebases.

---

## 8. A 90-day plan

**Weeks 1–2 — make the work legible**
- Cut the 90-second and 4-minute demo videos.
- Rewrite the README hero section; add the "what works today" table at the top.
- Fix the Python line and rewrite the CV per §6.4.
- Decide the `Neurobench` naming question.

**Weeks 3–4 — make the first move**
- Email NC-NL with the one-page brief. Ask for a conversation, not a job.
- Email, individually and specifically: Shahsavari (RU), Corradi (TU/e), Frenkel (TUD),
  Yousefzadeh (UT), Dolas (SURF). Propose the thesis topic that fits each of them.
- Apply to Innatera and Axelera through their boards *and* send a direct mail to a named engineer
  or manager at each.

**Weeks 5–8 — build the evidence**
- Produce the cross-target benchmark table (Akida vs PYNQ vs simulation).
- Write the technical post; submit to arXiv cs.NE.
- ~~Open one upstream PR against NIR, Lava or snnTorch.~~ **Dropped — see §11.4.** Not worth your
  time. If you ever hit a genuine NIR/snnTorch bug in the course of work you were doing anyway,
  file a 15-minute *issue*, not a PR. Otherwise do nothing here.

**Weeks 9–12 — convert**
- Follow up on everything, once, politely.
- Attend whatever NC-NL or Brainport event falls in the window.
- Lock in the thesis placement. If a company thesis is on the table, take it over a lab thesis —
  it pays and it converts.

**Success criteria at day 90:** thesis supervisor secured, arXiv preprint up, at least three
first-round conversations held, NC-NL aware of the toolkit by name.

---

## 9. Honest risk assessment

- **The Dutch neuromorphic job market is genuinely small.** A few hundred people, maybe a few dozen
  open software-side roles at any moment, concentrated in Delft, Eindhoven and Groningen. Applying
  broadly will not work; being *known* will. Weight your effort accordingly: 20% applications, 80%
  network and artefacts.
- **Funding is uncertain.** The Action Plan's €50M is a request, not a budget; the Roadmap notes
  that new public money is unlikely before 2027 and depends on cabinet decisions. Do not build your
  plan on the application lab existing. Build it on the two funded companies (Innatera, Axelera)
  and the universities, and treat NC-NL as a network multiplier rather than an employer.
- **You may have to take an adjacent role first.** An edge-AI or embedded-ML role at NXP, Thales,
  Sioux or Demcon while finishing a neuromorphic thesis is a perfectly good two-year path into the
  field, and pays substantially better than a PhD stipend. Do not treat it as failure.
- **Salary reality check — superseded by §11.2.** Short version: university and PhD-scale salaries
  are off the table for you, which removes most of §4's employment routes as *jobs* (they survive
  only as thesis or external-PhD arrangements on top of a paying job). Neuromorphic-pure work and
  a large pay rise are in direct tension in the Netherlands today. Read §11.2 before acting on §2.

---

## 10. The three sentences to memorise

1. "I build the layer between a trained spiking network and real neuromorphic silicon, and I've
   taken it all the way to running inference on an Akida board and a bitstream on a PYNQ FPGA."
2. "The Dutch action plan says adoption is blocked on tooling, benchmarking and derisking — I built
   a working reference implementation of exactly that, on my own, and I'm honest in the
   documentation about which paths don't work yet."
3. "I'm not a chip designer. I'm the production software engineer this field is short of, with a
   cognitive-science background that lets me actually measure why people can't use your SDK."

---

## 11. Revision 2 (2026-08-23, same day) — corrections and the money question

Written after your pushback. Where this section conflicts with sections 1–10, this section wins.

### 11.1 Publishing your work: Zenodo, arXiv, and what each one is

This section replaces the earlier version, which was written too densely to be useful.

**What Zenodo is**

Zenodo is a free, permanent public archive for research outputs, run by CERN and funded by the
European Commission. You upload something — a dataset, a piece of software, a document, a poster —
and Zenodo stores it forever and gives it a DOI, which is a permanent identifier that looks like
`10.5281/zenodo.1234567`. Anyone can cite it, the link never rots, and there is no gatekeeper: no
peer review, no editor, no institutional affiliation required. If you can log in, you can publish.

The reason it matters for you is that a DOI is what turns "a GitHub repository" into "a citable
research output". On a CV, in an email to a professor, or in a funding proposal, those are read very
differently, even though the underlying thing is identical. It is the cheapest credibility you will
ever buy.

It also integrates directly with GitHub. You authorise Zenodo to see your repository, flip a switch,
and from then on every tagged release is automatically archived and gets its own DOI, with one
"concept DOI" that always points at the latest version. Setting this up takes about twenty minutes
and then never needs attention again.

Do this one. It costs almost nothing and there is no downside.

**What arXiv is, and whether you can just post to it**

arXiv is the preprint server that most of physics, mathematics and computer science uses. You post a
paper there before (or instead of) journal publication, and it becomes publicly readable and citable
immediately. `cs.NE` is its "Neural and Evolutionary Computing" category, which is where neuromorphic
work goes.

You asked whether anyone can do this and whether you need credentials. The honest answer is: almost
anyone, with one small hurdle and one real one.

*The small hurdle is endorsement.* The first time you post to a given category, arXiv wants some
signal that you are a researcher rather than a spammer. There are two ways past it. The easy way is
to register your arXiv account using your **JKU Linz student email address** rather than a personal
one — arXiv automatically endorses accounts from recognised academic domains, and a university
student address usually clears it without you doing anything. The fallback is to ask a person to
endorse you: anyone who has had three or more papers accepted in that category in the last five
years can do it with two clicks, and your thesis supervisor or any of the Dutch academics listed in
section 4 would be an entirely normal person to ask. There is no fee and no affiliation requirement
beyond this.

*The real hurdle is moderation.* arXiv has human moderators who reject or reclassify submissions
that read as product announcements rather than research. A paper that says "here is my toolkit and
here are its features" will very likely be bounced, or moved out of cs.NE into a software-engineering
category where nobody in your field will see it. This is the thing that actually stops people, not
credentials.

**So what would the paper have to be?**

It has to be a paper that measures something, where your toolkit is the equipment you used rather
than the subject. The version I would write looks like this:

- **The question.** Spiking-network tooling is fragmented across a dozen frameworks and vendor SDKs.
  NIR exists as a common interchange format that is supposed to let a network move between them. But
  nobody has actually measured what survives that journey. Does the network that arrives on the chip
  still behave like the one you trained?
- **The method.** Take one trained network. Export it through NIR to every target you support.
  Feed all of them identical inputs. Measure what comes out.
- **The results.** A table: per target, the change in accuracy, the change in spike counts, latency,
  and energy where you can measure it. This does not have to be large. A small, honest, carefully
  described table is publishable; a large vague claim is not.
- **The part that makes it worth reading — a catalogue of silent failures.** This is your real
  contribution and it is the reason a moderator would accept the paper. You have personally found,
  and written down, a series of ways in which a spiking network can be quietly destroyed in transit
  without anything reporting an error: a controlled-English description that carried the network's
  shape but not its trained weights, so the simulators dutifully ran a network of zeros; a time
  constant discretised differently by different backends; a single key dropped from a register map
  by an offset writer, so an FPGA returned silence while every readiness check stayed green; layer
  sizes inferred differently by the canvas and by the deploy path. Nobody publishes this kind of
  thing, because finding it requires having actually pushed networks onto real hardware and then
  spent weeks working out why they did nothing. You have done that. It is unglamorous, genuinely
  useful, and nobody is competing with you for it.
- **The apparatus.** The toolkit, described briefly, at the end. Two pages at most.

**What I would actually do, given your time**

Not the paper. Not now. In order:

1. **Zenodo, this week.** Tag a release, connect the repository, get the DOI. Twenty minutes.
2. **Register the arXiv account with the JKU email now**, even though you are not posting yet. It
   costs five minutes and means the endorsement question is already settled whenever you do want it.
3. **Write the paper as a chapter of your JKU thesis, not as extra work.** You have to write a thesis
   anyway. Write this once, submit the same text to arXiv when the thesis is finished, and the
   marginal cost of the publication is zero.

There is a fourth option worth knowing about but not acting on yet. The *Journal of Open Source
Software* publishes short, genuinely peer-reviewed papers about research software — about a thousand
words, free, and the review happens openly on GitHub with reviewers who give useful feedback. It is
a better fit for a tool than arXiv is, and it produces a real peer-reviewed publication. The cost is
that review takes months and requires you to be responsive throughout, which is exactly the thing
you do not currently have. Keep it in mind for after the thesis.

### 11.2 Money: the honest answer

You are at €65k all-in and that is the binding constraint. Then say so and plan around it, because
the plan in §2 and §4 does not maximise income and I should have led with that.

**The core tension:** Dutch neuromorphic employers sort into (a) one well-funded scale-up that can
pay properly, (b) small startups that cannot, (c) universities and institutes that definitely
cannot. If income is the constraint, most of §4 is not a job list — it is a *thesis* list, to be
done on top of a paying job.

**Realistic Dutch senior/staff software salary bands, 2026, base + bonus:**

| Segment | Band | Notes |
|---|---|---|
| Typical Dutch product company / agency, senior | €65–85k | Where you are now. This is the trap. |
| Well-funded deep-tech scale-up, senior→staff | €85–130k + equity | Axelera AI sits here. |
| ASML / NXP / ASM, senior→principal | €85–130k | Dutch, deep-tech, generous secondary terms, strong pension. |
| Amsterdam trading firms (Optiver, IMC, Flow Traders, Da Vinci, Maven) | €120–250k+ | Dutch/EU companies. Bonus-heavy. Hardest interviews in the country. |
| Adyen, Booking, Databricks/Datadog/Snowflake NL entities | €100–170k | Some are US-parented but employ you through a Dutch entity on Dutch contracts. |
| European defence/sovereignty tech (**Helsing**, Quantinuum, IQM, Mistral) | €100–160k + equity | EU-domiciled, pays top-of-market for Europe, hiring hard, and ideologically aligned with the digital-sovereignty framing you already use. |
| ZZP / your own BV, senior contractor | €85–115/hr → €140–190k revenue | You already have the vehicle. See caveats below. |

**Your four realistic routes to a significant rise, ranked:**

1. **Staff-level at Axelera AI.** The only path that is simultaneously neuromorphic-adjacent and
   properly paid. Target *staff*, not senior. Negotiate equity hard — at their stage it is the real
   multiplier. This is the single best outcome available to you and it should be your primary
   target, ahead of Innatera.
2. **ASML or NXP, senior/principal, edge-AI or tooling.** Dutch, deep-tech, pays 30–70% above where
   you are, and both are named in the national roadmap as the semicon players NC will eventually
   touch. You can run a neuromorphic external PhD alongside (see §11.3) and they are culturally
   used to that.
3. **The FPGA/low-latency bridge into Amsterdam trading.** This is the option nobody would suggest
   to you and it deserves a look. You have *actually deployed a bitstream to an FPGA and debugged
   why the fabric returned silence* — that is a real, verifiable, uncommon line. Optiver, IMC and
   Flow Traders hire FPGA and low-latency systems engineers at €120–200k. It is not neuromorphic
   and the interviews are brutal, but it would roughly double your income and fund everything else,
   including a part-time PhD. Treat it as the "money" branch of a two-branch search.
4. **Contract through your own BV.** Fastest lever, since you already have the company. Senior
   Flutter/embedded rates in NL run €85–115/hr. Caveats that matter: no paid holiday, no pension,
   no sick pay, utilisation risk, and the Dutch tax authority resumed enforcing false-self-
   employment (*schijnzelfstandigheid*) rules from 2025 — your contracts need real substitution and
   autonomy clauses. Also: there is essentially no contract market in neuromorphic, so this branch
   funds the life but does not advance the career goal.

**What I would actually advise:** run two parallel searches. A **money branch** (Axelera staff,
ASML/NXP, Helsing, or trading) and a **field branch** (thesis placement at RU/TU-e/TUD/SURF, and
the NC-NL conversation). The thesis branch does not need to pay — it needs to be part-time and
prestigious. Do not let anyone talk you into a €55k research-engineer role because it is "in the
field". You can be in the field and well paid; it just requires the field branch to be a thesis and
a network rather than a paycheck, at least for the first two years.

**One thing to fix regardless of branch:** your CV reads as a Flutter/mobile lead, and Flutter caps
out around €85k in the Netherlands. Every band above €100k in that table is systems, ML, compilers,
embedded or low-latency. NMTK is your evidence that you are those things now. Lead with it.

### 11.3 The PhD-while-employed question — you are right, and here is why

Your instinct is correct and the salary numbers I quoted only apply to one specific arrangement.

**A university PhD position is an employment contract with the university**, paid on the CAO-NU
P-scale (roughly €3.0–4.0k/month gross over four years). That scale applies *because the university
is your employer*. If the university is not your employer, the scale is irrelevant. So:

| Arrangement | Who employs you | What you earn |
|---|---|---|
| University PhD position (*promovendus*) | The university | CAO-NU P-scale. **Never take this.** |
| **Buitenpromovendus / external PhD** | Your existing employer, unchanged | **Your existing salary, unchanged.** |
| Industrial PhD hosted at your employer | Your employer | Your salary, often part-subsidised |
| TNO or imec PhD | TNO / imec | Well above university scale — these are market-adjacent employers |
| MSCA Doctoral Network industrial doctorate | The project | Well above Dutch PhD scale, **but you are ineligible in NL** — MSCA has a mobility rule excluding candidates who have lived in the recruiting country more than 12 of the previous 36 months. You'd have to go to Belgium or Germany. |

**The buitenpromovendus route is exactly what you described and it is completely standard in the
Netherlands.** You stay employed, you keep your salary and your permanent contract, you find a
*promotor* at a Dutch university, you agree a topic, and you defend a thesis. The university does
not pay you and does not need to. What you negotiate with your employer is **time**, not money —
typically one day a week, sometimes framed as R&D or professional development. Many Dutch tech
employers will grant it, especially if the topic serves them; ASML, NXP, TNO and Philips all do
this routinely.

Two honest caveats:
- Part-time it takes **6–8 years**. With a family, a full-time job and a master's still to finish,
  that is a very large commitment and you should be clear-eyed about it.
- **You probably do not need a PhD at all** for the roles in §1.3. Applications, tooling, SDK,
  compiler and developer-experience roles do not require one anywhere in this field. A PhD is
  required for research-lead and principal-scientist tracks. Decide which of those you actually
  want before signing up for eight years. My read: finish the MSc, get the well-paid role, and
  revisit the PhD question in two years from a position of strength. Section 4 over-weighted
  academia and this corrects it.

Also note **WBSO**: if your own BV does R&D work, that is a Dutch R&D wage-tax credit that directly
subsidises R&D labour costs. Relevant if any of this ends up running through your company.

### 11.4 The upstream PR: withdrawn

You are right and I was adding work to a plate that is already full. Withdrawn.

The reasoning behind it was name-recognition, and there is a much cheaper substitute: you already
*have* the artifact that a PR was meant to buy you. A finished, polished, video-demonstrated
platform is rarer and more persuasive than a merged pull request, and it is already done.

If you ever want the near-zero-cost version: when your own work next hits a genuine bug or gap in
NIR or snnTorch, **file an issue** — fifteen minutes, no follow-up obligation, same name in front
of the same maintainers, and it is actually more useful to them than a drive-by PR. Otherwise, skip
it entirely. Nothing in this plan depends on it.

More generally, given your constraints, the *only* things in §8 that are worth your time are:
the Zenodo DOI, the English-language version of the video you already have, the CV rewrite, and
the emails. Everything else is optional and can wait for the thesis.

### 11.5 Agentic development: say it out loud, and here is how

You are right that section 1 overstated it, and I have corrected §0. But do not overcorrect —
"an AI wrote it" is as inaccurate as "I hand-wrote 40,000 lines", and the second inaccuracy is the
one that gets you caught in an interview.

**The accurate and genuinely strong framing:**

> "I architected and directed this; a large share of the code was written by AI agents under my
> direction. I made the design decisions, set the module boundaries, found the failures on real
> hardware, and verified the behaviour. Working at that scale alongside a full-time job and a
> master's is only possible that way, and I'd expect the code quality to be higher if I'd written
> it at a slower pace myself."

In 2026 this is not a confession, it is a description of how competent senior engineers work, and
being able to state precisely *what* you contributed is itself the senior signal. The candidates
who get caught are the ones who cannot answer follow-up questions about their own repository.

**What is unambiguously yours, and what you should talk about:**

- Reading the NC-NL documents and correctly identifying the gap. No agent did that.
- The architecture: one app, one backend container, workers only where a vendor SDK forces
  isolation. Module boundaries. The decision to make NIR the interchange spine.
- The intellectual honesty discipline — `works` / `needs hardware` / `not implemented`, and the
  per-target `faithful` / `approximate` / `unsupported` fidelity scale. That is a judgement call
  about how to represent truth in documentation, and it is the most senior thing in the repo.
- **Every hardware debugging story.** Agents do not find out that a PYNQ overlay returns silence
  because a register-map key was dropped by an offset writer, or that the simulators were running a
  network of zeros because the CNL carried shape but not values, or that user-space could not
  program the FPGA fabric so provisioning had to self-promote to a root service. Those came from
  you reading logs against real silicon. This is the strongest material you have and it is
  irreducibly human.
- Knowing what to cut. The `Future / Planned` section that honestly says Kubernetes is unverified.

**The one real risk to manage:** an interviewer opens the repo and asks you to explain a file. Before
any technical interview, be able to walk through the CNL→IR→NIR pipeline, the deploy path end to
end, and three debugging war stories in depth. Those you genuinely know. You do not need to have
memorised the whole codebase — nobody has, in any company — but you must not be surprised by your
own architecture.

### 11.6 IP: the real position, the commit metadata, and what a waiver actually looks like

None of this is legal advice. Get a Dutch employment lawyer to look at the actual contract wording
once you have a concrete offer in hand. A few hundred euro against a platform you have spent two
years on is obviously worth it. What follows is the shape of the problem and what I would do.

#### The good part: your copyright position is clean

Every human commit in the repository is yours, across several machines and email addresses. The only
other committers are bots — `google-labs-jules`, `dependabot`, `copilot-swe-agent`, VS Code. No third
party holds copyright in your code, which means you are the sole rights holder and you can license
and relicense it however you want. That is the entire basis of your leverage and it is worth
protecting carefully.

#### The commit metadata: what it does and does not mean

231 commits are authored from a machine whose hostname is
`yoshimartodihardjo@MacBookPro.byod.rosendaal.internal.response.nl`, and six carry the author email
`yoshi@response.nl`. Looking at when they were made:

- They run from March 2026 to August 2026, so this is current and ongoing, not ancient history.
- They fall on weekdays only, overwhelmingly Mondays and Wednesdays, with none at weekends.
- They cluster between 09:00 and 16:00.

Read plainly, that is the pattern of work done on office days during office hours while connected to
the employer's network — because you only pick up that internal DNS suffix when you are on it. If
this ever became contested, that is what the other side would put on the table, so it is better that
you see it now than in a meeting.

Two things genuinely work in your favour, though.

**First, `byod` means bring your own device.** That is your own MacBook, not company hardware. The
hostname is just what the office network's DHCP server appended to your machine's name; it is
network metadata, not evidence of who owns the laptop. That removes the "he used our equipment"
argument almost entirely, and it is worth saying out loud if anyone ever raises it.

**Second, and much more importantly, Dutch copyright law asks the right question here.** Article 7
of the *Auteurswet* vests copyright in the employer only where the work was produced in the course of
the duties the employee was engaged to perform. You are employed as a mobile software developer
building cross-platform apps. A spiking-neural-network compiler and a neuromorphic hardware
deployment toolchain are not within those duties by any reading. The clock matters much less than
the nature of the work, and the nature of the work is squarely outside your job description.

So the strongest version of your position is not "I did it in my own time" — the timestamps make
that argument weaker than you would like. It is: *this was never within the work I was employed to
do, and Response has itself acknowledged in writing that it has nothing to do with their business.*
That is a good position. But it rests on the employment contract not containing a broader clause,
which is why you have to read it.

#### Can you change the commit metadata?

Technically yes, and you should mostly not.

**What you should do, today:** stop the problem growing.

```bash
git config user.email "yoshi.martodihardjo@gmail.com"
git config user.name "Yoshi Martodihardjo"
```

Run that inside the repository (not `--global`, so it only affects this project), and do the same in
each submodule. Then, optionally, add a `.mailmap` file at the repository root:

```
Yoshi Martodihardjo <yoshi.martodihardjo@gmail.com> <yoshimartodihardjo@MacBookPro.byod.rosendaal.internal.response.nl>
Yoshi Martodihardjo <yoshi.martodihardjo@gmail.com> <yoshi@response.nl>
Yoshi Martodihardjo <yoshi.martodihardjo@gmail.com> <yoshimartodihardjo@mbp-van-yoshi.home>
```

A `.mailmap` is git's standard, entirely legitimate mechanism for saying "all of these addresses are
the same person". It changes how `git log`, `git shortlog` and `git blame` display authorship without
touching history at all. It is the normal housekeeping any developer does after years of committing
from different machines, and it tidies the repository up for anyone browsing it.

**What you should not do: rewrite the history.** It is possible — `git filter-repo` will rewrite
every author and committer field — but it is the wrong move here, for four reasons.

1. **It does not change anything that matters.** Ownership turns on your contract and on the nature
   of the work. The string in the metadata is a piece of evidence about those facts, not the fact
   itself. Deleting the evidence does not change the underlying position by one inch.
2. ~~**The history is already out.**~~ **Corrected 2026-08-24: the repositories are private.** I had
   assumed they were public because the README links to a Releases page. They are not, which means
   the history is *not* distributed and a rewrite would actually be effective. This reverses the
   recommendation below — see §12.
3. **It looks like exactly what it is.** Quietly rewriting authorship metadata after someone points
   out that it might be contested is the single worst-looking thing you could do. In any dispute it
   converts a mild, defensible fact into a story about concealment. That is far more damaging than
   the metadata ever was.
4. **It would break things.** Every commit hash changes from the first rewritten commit onward. This
   repository has submodules with pinned commits, ADRs that reference commits, and a public release
   history. Rewriting it is a genuinely painful operation for no benefit.

**Corrected 2026-08-24.** Because the repositories are still private, the calculus above changes.
There is now an unimpeachable reason to rewrite — the history contains live credentials that must be
removed before first publication (see §12) — and the same pass also strips the employer hostname and
work email. Cleaning a repository before open-sourcing it is ordinary, expected housekeeping, and
doing it *before* publication is completely different from doing it after. Do it once, as part of
the pre-publication pass, and never touch the history again afterwards.

#### Is the WhatsApp exchange a waiver? (revised 2026-08-24)

The earlier version of this section raised three objections. One of them was that it was unclear
whether the person replying could bind Response B.V. That objection is now withdrawn: the
counterparty is the owner and director of Response, so his statements are attributable to the
company. He has also separately stated that the side-activities clause (*nevenwerkzaamheden*) only
bites where the side activity is a competing or overlapping product.

That is a much better position than I first described, and it is worth being precise about why.

**What the exchange now does establish.** Quite a lot:

- The owner of the company, speaking for the company, engaged with your statement that
  NeuroMorphicToolKit has nothing to do with Response's business, and did not dispute it.
- He *acted* on that understanding, and said so: "Daarom heb ik hem ook uit de projecten gehaald" —
  he removed the project from the projects section of a Response-branded CV precisely because it is
  not a Response project. Conduct consistent with a stated position is stronger evidence than the
  statement alone.
- Separately, he has articulated the company's own reading of the side-activities clause: it applies
  only to competing or overlapping products. Response does mobile and applied-AI work for clients.
  A neuromorphic SNN authoring and deployment toolchain neither competes with nor overlaps that. On
  his own stated test, you are clear.
- Dutch civil procedure has a free system of evidence, and courts routinely accept WhatsApp threads.
  A director's statement binds the company as a matter of attribution. This is real evidence, not
  colour.

Combined with Article 7 of the *Auteurswet* — which vests copyright in the employer only for work
falling within the duties the employee was engaged to perform, and building a spiking-network
compiler plainly is not the work of a mobile developer — your substantive position is strong.

**Why it is still not a waiver, and why that still matters.** Two reasons remain, and they are
structural rather than about trust.

*First, the subject matter.* Nobody in that exchange said anything about copyright, intellectual
property, or claims. Removing a line from a CV is a decision about how to market you to a client. It
is excellent circumstantial evidence about what everyone understood the project to be, but it is not
a statement that the company makes no claim to the rights, because that question never came up.

*Second, and this is the part that actually matters: people and companies change.* The protection
you have today is one friendly owner's informal reading of a written clause. If Response is ever
sold, restructured, or acquires a new director or board, the written clause is what governs — not
what the previous owner said in a chat in May. The same applies in reverse: when a future employer,
an investor, or an acquirer runs diligence on NMTK, their lawyer will ask for documentation, and
"my old boss said it was fine over WhatsApp" is an answer that stalls the deal even when it is
completely true. You are not formalising this because you distrust him. You are formalising it
because the document has to outlive the relationship.

There is one more technical wrinkle worth knowing. If Article 7 *never applied* — the likely case —
you have owned the copyright from the moment you wrote it, you need nothing from Response, and the
WhatsApp thread is simply helpful corroboration. But if someone later argued Article 7 *did* apply,
then Response would have owned it from the start, and getting it back would require a transfer,
which under Article 2(3) of the *Auteurswet* needs a signed deed. A WhatsApp message would not do.
You do not want to be arguing about which of those two regimes applies. One signed paragraph makes
the question moot either way, which is the whole point of getting it.

**Two small things worth doing while you are at it.**

- **Check the KvK extract.** If your boss is registered as the sole director with independent
  authority (*zelfstandig bevoegd*), his single signature binds the company and you need nothing
  else. If authority is joint or restricted, you need the other signature too. A KvK extract costs
  a few euro and takes two minutes, and it is the difference between a document that works and one
  that does not.
- **Still ask to see the final CV.** It sounds like NMTK came out of the projects list, which is
  exactly right. Just confirm it did not land somewhere else on a Response-branded document in a way
  that reads like Response work, because that is a document circulated to third parties saying the
  opposite of what you want.

#### What to ask for, and how to ask

One short paragraph, signed and dated. Ask now, while you are employed and on good terms — after you
hand in notice it becomes a negotiation instead of a formality. Given the relationship, keep the tone
completely administrative: this is paperwork for your own company's records, not a legal move.

Because he has already told you both things verbally, ask him to confirm both in the same note — the
ownership point and his reading of the side-activities clause. Something like:

> Beste [naam],
>
> Zoals we eerder besproken hebben: NeuroMorphicToolKit is een privéproject van mij dat losstaat van
> mijn werkzaamheden voor Response en geen overlap heeft met wat Response doet of aanbiedt. Je gaf
> zelf al aan dat de nevenwerkzaamhedenclausule alleen speelt bij een concurrerend of overlappend
> product.
>
> Ik wil dat graag even formeel vastleggen voor de administratie van mijn eigen onderneming — puur
> een formaliteit. Zou je onderstaande willen bevestigen en ondertekenen?
>
> *"Response B.V. verklaart dat het project NeuroMorphicToolKit (repository:
> github.com/…/NeuroMorphicToolKit) buiten de arbeidsovereenkomst met Yoshi Martodihardjo-Bink valt
> en geen onderdeel uitmaakt van de aan hem opgedragen werkzaamheden. Response B.V. maakt geen
> aanspraak op enige intellectuele-eigendomsrechten met betrekking tot dit project. Response B.V.
> bevestigt tevens dat het project niet concurreert met of overlapt met de producten of
> dienstverlening van Response B.V., en dat de nevenwerkzaamhedenclausule uit de
> arbeidsovereenkomst hieraan niet in de weg staat."*
>
> Datum en handtekening zijn voldoende. Dank alvast!

Two sentences of yours, one paragraph of his, a signature and a date. That is the entire job, and it
converts a good informal position into one that survives a change of ownership, a diligence process,
and a future employer's lawyer.

#### Structuring it from here

- **Put the copyright in your BV** by a signed deed of assignment (*akte van overdracht*) from you
  personally to the company, if it is not there already. Dutch law requires copyright transfers to be
  in writing; an implied or verbal transfer does not work. Then update the copyright line in
  `LICENSE` and the module headers to name the BV.
- **Keep the AGPL.** Because you are the sole rights holder you can dual-license: the public version
  stays AGPL, and anyone who wants different terms buys a commercial licence from your BV. A company
  can use AGPL software internally without difficulty, but the moment they expose a modified version
  to users over a network, section 13 requires them to publish their source — which almost no
  commercial buyer will do. That is precisely the pressure that makes them pay you. Do not let anyone
  talk you into MIT or Apache "to make adoption easier". That gives away the only leverage you have.

**When a future employer wants the platform, keep three separate deals separate:**

| What they want | What it is | What to do |
|---|---|---|
| Use it internally | Already permitted by the AGPL | Nothing. Let them. |
| Ship it in a product, or expose it to users | A commercial licence | Sell one from your BV. Recurring fee, not a one-off. |
| Own it | An acquisition | Price it as an acquisition. Never let this ride along inside an employment offer. |

**The clause you must get into any new employment contract** is a written prior-inventions carve-out,
attached as a schedule, naming NeuroMorphicToolKit and its repository URL explicitly as pre-existing
intellectual property owned by your BV and excluded from the assignment clause. This is completely
standard, every competent employer has seen one, and an employer who refuses is telling you something
useful. Ask for it before you sign, because afterwards you have no leverage at all.

The specific trap to avoid: you join Innatera or Axelera, the contract assigns everything you create
that "relates to the business", and a neuromorphic toolchain relates to their business by definition.
Without a carve-out, your continued work on your own platform starts flowing to them for free, and
the ownership of the existing work gets muddier than it needs to be. The carve-out is one page and it
is the highest-value piece of paperwork in this entire document.

Also worth knowing: since the EU Transparent and Predictable Working Conditions Directive was
implemented into Dutch law in August 2022, a blanket ban on side activities is unenforceable unless
the employer has an objective justification for it. That works in your favour.

### 11.7 The video you already have

You have the 3-minute video, and the framing in it is already correct — you open on the NC-NL
bottlenecks and position the toolkit as the answer. That is exactly the narrative in §6.1. Good.

Three cheap improvements, in priority order:

1. **Make an English version.** It is in Dutch. Axelera, Innatera, Snap and imec all operate in
   English and their hiring managers are largely not Dutch. Cheapest fix: English subtitles (burned
   in, or an SRT). Better: re-record the voiceover in English. Keep the Dutch version for NC-NL and
   Topsector ICT, who will like it precisely *because* it is Dutch.
2. **Cut a 60–90 second version** from the same footage. The 3-minute one is for people who already
   replied; the 90-second one goes in the first email.
3. **Add one card at the end**: the honest "what works today / needs hardware / not implemented"
   table. Ending on candour is a stronger close than ending on a feature.

One small correction for the script: you say targets include "SC-NeuroCore". Make sure the video's
claims line up exactly with the repository's support matrix — if a target is simulated rather than
running on silicon, say so on screen. The whole credibility play in §6.1 depends on the demo and
the docs never disagreeing.

### 11.8 Revised 90-day plan, cut to what fits your life

Everything in §8 that is not below is optional. This is roughly 12–15 hours total.

**This week (~4 hours)**
- Register an arXiv account with your JKU email (5 min, do it now so the domain is on file).
- Tag a release and connect the repo to Zenodo for a DOI (20 min).
- Read your Response B.V. contract for the IP clause; stop committing from employer hardware (30 min).
- Rewrite the CV per §6.4, fix the "Python: Basic" line (2 hours).

**Next two weeks (~6 hours)**
- English subtitles on the existing video, plus a 90-second cut (2–3 hours).
- Email NC-NL with the one-page brief (1 hour).
- Five thesis-supervisor emails (1 hour, they are near-identical).
- Apply to Axelera at **staff** level and to ASML/NXP; apply to Innatera as the field branch (1 hour).

**Then stop.** Everything else — the paper, the benchmark table, the naming fix, upstream anything —
waits for the thesis or for an employer who is paying you to do it. That is the correct call and
you were right to push back on the rest.

---

## 12. Going public: the decision, the blocker, and the framing (2026-08-24)

You asked whether to just make the repositories public, and said you're worried people will judge
the code quality without any explanation.

Short answer: **yes, go public — but not this week, and not before you fix a real problem I found
that has nothing to do with code quality.** The code-quality worry is the wrong thing to be afraid
of, and it is fixable with about an hour of writing. The credentials in your git history are not.

### 12.1 The blocker: live secrets are committed

A scan of the repository turns up the following, and this is not theoretical.

| What | Where | Status |
|---|---|---|
| `.env` containing `GRAFANA_ADMIN_PASSWORD` | Tracked at HEAD **and in history** | 43-character non-empty value — a real password |
| `.nmtk/deployment_secrets.json` | **In history**, commits `0947e3f5` and `618f4e2f` | Two 9-character values, consistent with real deployment passwords |
| Neither file is gitignored | `git check-ignore` returns nothing for both | They will keep getting re-committed |

Also present, at lower severity: the employer's internal DNS suffix
(`…byod.rosendaal.internal.response.nl`) in 231 commit author fields, and your work email in six more.
RFC1918 addresses like `192.168.2.90` are harmless — they mean nothing outside your LAN — but the
corporate hostname is a genuine, if minor, disclosure about someone else's network.

**Publishing is effectively irreversible.** The moment a repository goes public, GitHub's API and
event records, any fork, any clone, and third-party mirrors have it. Deleting the file the next day
does nothing. So this has to be fixed before the switch is flipped, not after.

**What "fixed" means, in order:**

1. **Rotate the credentials first.** Change the Grafana admin password and whatever the two values in
   `deployment_secrets.json` are, on every machine that uses them. Do this *before* the history
   rewrite, because rotation is what actually protects you — scrubbing the history only stops the
   next person from reading them.
2. **Add them to `.gitignore`** so they cannot come back:
   ```
   .env
   .nmtk/deployment_secrets.json
   *.pem
   *.key
   ```
   Keep `.env.example` tracked — that is the right pattern and you already have it.
3. **Scrub the history**, once, with `git filter-repo`. This is where the employer-metadata problem
   gets solved for free, because you can do both in the same pass:
   ```bash
   brew install git-filter-repo
   git filter-repo --invert-paths --path .env --path .nmtk/deployment_secrets.json \
                   --mailmap .mailmap
   ```
   with `.mailmap` containing the identity consolidation from §11.6. Run it in a fresh clone, verify
   the result, and only then force-push. Each submodule needs its own pass.
4. **Verify** before publishing:
   ```bash
   git log --all --pretty=format: --name-only --diff-filter=A | sort -u | grep -Ei '\.env|secret|\.pem|\.key'
   git log --all --format='%ae %ce' | sort -u
   ```
   Both should come back clean. Consider also running `gitleaks detect --no-git` over the working
   tree — neither `gitleaks` nor `trufflehog` is installed on this machine, so nothing has scanned
   the file *contents* for tokens, only the filenames.

This is the one piece of work in this document I would call genuinely non-optional. Budget two
hours, including submodules.

### 12.2 The code-quality worry: you are afraid of the wrong thing

Your instinct — "they'll look at it without any explanation and won't like the code" — is reasonable
but misdiagnosed, for three reasons.

**Almost nobody will read the code.** Recruiters do not. Hiring managers open the README, look at
the screenshots, and close the tab. NC-NL and Topsector ICT will never open GitHub at all. Academics
read the demo and the docs. The only population that reads source is an engineer preparing to
interview you, and that is one or two people, late in a process you have already been invited into.

**A private repository fails the claim entirely.** Right now, everything in this strategy rests on
"I built a platform that deploys spiking networks to real neuromorphic silicon." If the link 404s,
that is an unverifiable assertion in a cover letter, and unverifiable assertions in cover letters are
worth nothing. Public and imperfect beats private and immaculate by an enormous margin — the
downside case is "some of this is rough", and the private case is "there is no evidence any of this
exists".

**Rough code with honest documentation reads as senior. Polished code with silent gaps reads as
junior.** You already have the strongest version of this in the repository — `works` / `needs
hardware` / `not implemented`, and `faithful` / `approximate` / `unsupported`. Someone who ships a
document saying "this path does not work today" is signalling exactly the judgement that hiring
managers in this field cannot find. You are worried about the thing that is actually your best
asset, one level down.

There is also a real cost to waiting: it will never feel ready. This is a solo project with no
external deadline, and "not yet" is a decision that compounds for years.

### 12.3 The framing fix: one section in the README

The whole "no explanation" problem is solved by supplying the explanation. Add this near the top of
the README, under the hero. It takes an hour and it converts the weakness into the same credibility
signal as the support matrix.

> ## About this codebase
>
> NMTK is a solo project, built over two years alongside a full-time job and a full-time master's
> degree. A large share of the code was written by AI coding agents working against an architecture,
> module boundary set and test discipline I defined; the architecture, the hardware debugging and
> the verification are mine. That is how a project this broad was possible at all on the time
> available, and it is worth stating plainly rather than leaving you to infer it.
>
> **What that means for what you are about to read.** Coverage is uneven — the compiler pipeline,
> the deployment path and the hardware workers have had the most attention because they had to work
> against real silicon. Peripheral modules have had less. There is duplication in places where a
> slower pass would have factored things out. If I were writing this at my own pace it would be a
> smaller, tidier codebase, and it would have taken five years instead of two.
>
> **What I would point you at**, if you want to judge the engineering rather than the line count:
> the architecture decisions in `docs/ADR-claude/`, the support matrix and its three-term
> vocabulary, the NIR compilation path, and the hardware deployment code for Akida and PYNQ-Z2 —
> the last of which is where most of the hard-won knowledge in this repository lives.
>
> **What this is not.** It is not a product, it is not supported, and several paths marked
> `needs hardware` have never run on a device I own. The documentation says so per component,
> deliberately.

Two things this does. It pre-empts the criticism — nobody enjoys pointing out a flaw the author has
already named — and it demonstrates, in the README itself, the calibrated honesty you are selling.

### 12.4 A middle path, if you want one

You do not have to choose between fully public and fully private.

**Add specific people as read-only collaborators.** Free, instant, and reversible. You could invite
the five thesis supervisors and a hiring manager or two, get real reactions, then go public a month
later with whatever you learned. The costs: it adds friction for them (a GitHub account, an
invitation to accept), it kills the "it's open source" line, which is a large part of what makes you
interesting to NC-NL, and it means no Zenodo DOI.

I would use this only if you genuinely want feedback before publishing. For the job search it is
strictly worse than going public.

**A better version of "not ready": go public with a version number.** Tag it `v0.9.0`, describe it in
the release notes as a research preview, and let the version number carry the expectation-setting.
Nobody judges a `v0.x` the way they judge a `v1.0`.

### 12.5 The sequence

The YouTube description links to the repository, so publishing the video first would point everyone
at a 404. That fixes the order:

1. **Rotate the credentials.** (§12.1, step 1)
2. **`.gitignore`, then scrub the history** with `git filter-repo`, including submodules. Verify.
3. **Write the "About this codebase" section**, and put the "what works today" table at the top of
   the README.
4. **Check the licence position** — confirm no vendor SDK binaries are committed anywhere. The scan
   found no wheels, `.so`, `.deb` or bitstream files tracked, which is a good sign, but the
   submodules were not scanned.
5. **Make it public. Tag `v0.9.0`.**
6. **Connect Zenodo, tag a release, get the DOI.**
7. **Publish the video**, with a working link in the description.
8. **Then** send the emails.

Steps 1–2 are the only ones with any real risk attached. Everything after is reversible.

### 12.6 Deleting GitHub and moving to Gitea — evaluated (2026-08-24)

Proposal: delete the GitHub repositories, push to a self-hosted Gitea, delete the offending files,
and leave the project alone until after a job is secured, since the semester is starting.

**The single fact that simplifies all of this: rotating the two SSH passwords neutralises the
risk entirely.** Once those passwords are changed, the values sitting in git history are worthless
strings. There is then no security urgency at all, and everything else — history rewriting,
deleting GitHub, moving hosts — becomes a question of tidiness and publication readiness, not a
question of exposure. The Grafana value needs nothing; that service no longer exists in any compose
file.

So the real question is not "how do I make this safe", it is "do I want this public during the job
search". Those are separable decisions and should be made separately.

**Three options.**

| | Effort | What you get | What you give up |
|---|---|---|---|
| **A. Rotate, change nothing else** | ~30 min | Risk closed. Repo stays private on GitHub. Publication decision deferred to whenever it has a payoff. | Nothing, until you decide to publish. |
| **B. Rotate, move to Gitea, delete GitHub** | ~2–4 h + ongoing | No third-party bot access. Full control of the host. | GitHub presence, one-click Zenodo archiving, and an uptime obligation during a job search. |
| **C. Rotate, scrub history, publish** | ~4–6 h | The full strategy in this document, including the NC-NL open-source play. | Time you have said you do not have. |

**Recommendation: A.** Your constraint is time, and A costs almost none of it. B is more work than A
for a benefit you do not currently need — a self-hosted Gitea is not a portfolio, nobody at Innatera
or NC-NL is going to make an account on your server to look at your code, and a self-hosted service
that goes down mid-job-search is a liability rather than an asset. C is correct only if you want the
NC-NL conversation now, and that conversation keeps.

**Three corrections to the plan as stated.**

1. **Deleting the files does not remove them from history.** They are already untracked at HEAD, but
   every old commit still contains them. If you push the existing history to Gitea, the secrets go
   with it. The only ways around that are a `filter-repo` pass or starting a fresh history — and a
   fresh history throws away the ~1,100-commit record, which is itself portfolio evidence. Do not
   squash it away.
2. **Rotate regardless of where the code lives.** Three bot integrations — `google-labs-jules`
   (387 commits), `dependabot` and `copilot-swe-agent` — have had read access to a private
   repository containing live SSH passwords. Deleting the repository afterwards does not undo that.
3. **You already have the archive.** The mirror clones at `~/nmtk-backup-2026-08-24` hold complete
   history for all seven repositories. If the motivation for Gitea is "somewhere safe that is not
   GitHub", that is already satisfied. Gitea only earns its keep if you want a working remote to
   push to daily, which by your own account you will not be doing for months.

**What not publishing actually costs you.** Less than the earlier sections imply. The video carries
most of the weight — three minutes of working software is stronger evidence than a repository most
people would never open. The CV and the outreach templates work unchanged. What you lose is §5, the
NC-NL play, which genuinely depends on there being an open-source asset the alliance can point at.
That play is worth a lot, but it is not time-critical, and it is strictly better executed when you
have the capacity to follow it up.

**And when someone asks to see the code**, the honest answer is a good one:

> "It isn't public yet — there's cleanup I haven't had time for with the semester starting. Happy to
> give you read access if you want to look."

Thirty seconds to add a collaborator. That reads as busy and careful, not as evasive.

**So: rotate the two passwords, leave the repositories private on GitHub, and revisit publication
when you are employed or when the NC-NL conversation actually starts.** The `filter-repo` script and
the verification script stay where they are; they will still work in six months.

### 12.6 Revised plan: delete GitHub, move to Gitea, publish a frozen snapshot

You proposed deleting the GitHub repositories and submodules outright, pushing to a self-hosted
Gitea, dropping the bad files, and parking the project until after you have a job — restructuring
later, and only continuing it if a future employer wants it.

**On security, this is better than what I proposed.** Force-pushing a rewritten history leaves the
old commits reachable by SHA on GitHub until garbage collection, which is why GitHub's own guidance
is to contact Support afterwards. Deleting the repository removes the whole object store instead.
It is also *less* work than `filter-repo` across seven repositories and thirty branches. And it is
recoverable — GitHub keeps a deleted repository restorable for a window, so it is not a one-way
door.

Two things it does not fix, and one thing it breaks.

**Still required: rotate the two deployment secrets.** Deleting a repository does not un-read
anything. `google-labs-jules`, `dependabot` and `copilot-swe-agent` all had read access to a
repository containing live SSH passwords for your dev hosts. Rotation is the control; deletion is
hygiene. The Grafana value needs nothing — see §12.5 — because the service no longer exists in any
compose file.

**Still required if you ever publish: the identity rewrite.** Moving the repositories as-is carries
all 360 employer-domain commit fields to the new remote unchanged. The good news is that your plan
makes this *easier*, not harder: pushing cleaned history into a fresh, empty remote with no
collaborators, no forks and no open pull requests removes every reason I had for hesitating. The
`.mailmap` files are already committed and `scrub-history.sh` already exists.

**What it breaks: the portfolio.** This is the part to think about carefully. Everything in sections
2 through 6 rests on a stranger being able to click a link and see that this exists. A private
Gitea instance behind your home network is invisible to Innatera, invisible to a thesis supervisor,
and invisible to NC-NL. It also cannot be reached by anyone you send the video to, and it cannot
carry a Zenodo DOI. You would be removing the evidence at exactly the moment you need it.

**The resolution: "public" and "actively developed" are different things.**

You do not have to choose between publishing and parking. Publish a **frozen snapshot**, tagged
`v0.9.0`, with a README line saying it is a research preview and not under active development while
you finish your degree. Nobody expects maintenance from a `v0.x` research preview — an archived,
read-only public repository is a perfectly normal portfolio artifact, and arguably a cleaner one
than a repository with sporadic commits.

That gives you:

| | Canonical dev repo (Gitea, private) | Public snapshot |
|---|---|---|
| Where work happens | Yes, when you resume | No — frozen |
| Full history | Yes | Optional |
| Reachable by a recruiter or professor | No | Yes |
| Zenodo DOI possible | No | Yes |
| Maintenance expectation | None | None, if labelled |

**Two ways to build the snapshot.** Both are fine; pick by how much you care about the commit count.

*Option A — snapshot with no history (fastest, ~45 minutes).* A fresh `git init` on a clean export
of the tree. There is no history, so there are no secrets, no employer addresses, no committed
virtualenvs, no `current tasks/`, and no thirty stale agent branches — every problem in this section
disappears by construction rather than by surgery. You lose the "~1,100 commits over two years"
signal, which you can simply state in the README instead. Nobody counts commits.

*Option B — snapshot with cleaned history (~2 hours).* Run `scrub-history.sh`, then push the result
to the new public remote instead of force-pushing over the old one. You keep the commit record,
which is mild evidence of sustained work. The script is written and `git-filter-repo` is installed.

I would take Option A. You said you want to restructure anyway, you have no time this semester, and
a snapshot is the one path where "restructure later" costs you nothing now.

**One thing to decide while you are restructuring: collapse the submodules.** Six submodules means
six repositories to migrate, six sets of `.gitmodules` URLs to rewrite, six histories to clean and
six things that can drift out of sync. If you are restructuring anyway, a monorepo would remove all
of that permanently, and the module boundaries you care about are directory boundaries, not
repository boundaries. This is the single highest-value structural change available to you and it
is much cheaper to do during a migration than after.

**Order of operations.** Do not delete anything on GitHub until the new home has verified copies.

1. Rotate the two deployment secrets; move those hosts to key-based auth if convenient.
2. Stand up Gitea. Push all seven repositories to it. Verify by cloning fresh from Gitea and
   checking the submodule pointers resolve.
3. Confirm the backup at `~/nmtk-backup-2026-08-24` is intact and keep it until you are settled.
4. Build the public snapshot (Option A or B) as a *separate* new repository.
5. Only then delete the GitHub repositories.

The mirror backups mean step 5 is safe even if something is wrong, but the ordering still matters —
deleting last costs nothing and removes the failure mode entirely.

## 13. EU bodies: JRC, Chips JU, EIC, EPO, ESA (2026-08-25)

Assessed against your CV and your hard constraint of staying in the Netherlands.

### 13.1 The short version

| Body | Location relevant to you | Kind of work | Your realistic chance |
|---|---|---|---|
| **EPO** | **The Hague / Rijswijk** ✅ | Patent examination | **Genuinely realistic**, gated on degree field + languages |
| **ESA** | **ESTEC, Noordwijk** ✅ | Space engineering & research | **Contractor route realistic**; direct staff hard; neuromorphic roles want a PhD |
| **JRC** | Petten is NL, but does energy — AI/digital sits in Ispra (IT) and Seville (ES) ❌ | Policy-supporting research | Low, and geographically wrong |
| **Chips JU** | Brussels ❌ | Programme management | Low |
| **EIC** | Brussels ❌ | Programme management | Very low |

Three of the five fail your location constraint before anything else is considered.

### 13.2 EPO — the one worth taking seriously

The European Patent Office's second-largest site is in Rijswijk, about ninety minutes from
Etten-Leur. Average EPO salary in the Netherlands sits around **€99k–112k**, with the tax treatment
international organisations get. Against your current €65k that is the largest single jump available
anywhere in this document, and it is permanent, pensioned and in the Netherlands. They are recruiting
for October 2026 starts and building a 2027 talent pool now.

**What qualifies you:** EPC member-state nationality ✅, eight years of technical work ✅, and a
completed Master's — which is the first gate.

**Two real obstacles.**

*Degree field.* Their stated requirement is a Master's in **physics, chemistry, engineering or
natural sciences**. Computer science is not explicitly on that list, and your completed Master's is
in Applied Cognitive Psychology, which will not qualify. Whether the JKU **MSc Applied AI** counts
depends on how the diploma is worded and how EPO's recruiters classify it. **Ask them directly
before investing any effort** — a single email to EPO recruitment answers it, and the answer
determines whether this path exists for you at all.

*Languages.* You need C1 in one of English, French or German plus comprehension of the other two —
or C1 English plus a commitment to reach **B2 in both French and German** within a set period. Your
English is fine. The other two are a genuine multi-year commitment, and it is the thing most people
underestimate.

**What you would be giving up.** Patent examination is reading, searching prior art and writing
reasoned assessments. It is analytical, well paid, secure, and it is not building software. If you
land in the G06N classifications you would be reading neural-network patents all day, which is
adjacent to your interests but is emphatically not the same as working in the field. Go in with your
eyes open: this is a career-shape decision, not just a change of employer.

### 13.3 ESA — right place, right topic, wrong door

ESTEC in Noordwijk is ESA's technical heart and the largest ESA site, and the Advanced Concepts Team
genuinely works on your subject: spiking neural networks for onboard processing, retinomorphic
vision, and the fault tolerance of neuromorphic processors under radiation. On paper this is the best
topical fit of the five.

The problem is the entry routes:

- **Internal Research Fellow (PostDoc)** — the neuromorphic and bio-inspired positions at ESTEC are
  postdoctoral. They require a PhD. Closed to you.
- **Young Graduate Trainee** — e.g. the ACT's Graduate Trainee in Computational Neuroscience. You
  would technically qualify once the JKU MSc is finished, but it is a one-to-two-year traineeship
  aimed at people in their twenties, paying roughly €3.1k/month. That is a large pay cut and a
  step backwards at 34 with eight years behind you.
- **Staff engineer** — competitive, and normally wants space-domain experience you do not have.
- **Contractor at ESTEC** — this is the realistic door. A large share of the work at ESTEC is done by
  people employed by Terma, RHEA, Serco, Telespazio and similar, working on site. Pay is decent,
  the bar is engineering competence rather than a PhD, and it puts you physically inside the
  building. If ESA appeals, this is the route to research, not the careers page.

### 13.4 JRC, Chips JU, EIC — why these are not for you

**JRC** has a Dutch site at Petten, but it does energy and nuclear research; the AI and digital work
sits at Ispra in Italy and Seville in Spain. Right country, wrong topic; right topic, wrong country.
Research posts also lean heavily on doctorates.

**Chips JU** is a funding body in Brussels with a small staff who manage calls, evaluate proposals
and monitor consortia. The work is programme management, and the profile they hire wants EU-funding
literacy and deep semiconductor-programme experience.

**EIC** Programme Manager posts are marquee appointments on a DARPA-style model — former professors,
serial founders, people with a substantial public track record. The supporting project-officer roles
at EISMEA are administrative and in Brussels.

None of these three are building jobs, and none are in the Netherlands.

### 13.5 The thing that matters most here

**Everything we built this week is worth almost nothing to these five organisations.** EU bodies hire
on formal criteria: nationality, degree field, language certificates, structured selection
procedures. EPO runs an examination. A GitHub repository, a demo video and a Zenodo DOI barely
register. The portfolio-first strategy in sections 1 through 6 is optimised for startups, scale-ups
and research groups — people who can look at what you made and decide. Institutions cannot decide
that way; they decide on paperwork.

So treat this as a genuinely separate track with a separate CV, not as an extension of the same
campaign.

Two further practical points. **Both viable options are gated on finishing the JKU degree** — EPO
requires a completed Master's, and ESA's routes need it too. That is now a concrete financial reason
to finish. And **the timelines are long**: EPO cycles run six to twelve months, ESA similar. Neither
is an answer to a salary problem you want solved this year.

### 13.6 The better EU angle

If what appeals is working in the European deep-tech ecosystem rather than working *for* an EU
institution, the practical version is to be employed by a **Dutch organisation running EU-funded
work**. TNO, SURF, imec NL and the universities all run Horizon Europe and Chips JU projects. You
would be paid Dutch rates, live where you live, and sit inside the same programmes — without a
language requirement, a relocation, or a doctorate.

That is also exactly what NC-NL is trying to build. Their entire purpose is to assemble consortia
that can win national and European funding. Being known to them, which is what your email is for, is
a far more realistic route into EU-funded neuromorphic work than any of the five careers pages above.

---

## Sources

- [Neuromorphic Computing in the Netherlands — White Paper (Topsector ICT / Radboud, 2024)](https://www.ru.nl/sites/default/files/2024-11/whitepaper-neuromorphic-computing-final_pdf.pdf)
- [Roadmap Neuromorphic Computing 2025 (Topsector ICT / Birch)](https://topsector-ict.nl/)
- [Action Plan for Neuromorphic Computing 1.0 (Digital Holland, Nov 2025)](https://digital-holland.nl/assets/images/default/Action-Plan-Neuromorphic-Computing_2025-11-04-104644_oimj.pdf)
- [Neuromorphic Computing NL](https://nc-nl.nl/)
- [Launch of NC-NL — CogniGron, University of Groningen (Jan 2026)](https://www.rug.nl/research/fse/cognitive-systems-and-materials/news/newsitems/2026/260122-launch-of-nc-nl-accelerates-the-future-of-brain-inspired-technology?lang=en)
- [Launch of Neuromorphic Computing NL — Radboud University](https://www.ru.nl/en/research/research-news/launch-of-neuromorphic-computing-nl-the-netherlands-takes-the-next-step-towards-energy-efficient-ai-and-digital-autonomy)
- [The Netherlands aims to lead brain-inspired computing development — IO+](https://ioplus.nl/en/posts/the-netherlands-aims-to-lead-brain-inspired-computing-development)
- [Innatera careers](https://www.innatera.com/careers/) · [Innatera on Ashby](https://jobs.ashbyhq.com/innatera)
- [Axelera AI careers](https://axelera.ai/careers)
- [CogniGron research centre](https://www.rug.nl/research/fse/cognitive-systems-and-materials/?lang=en) · [RUG vacancies](https://werkenbij.rug.nl/en/all-vacancies/)
- [Grai Matter Labs acquired by Snap — Bits&Chips](https://bits-chips.com/article/grai-matter-labs-quietly-snapped-up-by-snap/)
- [The NeuroBench framework — Nature Communications (2025)](https://www.nature.com/articles/s41467-025-56739-4) · [arXiv:2304.04640](https://arxiv.org/abs/2304.04640)
