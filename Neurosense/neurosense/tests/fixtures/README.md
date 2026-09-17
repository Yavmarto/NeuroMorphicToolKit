# NeuroSense Session Fixtures

`canonical_emg_session.hdf5` is the checked-in canonical artifact used by the
session, replay, and export tests. It models the flagship workflow with:

- 2-channel forearm EMG labels: `flexor`, `extensor`
- `emg_prosthetic` preset metadata
- canonical root attrs, `raw`, `filtered`, `timestamps`, `markers`, and `spikes`
- `OpenBCI Cyton` recorded as the target future validation board, still marked
  `experimental`
