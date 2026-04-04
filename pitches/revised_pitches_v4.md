# Revised NMTK Developer Program Pitches — v4

---

## BrainChip — Akida

**Subject: Developer Program Application — Building Akida Integration into NMTK**

Neuromorphic computing has enormous practical potential, but adoption is still slowed by a fragmented toolchain. Neuroscientists, hardware engineers, and software developers are often solving adjacent parts of the same problem with separate tools, separate assumptions, and very little interoperability.

To address that, I am building the **NeuroMorphicToolkit (NMTK)**: a unified, actively developed cross-platform desktop application that brings these workflows together through a local microservice architecture, with a Flutter frontend orchestrating Docker/Python backends. NMTK currently includes modules for plain-English to SNN translation (NeuroCNL), sensory spike encoding (Neurosense), hardware interfacing (Neurochip), and performance benchmarking (Neurobench). The goal is to make it materially easier for researchers and developers to move from model design to edge deployment without stitching together a stack of disconnected repositories.

I am an independent software developer and founder based in the Netherlands, with 8 years of professional mobile software development experience. I hold a Master's degree in Psychology and am currently completing a second Master's in Applied A.I. at JKU Linz alongside a full-time job. I am building NMTK deliberately and long-term, because neuromorphic computing is the field I am moving into professionally. My background gives me a useful combination of biological framing, product thinking, and production-grade software engineering.

BrainChip's Akida processors are exactly the kind of ultra-low-power edge target that NMTK's **Neurochip** and **Neurobench** modules are being built to support. I can design the surrounding integration architecture without access, but I cannot build a credible Akida deployment and benchmarking path without the MetaTF SDK and real hardware. Model conversion, deployment validation, and on-chip performance feedback all depend on platform access. That is the gap I am trying to close through your developer program. The codebase is not yet public; I am keeping it private until it reaches the quality bar I want to stand behind. My aim is to make Akida a first-class deployment target in NMTK from the beginning.

Thank you for considering my application. I would welcome the opportunity to build and validate Akida support properly.

---

## SynSense — Speck

**Subject: Developer Program Application — Building Speck Integration into NMTK**

Neuromorphic computing has enormous practical potential, but adoption is still slowed by a fragmented toolchain. Neuroscientists, hardware engineers, and software developers are often solving adjacent parts of the same problem with separate tools, separate assumptions, and very little interoperability.

To address that, I am building the **NeuroMorphicToolkit (NMTK)**: a private, actively developed cross-platform desktop application that brings these workflows together through a local microservice architecture, with a Flutter frontend orchestrating Docker/Python backends. NMTK currently includes modules for plain-English to SNN translation (NeuroCNL), sensory spike encoding (Neurosense), hardware interfacing (Neurochip), and performance benchmarking (Neurobench). The goal is to make it materially easier for researchers and developers to move from model design to edge deployment without stitching together a stack of disconnected repositories.

I am an independent software developer and founder based in the Netherlands, with 8 years of professional mobile software development experience. I hold a Master's degree in Psychology and am currently completing a second Master's in Applied A.I. at JKU Linz alongside a full-time job. I am building NMTK deliberately and long-term, because neuromorphic computing is the field I am moving into professionally. My background gives me a useful combination of biological framing, product thinking, and production-grade software engineering.

SynSense's Speck platform is precisely the kind of target that NMTK's **Neurosense** and **Neurochip** modules are being designed around. There is a hard limit to how far I can take event-based sensing and deployment support without access to the Sinabs/Rockpool SDK and physical Speck hardware. The event pipeline, timing behavior, hardware configuration, and real deployment constraints all need feedback from the actual device. Joining your developer program would give me the missing piece required to turn a sensible software architecture into a real, validated integration. The codebase is not yet public; I am keeping it private until it reaches the quality bar I want to stand behind. My goal is to make deploying bio-constrained SNNs to hardware like Speck far more approachable for developers.

Thank you for considering my application. I would welcome the opportunity to build Speck support seriously and correctly.

---

## SpiNNcloud Systems — SpiNNaker

**Subject: Developer Program Application — Building SpiNNaker Integration into NMTK**

Neuromorphic computing has enormous practical potential, but adoption is still slowed by a fragmented toolchain. Neuroscientists, hardware engineers, and software developers are often solving adjacent parts of the same problem with separate tools, separate assumptions, and very little interoperability.

To address that, I am building the **NeuroMorphicToolkit (NMTK)**: a private, actively developed cross-platform desktop application that brings these workflows together through a local microservice architecture, with a Flutter frontend orchestrating Docker/Python backends. NMTK currently includes modules for plain-English to SNN translation (NeuroCNL), sensory spike encoding (Neurosense), hardware interfacing (Neurochip), and performance benchmarking (Neurobench). The goal is to make it materially easier for researchers and developers to move from model design to edge deployment without stitching together a stack of disconnected repositories.

I am an independent software developer and founder based in the Netherlands, with 8 years of professional mobile software development experience. I hold a Master's degree in Psychology and am currently completing a second Master's in Applied A.I. at JKU Linz alongside a full-time job. I am building NMTK deliberately and long-term, because neuromorphic computing is the field I am moving into professionally. My background gives me a useful combination of biological framing, product thinking, and production-grade software engineering.

SpiNNaker's massively parallel architecture is a natural fit for NMTK's **NeuroCNL** translation layer and **Neurobench** benchmarking workflows. I can prepare export and orchestration scaffolding without direct access, but I cannot validate routing behavior, timing semantics, execution constraints, or realistic benchmark behavior without access to the platform itself. That access is the missing piece between architectural intent and a trustworthy integration. The codebase is not yet public; I am keeping it private until it reaches the quality bar I want to stand behind. I am applying because I want SpiNNaker support to be part of NMTK early, and because hands-on work with the platform is important to the expertise I am building in this field.

Thank you for considering my application. I would value the chance to build SpiNNaker support on a real technical footing.

---

## Prophesee — Metavision

**Subject: Developer Program Application — Building Metavision Integration into NMTK**

Neuromorphic computing has enormous practical potential, but adoption is still slowed by a fragmented toolchain. Neuroscientists, hardware engineers, and software developers are often solving adjacent parts of the same problem with separate tools, separate assumptions, and very little interoperability.

To address that, I am building the **NeuroMorphicToolkit (NMTK)**: a private, actively developed cross-platform desktop application that brings these workflows together through a local microservice architecture, with a Flutter frontend orchestrating Docker/Python backends. NMTK currently includes modules for plain-English to SNN translation (NeuroCNL), sensory spike encoding (Neurosense), hardware interfacing (Neurochip), and performance benchmarking (Neurobench). The goal is to make it materially easier for researchers and developers to move from model design to edge deployment without stitching together a stack of disconnected repositories.

I am an independent software developer and founder based in the Netherlands, with 8 years of professional mobile software development experience. I hold a Master's degree in Psychology and am currently completing a second Master's in Applied A.I. at JKU Linz alongside a full-time job. I am building NMTK deliberately and long-term, because neuromorphic computing is the field I am moving into professionally. My background gives me a useful combination of biological framing, product thinking, and production-grade software engineering.

Prophesee's event-based sensors are one of the clearest real-world counterparts to biological vision, and **Neurosense** is being developed with exactly this class of hardware in mind. It is intended to support both conventional and event-based sensory streams and encode them into spike trains for downstream SNN processing. The part I cannot do properly on my own is the platform-specific integration work: the Metavision SDK, event format handling, device behavior, and timing characteristics all need real access to the ecosystem. Building against documentation alone would leave the integration untested and fragile. The codebase is not yet public; I am keeping it private until it reaches the quality bar I want to stand behind. Event-based vision is one of the areas in which I most want to build real depth, and your developer program would let me do that in a serious way.

Thank you for considering my application. I would welcome the opportunity to build meaningful Metavision support into NMTK.

---

## Intel Labs — Loihi / Lava

**Subject: Developer Program Application — Building Lava/Loihi Integration into NMTK**

Neuromorphic computing has enormous practical potential, but adoption is still slowed by a fragmented toolchain. Neuroscientists, hardware engineers, and software developers are often solving adjacent parts of the same problem with separate tools, separate assumptions, and very little interoperability.

To address that, I am building the **NeuroMorphicToolkit (NMTK)**: a private, actively developed cross-platform desktop application that brings these workflows together through a local microservice architecture, with a Flutter frontend orchestrating Docker/Python backends. NMTK currently includes modules for plain-English to SNN translation (NeuroCNL), sensory spike encoding (Neurosense), hardware interfacing (Neurochip), and performance benchmarking (Neurobench). The goal is to make it materially easier for researchers and developers to move from model design to edge deployment without stitching together a stack of disconnected repositories.

I am an independent software developer and founder based in the Netherlands, with 8 years of professional mobile software development experience. I hold a Master's degree in Psychology and am currently completing a second Master's in Applied A.I. at JKU Linz alongside a full-time job. I am building NMTK deliberately and long-term, because neuromorphic computing is the field I am moving into professionally. My background gives me a useful combination of biological framing, product thinking, and production-grade software engineering.

Intel Labs is pushing the frontier of neuromorphic scale with Loihi 2, and Lava is the right software abstraction layer for what NMTK's **NeuroCNL** and **Neurosim** modules are meant to support: translating higher-level models into validated deployment paths. Lava being open is extremely helpful, and I can build around that. The real blocker is Loihi hardware access. Without it, I cannot validate compilation, execution timing, resource constraints, or on-chip behavior in a way that would make the integration credible. The codebase is not yet public; I am keeping it private until it reaches the quality bar I want to stand behind. Getting Loihi integration right matters to me both for NMTK and for the hands-on foundation I am building for a long-term career in this space.

Thank you for considering my application. I would welcome the opportunity to build Loihi support on real hardware rather than in the abstract.

---

## Innaterra — Ultra-Low Power Edge AI

**Subject: Developer Program Application — Building Innaterra Integration into NMTK**

Neuromorphic computing has enormous practical potential, but adoption is still slowed by a fragmented toolchain. Neuroscientists, hardware engineers, and software developers are often solving adjacent parts of the same problem with separate tools, separate assumptions, and very little interoperability.

To address that, I am building the **NeuroMorphicToolkit (NMTK)**: a private, actively developed cross-platform desktop application that brings these workflows together through a local microservice architecture, with a Flutter frontend orchestrating Docker/Python backends. NMTK currently includes modules for plain-English to SNN translation (NeuroCNL), sensory spike encoding (Neurosense), hardware interfacing (Neurochip), and performance benchmarking (Neurobench). The goal is to make it materially easier for researchers and developers to move from model design to edge deployment without stitching together a stack of disconnected repositories.

I am an independent software developer and founder based in the Netherlands, with 8 years of professional mobile software development experience. I hold a Master's degree in Psychology and am currently completing a second Master's in Applied A.I. at JKU Linz alongside a full-time job. I am building NMTK deliberately and long-term, because neuromorphic computing is the field I am moving into professionally. My background gives me a useful combination of biological framing, product thinking, and production-grade software engineering.

Innaterra's mission around ultra-low-power, bio-inspired edge AI maps directly onto what NMTK is trying to make easier: the last mile from model to hardware. NMTK's **Neurochip** and **Neuro-Dream-Hand** modules are being built around applied hardware orchestration and robotics-adjacent deployment, and your silicon is exactly the kind of target they are meant to serve. The limits here are hardware-specific: power envelopes, memory constraints, compilation targets, and deployment behavior cannot be meaningfully validated without access to the SDK and platform details. The codebase is not yet public; I am keeping it private until it reaches the quality bar I want to stand behind. This is not a one-off experiment for me. Applied neuromorphic hardware is the direction I am heading professionally, and I would like to build that expertise with companies that are actually moving the field forward.

Thank you for considering my application. I would welcome the opportunity to build a real Innaterra integration into NMTK.
