You are reproducing the 'lif_snntorch.ipynb' notebook inside the NeuroStudio (neuro_toolkit) application by following this EXACT numbered checklist, in order. Use the action history below to figure out which steps you've already completed, then perform the next uncompleted one. Do not skip ahead and do not repeat a step that already succeeded.

Canvas: Model
1. Navigate to the Model Canvas (stepper tab '2. Model').
2. Click the icon whose tooltip/content is 'NIR Importer' to open its side panel.
3. Inside that panel, click the button labeled 'Load .nir'.
4. A native file picker will open as a SEPARATE window you cannot see or click into — do not try. Instead: press key 'cmd+shift+g', then type the exact text '/Users/yoshimartodihardjo/NeuroMorphicToolKit/paper/01_lif/lif_norse.nir', then press key 'Return', then press key 'Return' again to confirm the file selection.
5. Wait a couple of seconds, then confirm the Model canvas now shows a real graph (no longer empty).

Canvas: Eval
6. Navigate to the Eval Canvas (stepper tab '4. Eval').
7. Click the '+' icon in the bottom toolbar (tooltip 'Add') to open the 'Add Node' picker.
8. Click the tile labeled 'Spike Generator'. Configure it: n_neurons=1, n_timesteps=100, pattern=isi_regular, isi_period=10, seed=42.
9. Click the '+' icon again, then click the tile labeled 'State Reset'.
10. Click the '+' icon again, then click the tile labeled 'Forward Pass'. Set its eval_mode = true.
11. Click the '+' icon again, then click the tile labeled 'Spike Rate Logger'.
12. Drag from the Spike Generator node's output port to the Forward Pass node's input port (use the 'drag' action with from_id/to_id set to those two ports' element IDs).
13. Drag from the State Reset node's model-output port to the Forward Pass node's model-input port.
14. Drag from the Forward Pass node's spikes-output port to the Spike Rate Logger node's spikes-input port. Leave any other Forward Pass outputs (membrane, model) unconnected.
15. Click 'Run Eval'.

Results Step: Dynamics Tab
16. After the eval run completes, navigate to the Results step and open the Dynamics tab.
17. Confirm the Spike Raster panel shows the output spike times.
18. Confirm the Membrane Voltage Trace panel shows the LIF membrane potential over 100 timesteps.
19. Export results to CSV via the export button.
