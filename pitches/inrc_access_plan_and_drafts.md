# INRC Access Plan and Email Drafts

## 1. Feasibility Assessment: Is it realistic?
**Yes, it is highly realistic.** The Intel Neuromorphic Research Community (INRC) actively looks for applicants who aren't starting from scratch but have already built models and used their software framework (Lava). NMTK's current architecture has perfectly positioned you for this request.

According to their checklist, you already meet the heavy technical requirements:
- **Built and tested an SNN:** Yes, you have the `Neuro-Dream-Hand` project using trained SNN parameters.
- **Implemented the model in Lava:** Yes, NMTK has a built-in `LoihiExporter` that translates NeuroCNL SNN graphs into Lava's `LIF` and `Dense` processes (`lava-nc`).
- **Evaluated in simulation:** Yes, your deployment script (`step13_loihi_deployment.py`) already targets the CPU emulator (`Loihi2SimCfg`) and compares the simulated hardware latency/energy.

You have essentially completed their entire prerequisite list for utilizing physical hardware. The logical missing piece is access to the Neuromorphic Research Cloud to test your existing pipeline and auto-generated scripts on actual hardware using `Loihi2HwCfg`.

---

## 2. Situation A: Direct Application (NMTK Core Maintainer)

### Strategy
Apply directly on behalf of the NeuroMorphicToolKit (NMTK) project. Frame NMTK as an open-source development tool aimed at expanding the accessibility of neuromorphic computing, explicitly highlighting your existing Lava integration. Request Neuromorphic Research Cloud (vLab) access to validate your backend integrations.

### Email Draft

**To:** [INRC Contact Email]
**Subject:** INRC Membership & Cloud Access Request: Hardware Validation for NeuroMorphicToolKit (NMTK)

**Body:**
Dear INRC Team,

I am writing to apply for membership in the Intel Neuromorphic Research Community (INRC) and to request access to the Neuromorphic Research Cloud (vLab) for my open-source software project, the NeuroMorphicToolKit (NMTK).

NMTK is a unified cross-platform desktop framework designed to bridge neuroscience, software engineering, and edge robotics. We focus heavily on hardware-agnostic compilation and interoperability, streamlining how models are deployed to edge devices.

I am seeking access to the Research Cloud specifically to benchmark and validate our automated SNN-to-Lava compilation toolchain. Looking at your hardware request evaluation checklist, we have already completed the prerequisites:
1. **Model Building & Lava Implementation:** We have implemented a native `LoihiExporter` in our translation layer (NeuroCNL) that successfully parses network graphs into Lava's `LIF` and `Dense` processes.
2. **Simulation Evaluation:** We have applied this pipeline to an applied robotics use-case (a robotic hand controller) and have evaluated the SNN's performance locally using Lava's CPU emulator (`Loihi2SimCfg`), resulting in accurate energy and latency baseline estimates.

Our primary roadblock is validating our compiled workflows and evaluating these metrics on actual Loihi hardware using `Loihi2HwCfg`. Cloud access would allow us to finalize this backend integration and ensure that SNN artifacts exported by NMTK are fully optimized for the Loihi 2 infrastructure.

I have attached a brief overview of our project architecture and our Lava integration testing plan. Please let me know the required next steps or proposals needed to formalize this INRC application.

Thank you for your time and review.

Best regards,
[Your Name]
Maintainer, NeuroMorphicToolKit
[Link to GitHub / Project]

---

## 3. Situation B: JKU Endorsement (Academic/Institutional Route)

### Strategy
Software vendors and hardware labs typically strongly prefer—or require—dealing with established academic institutions due to IP, export controls, and NDAs. Applying through Johannes Kepler University (JKU) significantly increases your authority and the likelihood of approval. In this scenario, you pitch NMTK as your academic project/research at JKU.

### Email Draft

**To:** [INRC Contact Email]
**CC:** [Your JKU Supervisor/Adviser]
**Subject:** INRC Membership & Cloud Access Request: JKU Research on Cross-Platform Neuromorphic Compilers

**Body:**
Dear INRC Team,

My name is [Your Name], and I am a researcher/student at Johannes Kepler University (JKU), studying under the guidance of [Professor/Advisor Name if applicable]. I am writing to formally apply for INRC membership and request access to the Neuromorphic Research Cloud (vLab).

My research focuses on cross-platform SNN interoperability, primarily driven through the development of the open-source NeuroMorphicToolKit (NMTK). NMTK aims to lower the barrier for neuromorphic application deployment by providing automated compilation from high-level models into hardware-specific execution processes.

To date, we have successfully developed our framework locally and met Intel's hardware evaluation prerequisites:
1. **Lava Implementation:** We built an internal compiler that maps biological neural networks into Lava's native `LIF` and `Dense` processes.
2. **Simulation Validation:** We have evaluated an edge-robotics model (SNN controlling a robotic hand) on local hardware using the Lava CPU simulator. This generated stable latency constraints and energy use baselines.

The next critical phase of my research at JKU is to benchmark our automated compiler against the physical capabilities of Loihi 2. We are requesting Neuromorphic Research Cloud access to test our `Loihi2HwCfg` deployment pipeline. This hands-on validation ensures that our auto-generated Lava scripts meet routing and configuration requirements on real Intel hardware.

I believe our workflow will be a valuable contribution to the broader neuromorphic community. I have CC'd my advisor, [Advisor's Name], for institutional verification. We are happy to review any necessary agreements required to join the INRC.

Thank you for your consideration and support of academic research.

Best regards,
[Your Name]
Johannes Kepler University (JKU)
[Link to Research / NMTK]
