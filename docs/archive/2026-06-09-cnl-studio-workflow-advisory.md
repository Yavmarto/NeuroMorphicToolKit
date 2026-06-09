# CNL Studio Workflow Advisory

Date: 2026-06-09

## Summary

The current CNL Studio workflow is directionally correct, but it mixes two different product stories:

1. The notebook is presented as a main workflow step.
2. Training and execution results are already handled inside Studio itself.

That makes the notebook feel more important than it actually is for most users, while the real "outcome" moment is split across later steps. The flow should end on results, not on the notebook.

## Current Workflow Assessment

The current flow is:

1. Pick data and targets.
2. Create the model or architecture with CNL, NIR, or canvas.
3. Open generated target notebook(s) and edit where needed.
4. Run or train.
5. Deploy.

This mostly makes sense if the notebook is treated as an editable artifact generated from the designed architecture. It makes less sense if the notebook is supposed to be the main place where users understand whether the model worked.

Why:

- Data and target selection should happen first.
- Architecture definition should happen before any generated artifact.
- A notebook can be useful as a target-specific editable package.
- But the notebook is not the clearest end-user destination for judging success.
- The user's real question at the end is not "what code was generated?" but "did the model train, what does it look like, and is it ready to deploy?"

## Recommendation

The better workflow is:

1. Setup
   Select dataset and target platform(s).
2. Architecture
   Define the network in CNL, NIR, or canvas.
3. Notebook
   Generate the notebook package for the selected targets and allow optional edits.
4. Run / Train / Deploy
   Execute training or target-specific run flows and allow deployment actions from the same execution phase.
5. Results
   Show the final model outcome, training behavior, generated artifacts summary, and deployment readiness.

This keeps the notebook before execution, which is correct if it remains an editable package generated from the architecture. But it moves the emotional and practical endpoint to a final Results step.

## Why This Ordering Is Better

### Notebook should not be the end

Putting the notebook at the end would make the last user-facing destination a technical artifact instead of the product outcome. That is backwards for most users.

The notebook is best understood as:

- a generated working package
- an advanced editing surface
- a target-specific handoff artifact

It is not the clearest final checkpoint for the guided Studio flow.

### Execution and deployment belong near each other

After architecture is defined and the optional notebook package exists, users want to do the real work:

- run
- train
- inspect immediate status
- export
- deploy

Those actions are part of one operational phase. They should feel connected, not scattered.

### Results should be the final step

The final step should answer:

- Did training succeed?
- How did loss or performance evolve?
- What model was produced?
- What target artifacts are ready?
- Is the model deployable?

That is the true end of the workflow.

## Visualization Placement

The training and model visualization should live primarily in the final Results step.

That step should include:

- animated training loss curve
- animated or progressively revealed model summary
- run status and final metrics
- target-by-target readiness summary
- generated artifacts summary
- deployment outcome or deploy readiness state

This is the best place because the visualizations are not just part of running. They are the explanation of the outcome.

## Animation Guidance

The results step should feel alive, not static.

Recommended behavior:

- Animate the training curve as epochs arrive or replay it on completion.
- Reveal final metrics with short staged transitions instead of dumping all values at once.
- Animate deploy readiness badges or target completion states as each target resolves.
- If a model topology preview is shown, use subtle entrance animation or progressive highlighting rather than a static snapshot only.

The goal is not decorative motion. The goal is to make the result legible and to help users understand sequence, improvement, and completion.

## Product Framing

The workflow should communicate this story:

1. I chose my data and targets.
2. I designed the model.
3. I received a generated editable package.
4. I ran or trained the model and optionally deployed it.
5. I reviewed the final outcome in a dedicated results surface.

That story is clearer than ending on a notebook, because it optimizes for end-user understanding rather than for the intermediate technical artifact.

## Final Recommendation

Do not move the notebook to the end.

Instead:

- keep the notebook after architecture generation
- treat it as an editable generated package
- combine run, train, and deploy into the operational phase
- add a dedicated final Results step
- place animated training and model visualization in that final Results step

This gives Studio a clearer guided workflow and makes the last screen the one users actually care about.
