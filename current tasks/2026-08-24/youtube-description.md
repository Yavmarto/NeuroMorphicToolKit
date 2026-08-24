# YouTube description — NMTK demo (3 min)

Trimmed ~15% from the first draft. Chapters are a separate optional block at the bottom.

Title suggestions (keep stable once published):
- NL: `NeuroMorphicToolKit — spiking neural networks bouwen en uitrollen naar neuromorphic hardware`
- EN: `NeuroMorphicToolKit — build, train and deploy spiking neural networks to neuromorphic hardware`

---

## Dutch

NeuroMorphicToolKit (NMTK) — spiking neural networks bouwen, trainen en uitrollen naar neuromorphic hardware, vanuit één app.

Neuromorphic Computing NL benoemt een aantal knelpunten in het veld: hardware opzetten is moeilijk, drivers, simulators en remote servers werkend krijgen kost veel tijd, en er is weinig standaardisatie en gebruiksvriendelijke software. NMTK is mijn antwoord daarop.

In deze demo van drie minuten:

• Backend-installatie — server-IP invoeren, op deploy klikken; de app regelt SSH, containers en verbinding
• Setup — pipeline vanaf nul, workspace laden van computer of remote server, of een gedeelde workspace ophalen via NeuroHub
• Design — netwerken bouwen door modulaire nodes te verbinden, de onderliggende Python per node bekijken, en eigen custom nodes maken en delen
• Trainen, en ondertussen doorwerken op je telefoon met dezelfde functionaliteit als op desktop
• Analyse — neuron-activaties op het ruimtelijke raster, populatiefrequenties, spike rasters over de tijd, en gewichtsevolutie per epoch
• Deploy — readiness-check van de chip, quantisatie, en de bundle uitrollen naar een Akida-chip op je server
• Review — evaluatie per target, en meerdere targets naast elkaar vergelijken
• Publiceren van complete workspaces, inclusief modellen en benchmarkresultaten, op NeuroHub, voor reproduceerbaarheid

Wat werkt vandaag, en wat niet

NMTK installeert of configureert géén fysieke neuromorphic hardware. Hardwarepaden vereisen een fysiek apparaat plus vendor-SDK, en die zitten niet in de container images. De repository documenteert per onderdeel of het works, needs hardware of not implemented is, en per exporttarget hoe getrouw de conversie is (faithful, approximate, unsupported).

Onder de motorkap

Flutter-app voor macOS, Windows, Linux, Android en iOS. Python/FastAPI-backend. Een CNL→IR→NIR compiler als ruggengraat, met integraties richting snnTorch, Nengo, Rockpool, Sinabs, Brian2, Lava, PyNN/SpiNNaker en Akida.

Open source onder AGPL-3.0-or-later: https://github.com/Completed-Spoon-6/NeuroMorphicToolKit

Gemaakt door Yoshi Martodihardjo-Bink. Vragen, feedback en samenwerking welkom.

#neuromorphic #spikingneuralnetworks #edgeai #snn #akida #nir #opensource #neuromorphiccomputing

---

## English

NeuroMorphicToolKit (NMTK) — build, train and deploy spiking neural networks to neuromorphic hardware, from a single app.

Neuromorphic Computing NL has highlighted several bottlenecks in the field: hardware is hard to set up, getting drivers, simulators and remote servers working takes a lot of time, and there is little standardisation or user-friendly software. NMTK is my answer to that.

In this three-minute demo:

• Backend install — enter your server's IP, click deploy; the app handles SSH, containers and the connection
• Setup — build a pipeline from scratch, load a workspace from your machine or a remote server, or pull a shared one from NeuroHub
• Design — build networks by connecting modular nodes, inspect the Python behind each node, and create and share custom nodes
• Training, and picking up on your phone with the same functionality as on desktop
• Analysis — neuron activations on the spatial grid, population firing rates, spike rasters over time, and weight evolution per epoch
• Deployment — chip readiness check, quantization, and rolling the bundle out to an Akida chip on your server
• Review — evaluation per target, and side-by-side comparison across targets
• Publishing complete workspaces, models and benchmark results included, to NeuroHub for reproducibility

What works today, and what doesn't

NMTK does not install or configure physical neuromorphic hardware. Hardware paths need a physical device plus its vendor SDK, and those are not in the container images. The repository documents, per component, whether something works, needs hardware or is not implemented, and rates each export target's fidelity as faithful, approximate or unsupported.

Under the hood

Flutter app for macOS, Windows, Linux, Android and iOS. Python/FastAPI backend. A CNL→IR→NIR compiler as the spine, with integrations targeting snnTorch, Nengo, Rockpool, Sinabs, Brian2, Lava, PyNN/SpiNNaker and Akida.

Open source under AGPL-3.0-or-later: https://github.com/Completed-Spoon-6/NeuroMorphicToolKit

Built by Yoshi Martodihardjo-Bink. Questions, feedback and collaboration welcome.

#neuromorphic #spikingneuralnetworks #edgeai #snn #akida #nir #opensource #neuromorphiccomputing

---

## Optional: chapters

Adds length, but improves retention and makes the video skimmable. Known anchors from the
recording: backend dialog ~0:04, weights view ~1:51, runtime 3:00. Fill the rest.

```
0:00 Knelpunten in neuromorphic computing
0:__ Backend installeren en verbinden
0:__ Setup: workspace laden of ophalen via NeuroHub
0:__ Design: netwerken bouwen met modulaire nodes
0:__ Node-source en custom nodes
1:__ Training starten, doorwerken op mobiel
1:51 Analyse: raster, spike rasters, gewichtsevolutie
2:__ Deploy naar de Akida-chip
2:__ Review: targets vergelijken
2:__ Publiceren op NeuroHub
```
