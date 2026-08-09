# NMTK End-to-End Demo Script

**Flow**: CNL Studio → Train (SNNTorch) → Deploy (Akida) → Benchmark (NeuroBench) → Share (Neurohub)

> **Say the bold line. Do the action in _italics_.**

---

## 1 — Open CNL Studio and load the pipeline

**"This is NeuroMorphicToolKit — one app for the full neuromorphic workflow. Let's start by opening CNL Studio."**

_Click **CNL Studio** in the launcher sidebar._

**"I'll load a workspace I already have — a spiking network trained on MNIST."**

_In the **Setup** step → **Workspace** section → click **Load from hub** (or **Load from disc**)._
_Select your workspace. The model canvas loads automatically._

**"Here's the network on the canvas — an input layer, two linear layers with LIF neurons, and an output. 784 inputs, 256 hidden units, 10 outputs. Simple, clean, and ready to train."**

_Click the **Model** step tab so the canvas is visible._

---

## 2 — Train with SNNTorch

**"In Setup I've already selected SNNTorch as the training target and Akida for deployment. Let me hit Play."**

_Click the **Run** step tab, then click the **Play** button._

**"The app generates the training notebook automatically — no code to write. You can see the loss dropping and accuracy climbing live."**

_Point to the **Live Metrics Dock** showing epoch curves._

**"Training finishes. Roughly 92% test accuracy on MNIST, just like the reference result. The Akida Exporter node also ran — it quantized the trained weights and packaged them into an Akida bundle."**

_Wait for the **Complete** (green checkmark) state on the Run step._

---

## 3 — Deploy to Akida hardware

**"Now let's put this on the physical BrainChip Akida card."**

_Click the **Results** step tab → click **Deploy to Hardware** → select the **Akida** tab._

**"The host is already paired. I click Check Readiness — SDK is installed, card is detected, we're green."**

_Click **Check Readiness**. Status dot turns green._

**"Use Latest Bundle — the app finds the bundle the training step just produced and submits it."**

_Click **Use Latest Bundle**._

**"You can watch it go through validation, quantization, conversion, mapping, and evaluation on the card. When it finishes, it shows Hardware Verified."**

_Point to the **Hardware verified** badge._

**"One sample on silicon — I pick index 7, hit Run Model Sample."**

_Set **Sample index** to `7`, click **Run Model Sample**._
_Point to the prediction panel showing `Prediction: 7 "seven" · correct`._

**"Prediction correct, running on real neuromorphic hardware."**

---

## 4 — Benchmark with NeuroBench

**"Now let's get standardized benchmark numbers. I'll open NeuroBench."**

_Click **NeuroBench** in the launcher sidebar._

**"Configure and Run — I select the MNIST FCN benchmark, target Akida, and hit Run Benchmark."**

_In the **Configure & Run** tab → set **Benchmark** to `MNIST FCN` → **Target** to `Akida` → click **Run Benchmark**._

**"While that runs — you can see active jobs in the bar at the bottom."**

_Point to the **Active Jobs Bar**._

**"Results: accuracy, latency per sample, energy per inference in microjoules. This is what you'd report in a paper."**

_Click the **Results & History** tab. Point to the metrics table._

**"I can also compare against published baselines side by side."**

_Click the **Comparisons** tab._

---

## 5 — Share to Neurohub

**"Last step — publish this to Neurohub so anyone in the community can reproduce it."**

_Click **Neurohub** in the launcher sidebar → click **Share to Hub**._

**"I give it a slug, a version, a short description, tag it with snntorch and akida, attach the bundle, and share."**

_Fill in `Slug`, `Version`, `Description`, `Tags` → click **Pick file** → select the `.akida-bundle.zip` → click **Share to Hub**._

**"Done. It's live on the hub — the model, the benchmark results, everything. Anyone can load it with one click from the Hub tab in Setup."**

_Point to the success snackbar, then navigate to **Explore Feed** showing the published card._

---

## Closing line

**"That's the full workflow — from a network spec to a trained spiking model, running on neuromorphic silicon, benchmarked, and shared — all inside one app, no terminal required."**
