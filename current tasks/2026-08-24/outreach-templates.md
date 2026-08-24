# Cover letters, emails and opening messages

Placeholders in `[brackets]`. Every template is short on purpose — a hiring manager at a 40-person
chip company reads three paragraphs, not a page.

## Principles

1. **Lead with their problem, not your history.** Every one of these companies has the same
   bottleneck: they have hardware nobody knows how to program. Say that first.
2. **One link, not three.** The 90-second video. Everything else is in the CV.
3. **Ask for a conversation, not a job.** Lower bar, higher hit rate, and it works even when there
   is no open vacancy.
4. **Never send a generic letter.** The middle paragraph must name something specific about them.
   If you cannot write that sentence, do not send the mail.
5. **Language.** English by default for Innatera, Axelera, Snap, imec, SynSense and any research
   institute. Dutch for NC-NL, Topsector ICT and Dutch family-owned engineering firms. When in
   doubt, English — nobody is offended by it, and half these teams have no Dutch speakers.

---

## Paragraph bank

Reusable building blocks. Assemble rather than rewrite.

**Hook (EN)**
> Neuromorphic Computing NL keeps naming the same bottleneck: the hardware exists, but setting it up, getting drivers and simulators running, and moving a model onto a chip costs weeks. I hit that wall myself, so I built the missing layer.

**Hook (NL)**
> Neuromorphic Computing NL benoemt telkens hetzelfde knelpunt: de hardware is er, maar het opzetten ervan, drivers en simulators werkend krijgen en een model daadwerkelijk op een chip krijgen kost weken. Ik liep daar zelf tegenaan en heb de ontbrekende laag gebouwd.

**Proof (EN)**
> NeuroMorphicToolKit takes a spiking network from a visual or controlled-English specification, through NIR, to inference on real silicon — a BrainChip Akida AKD1000 and a PYNQ-Z2 FPGA, plus eight simulation frameworks. It is open source, and the documentation states plainly which paths work and which need hardware I do not have.

**Proof (NL)**
> NeuroMorphicToolKit brengt een spiking netwerk van een visuele of gecontroleerd-Engelse specificatie, via NIR, naar inferentie op echte hardware — een BrainChip Akida AKD1000 en een PYNQ-Z2 FPGA, plus acht simulatieframeworks. Het is open source, en de documentatie zegt expliciet welke paden werken en welke hardware vereisen die ik niet heb.

**Who I am (EN)**
> I am a software engineer with eight years of professional delivery experience and a background in cognitive psychology, currently finishing an MSc in Applied AI. I bring production engineering discipline to a field that mostly runs on research code.

**Ask (EN)**
> Would you have half an hour to talk? I am not attached to a specific vacancy — I would rather understand where your tooling actually hurts.

**Ask (NL)**
> Zou je een half uur hebben om te praten? Ik ben niet gebonden aan een specifieke vacature — ik hoor liever waar het bij jullie qua tooling echt schuurt.

---

## A. Neuromorphic chip company — Innatera, Axelera, Snap, SynSense (EN)

**Subject:** `Built an open-source SNN toolchain — 30 minutes?`

> Dear [name],
>
> Neuromorphic Computing NL keeps naming the same bottleneck: the hardware exists, but setting it up, getting drivers and simulators running, and moving a model onto a chip costs weeks. I hit that wall myself, so I built the missing layer.
>
> NeuroMorphicToolKit takes a spiking network from a visual or controlled-English specification, through NIR, to inference on real silicon — a BrainChip Akida AKD1000 and a PYNQ-Z2 FPGA, plus eight simulation frameworks. 90-second demo: [video URL]. Source: github.com/Completed-Spoon-6/NeuroMorphicToolKit.
>
> [**Specific paragraph — rewrite per company.** Innatera: *"You have shipped the first commercial neuromorphic microcontroller. The hard part now is not the silicon, it is the hundredth developer getting a model onto it without your engineers in the room — which is exactly the problem I have spent two years on."* Axelera: *"Metis is shipping, which means the work has moved to conversion, quantization and evaluation tooling. That is the part of my toolchain I would put in front of you first."* Snap Eindhoven: *"Your Eindhoven site owns AI tools. That is the team name for what I built."*]
>
> I am a software engineer with eight years of professional delivery experience and a background in cognitive psychology, currently finishing an MSc in Applied AI. I bring production engineering discipline to a field that mostly runs on research code.
>
> Would you have half an hour? I am not attached to a specific vacancy — I would rather understand where your tooling actually hurts. CV attached either way.
>
> Best regards,
> Yoshi Martodihardjo-Bink
> +31 6 55585355

---

## B. Research institute or infrastructure — SURF, imec, TNO (EN)

**Subject:** `Open-source reference implementation for neuromorphic benchmarking`

> Dear [name],
>
> The Action Plan for Neuromorphic Computing describes a market-driven application lab whose deliverables are benchmark methodologies, easier access to neuromorphic hardware, demonstrators, and open developer toolsets that lower the barrier to adoption.
>
> I have built a working version of most of that, on my own, and released it under AGPL. NeuroMorphicToolKit provisions a containerised backend onto a server over SSH, lets a user author a spiking network visually or in controlled English, compiles it through NIR to eight frameworks, deploys it to an Akida AKD1000 or a PYNQ-Z2, benchmarks it, and publishes the complete workspace so someone else can reproduce it. 90-second demo: [video URL].
>
> I am not claiming it is finished — the documentation rates every component `works`, `needs hardware` or `not implemented`, and is deliberately blunt about the gaps. But it exists, it runs, and it may be a useful starting point rather than a blank sheet.
>
> [**Specific paragraph.** SURF: *"The Action Plan names the SURF Emerging Technology Platform as the model for this lab, which is why I am writing to you first."* imec: *"µBrain and SENeCA both need a path for third parties to actually run something on them."* TNO: *"I understand you are a partner in NC-NL and I would like to understand where this could plug in."*]
>
> Would a half-hour conversation be useful? I would rather find out where this is wrong than assume it is right.
>
> Best regards,
> Yoshi Martodihardjo-Bink

---

## C. Dutch deep tech and semicon — ASML, NXP, Thales, Sioux, Demcon, Prodrive

### English

**Subject:** `Senior engineer, edge AI and hardware deployment tooling`

> Dear [name],
>
> I am a lead software engineer with eight years of delivery experience, applying for [role]. What I would draw your attention to first is not on my employment record: over the past two years I designed and shipped NeuroMorphicToolKit, an open-source platform that compiles spiking neural networks and deploys them to physical hardware — a BrainChip Akida accelerator and a Zynq-7000 FPGA, including bitstream provisioning and the DMA and register-map interface. 90-second demo: [video URL].
>
> That project is where I learned the things [company] actually needs: getting a model from a training framework onto constrained hardware, measuring what the conversion costs in accuracy and latency, and building tooling other engineers can use without a manual.
>
> [**Specific paragraph — one sentence about their product line and why you care.**]
>
> I am based in Etten-Leur, Dutch national, available for [full-time / 32–36 hours]. I would welcome a conversation.
>
> Best regards,
> Yoshi Martodihardjo-Bink

### Nederlands

**Onderwerp:** `Senior engineer — edge AI en hardware-deployment tooling`

> Beste [naam],
>
> Ik ben lead software engineer met acht jaar ervaring en solliciteer op [functie]. Wat ik graag als eerste noem staat niet op mijn cv-regel: de afgelopen twee jaar heb ik NeuroMorphicToolKit ontworpen en gebouwd, een open-source platform dat spiking neural networks compileert en uitrolt naar fysieke hardware — een BrainChip Akida-versneller en een Zynq-7000 FPGA, inclusief het inladen van de bitstream en de DMA- en registerinterface. Demo van 90 seconden: [video-URL].
>
> In dat project heb ik precies geleerd wat bij [bedrijf] speelt: een model vanuit een trainingsframework op beperkte hardware krijgen, meten wat die conversie kost aan nauwkeurigheid en latency, en tooling bouwen die andere engineers zonder handleiding kunnen gebruiken.
>
> [**Specifieke alinea — één zin over hun productlijn en waarom die je interesseert.**]
>
> Ik woon in Etten-Leur, ben Nederlands staatsburger en beschikbaar voor [fulltime / 32–36 uur]. Ik ga graag in gesprek.
>
> Met vriendelijke groet,
> Yoshi Martodihardjo-Bink

---

## D. Thesis supervisor (academic) — Shahsavari, Corradi, Frenkel, Yousefzadeh, Dolas (EN)

Keep this one to four short paragraphs. Academics get a lot of mail.

**Subject:** `MSc thesis proposal — cross-target fidelity of NIR-based SNN deployment`

> Dear Dr. [name],
>
> I am a second-year MSc Applied AI student at JKU Linz, and a working senior software engineer. I am looking for a thesis supervisor and I think our interests overlap closely.
>
> Over the past two years I built NeuroMorphicToolKit, an open-source toolchain that compiles spiking networks through NIR and deploys them to real hardware — an Akida AKD1000 and a PYNQ-Z2 — as well as eight simulation frameworks. 90-second demo: [video URL].
>
> Building it, I kept hitting a problem nobody seems to have measured: what actually survives the NIR round trip. I found networks that arrived on the target carrying shape but not trained weights, time constants discretised differently per backend, and a dropped register-map key that made an FPGA return silence while every readiness check stayed green. I would like to turn that into a thesis: one trained network, exported to every target, measured for accuracy, spike-count and latency delta, with a systematic taxonomy of the silent failure modes.
>
> [**Specific paragraph — one sentence on why this person.** e.g. *"Your work on [X] is the closest thing I have found to the problem I am describing, which is why I am writing to you rather than to a general address."*]
>
> Would you be open to a short conversation? I am employed full-time, so this would be a part-time external thesis, and I would deliver working software rather than a prototype that stops at submission.
>
> Best regards,
> Yoshi Martodihardjo-Bink

---

## E. NC-NL / Topsector ICT ecosystem introduction (NL)

Not a job application. Send this to `nc-nl@digital-holland.nl`. Attach the one-page brief, not the CV.

**Onderwerp:** `Open-source referentie-implementatie voor de Application Lab — aanbod`

> Beste [naam / NC-NL],
>
> Het Action Plan beschrijft een market-driven application lab met vier concrete opdrachten: benchmarkmethodieken, toegang tot neuromorphic hardware, demonstrators, en open developer-toolsets die de drempel tot adoptie verlagen.
>
> Ik heb daar de afgelopen twee jaar in mijn eigen tijd een werkende versie van gebouwd en onder AGPL vrijgegeven. NeuroMorphicToolKit installeert een gecontaineriseerde backend op een server via SSH, laat een gebruiker een spiking netwerk visueel of in gecontroleerd Engels ontwerpen, compileert dat via NIR naar acht frameworks, rolt het uit naar een Akida AKD1000 of een PYNQ-Z2, benchmarkt het, en publiceert de complete workspace zodat een ander het kan reproduceren. Demo van drie minuten: [video-URL].
>
> Ik claim niet dat het af is — de documentatie geeft per onderdeel aan of het `works`, `needs hardware` of `not implemented` is, en is bewust expliciet over de gaten. Maar het bestaat, het draait, en het is wellicht een bruikbaar vertrekpunt in plaats van een leeg vel.
>
> Ik bied het graag aan de alliantie aan. Zou iemand een half uur hebben om te kijken of hier iets in zit? Ik zoek geen opdracht of financiering; ik wil vooral weten of dit het veld verder helpt.
>
> Met vriendelijke groet,
> Yoshi Martodihardjo-Bink
> [telefoon] · [GitHub]

---

## F. LinkedIn connection note / short opening message

Under 300 characters for a connection request. These are for cold-messaging a named engineer or
manager rather than applying through a portal.

**EN, connection request**
> Hi [name] — I built an open-source toolchain that compiles spiking networks through NIR and deploys them to Akida and PYNQ hardware. Given what [company] is working on I would value your view on it. 90-second demo in my profile. Happy to keep it to a short call.

**EN, follow-up after they accept**
> Thanks for connecting. Short version: NeuroMorphicToolKit takes an SNN from a visual spec through NIR to inference on real silicon — Akida AKD1000 and a PYNQ-Z2 — plus eight simulators. Video: [URL]. I am a senior engineer moving into this field and I am trying to work out where the real tooling gaps are. Would half an hour be worth your time?

**NL, connection request**
> Hoi [naam] — ik heb een open-source toolchain gebouwd die spiking networks via NIR compileert en uitrolt naar Akida- en PYNQ-hardware. Gezien waar [bedrijf] mee bezig is ben ik benieuwd naar je blik erop. Demo van 90 seconden staat in mijn profiel.

---

## G. Follow-up (once, after 8–10 working days)

Never more than three sentences, and never apologetic.

**EN**
> Hi [name] — following up on the note below, in case it got buried. Still happy to talk if it is useful; equally happy to hear it is not a fit. Either answer helps me.

**NL**
> Hoi [naam] — even een korte herinnering aan onderstaand bericht, mocht het ondergesneeuwd zijn. Ik ga graag in gesprek, maar een "niet passend" is ook prima. Beide antwoorden helpen me.

---

## Sending checklist

- [ ] Named person in the greeting, not "Dear Sir/Madam" or "Beste heer/mevrouw"
- [ ] The company-specific paragraph is actually written, not left as a placeholder
- [ ] Video URL is in the mail, and it plays
- [ ] CV attached as PDF, not .docx
- [ ] The word "passionate" does not appear
- [ ] Under 250 words
