// PYNQ results for the Review step: the overlay verdict, what the board
// returned, and the verification pass.
//
// The verdict card stays because it explains the rest — a network that only
// just fit the overlay is the context for whatever the board reported. What is
// new is everything below it: before this, the verdict *was* the whole result,
// which read as if PYNQ deploy had run something when it had not.

// What the board returned, read the way overlay-v2 actually encodes it.
//
// The stream is one word per output neuron per timestep, so its *length* is
// fixed by the network and the run — never a spike count. Reporting the length
// said "Output spikes: 10" for a run in which nothing fired, and printing the
// stream verbatim under "Spiking output neurons" listed ten zeros.

// One precision for board timings everywhere they are shown.
//
// Switches to milliseconds above 1 ms because a DMA round trip on the Z2 runs
// into the thousands of microseconds, where the extra digits carry no meaning.
String formatPynqMicroseconds(double microseconds) {
  if (microseconds >= 1000) {
    return '${(microseconds / 1000).toStringAsFixed(2)} ms';
  }
  return '${microseconds.toStringAsFixed(1)} µs';
}
