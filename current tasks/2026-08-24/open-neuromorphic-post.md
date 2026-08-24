# Open Neuromorphic — Discord post and the two better asks behind it

Open Neuromorphic is a ~3,100-member global community for open-source neuromorphic computing, led by
an elected executive committee (2026: Justin Riddiough, Alexandre Marcireau, Effiong Blessing). They
promote and maintain exactly the stack you built on — snnTorch, Brian, GeNN, BindsNET, **NIRTorch**,
AEStream, Faery — and they run four things: Workshops, **Student Talks**, Hacking Hours, and a
**Community Peer Review (ONR)** programme for "transparent community review and recognition" of
open-source projects.

That last one matters. You are asking for feedback on a project and on its value as a portfolio
piece. ONM has a formal programme for the first and a stage for the second.

## Why this audience is different from NC-NL

NC-NL will never open your repository. **This community wrote half your dependency tree.** NIR, the
interchange format your whole compiler spine rests on, is their work. Several people in that Discord
are authors of snnTorch, Sinabs, Tonic and NIR itself. They will understand what you built in about
fifteen seconds, and they will have opinions.

Three consequences:

1. **Credit NIR explicitly and early.** You are standing on their work. Saying so is both true and
   the correct social move.
2. **Your NeuroBench module is an integration, not a collision — but it is not finished, so keep it
   understated.** The executor genuinely wraps upstream: `neurobench_executor.py` imports
   `neurobench.benchmarks.Benchmark`, `neurobench.datasets` (WISDM, MackeyGlass, PrimateReaching,
   SpeechCommands), `neurobench.metrics.static`, `neurobench.metrics.workload`,
   `NeuroBenchModel` and `MFCCPreProcessor`. **But it is not wired end-to-end from CNL Studio**: the
   Setup benchmark dropdown only stores a selection, Review's benchmark result field is never
   populated, and the bridge sends CNL text rather than the trained checkpoint, NIR weights, test
   set or Akida bundle. So it is an in-progress standardised benchmarking workbench, not a shipped
   feature — which is exactly how the post now describes it. Do not let anyone leave that thread
   thinking otherwise; this audience would find out in an afternoon. There is no name collision to
   apologise for either way; a cosmetic rename to **NeuroBench UI** (their capitalisation) when you
   finish it is enough.
3. **Credit it in `THIRD_PARTY_NOTICES.md`** before publishing. You are consuming their package;
   AGPL can consume it fine, but the attribution should be explicit.
4. **The video has to be in English.** Yours is Dutch. Subtitles at minimum, an English voiceover
   ideally. A Dutch-narrated video posted to an international Discord will simply not be watched.

## Three asks, in increasing order of value

**A. The Discord post — feedback now.** Costs an hour. Text below.

**B. A talk — do this.** ONM runs both Student Talks and expert-led Workshops, and records them to
their YouTube channel. You qualify for either: you are an MSc student *and* a software engineer with
eight years of experience and a working hardware integration. Pitch it as a workshop or a practitioner
talk rather than a student talk — the material is a hands-on walkthrough of getting a trained network
onto real silicon, which is workshop content, and the framing costs you nothing while placing you
correctly. A recorded ONM talk is a genuine, linkable credential seen by exactly the people you want
— including engineers at Innatera and SynSense — and it costs you a deck you have largely already
built as a video. Relative to effort this is the highest-return item available to you.

**C. Community Peer Review (ONR) — after you publish.** A formal, transparent review of your
open-source project by people who know the field. That is the code-quality feedback you actually
want, from qualified reviewers, and "reviewed by Open Neuromorphic" is a line you can put on a CV.
Gated behind the public snapshot, so it comes later — but it is the reason to publish rather than
park.

## The Discord post

Check `#introductions` first if you have not posted before. Then post **once** in whichever of
`#showcase` / `#projects` / `#general` fits — do not cross-post, this community notices.

> Hi all — before anything else, a genuine thank you. This project only exists because of work done in this community: NIR and NIRTorch, snnTorch, Brian2, PyNN, Sinabs, Rockpool, Lava, and NeuroBench. I've spent six months building a proof of concept on top of all of it, and I'd like your opinion on the result before I publish.
>
> 🎥 3-minute demo: [video URL]
>
> What it is: design a spiking network visually or in controlled English, train it once in snnTorch, then run the same trained network through NIR on several platforms — including a real Akida card. Benchmarking will run through the NeuroBench harness from inside the app; that part is still being wired up. The backend provisions itself onto a server, and a complete experiment and workspace (model, weights, results) is shareable in one piece so someone else can replicate it via the Hub.
>
> Two things I'd genuinely value:
>
> **1. Technical feedback, especially on the NIR round-trip.** I hit a lot of *silent* failures getting networks onto targets: a spec that carried shape but not trained weights, so simulators cheerfully ran a network of zeros; time constants discretised differently per backend; a dropped register-map key that made the FPGA emit nothing while every readiness check stayed green. I'd like to know which of these are known, which are my own bugs, and whether anyone has systematically measured what survives a NIR round trip. I'm considering making that my MSc thesis.
>
> **2. A question for people already in the field.** I'm a software engineer with eight years of experience moving into neuromorphic from outside it — I built this alongside a full-time job, so I'm coming at it as a practitioner rather than a researcher. For someone making that move, what would you actually want to see in a project like this, and what's missing that would make it genuinely useful rather than just a demo?
>
> Full disclosure: solo project, will be open source, built fast, with a large share of the code written by AI agents working to an architecture and test discipline I set. The architecture, the hardware debugging and the verification are mine. Happy to be told where that shows.

**Three copy fixes applied to your final text** (wording only, no content changed):
- "runs … from inside the app in the future" → "will run … ; that part is still being wired up".
  A present-tense verb with "in the future" attached reads as a mistake to a native speaker, and it
  is the one sentence in the post making a status claim, so it needs to be unambiguous.
- "open source in the future" → "will be open source". Same tense clash, smaller.
- Removed a double space in "built fast,  with".

**Optional closing line, if you want to open the Student Talk door:**

> Also — if a hands-on walkthrough of the hardware-deployment side would be useful as a workshop or talk, I'd be glad to give one.

## Notes on tone and cost

- **Do not mention looking for a job.** You only want to work in the Netherlands, so there is
  nothing to gain and it would change how the post is read. Leave it out entirely. Your experience
  still belongs in there — "software engineer with eight years of experience, built alongside a
  full-time job" is context for the question you are asking, not a pitch, and it stops people
  answering you as though you were a first-year student.
- **State the real status before they watch.** Naming what does not work, up front, in a community
  that will test it, is the difference between a good first impression and a bad one. The three
  working runtimes plus Akida is a genuinely respectable claim; eight backends would not have
  survived first contact.
- **Lead with the video, not the preamble.** Discord readers scroll.
- **The AI disclosure stays.** You are asking people to review a codebase; they are entitled to know
  how it was produced, and being found out later is far worse than saying it. Say it plainly, once,
  without apologising — the sentence about architecture and hardware debugging being yours is the
  part that matters.
- **Budget the follow-up.** A post to 3,100 people creates an obligation to reply for two or three
  days. Post on a week where you have two free evenings, not the week your semester starts. If you
  cannot respond, do not post yet — an abandoned thread is worse than no thread.
- **You will get criticism.** Some of it will be about the AI-generated code, some about scope,
  some about reinventing things that exist. Answer the technical points, thank people for the rest,
  argue with nobody. The community is generally constructive and the ones who engage seriously are
  worth listening to.
