#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // canvas size in pixels
uniform float uNeuronCount; // total number of neurons
uniform float uDuration;   // simulation window in ms
uniform float uTime;       // current playback time in ms (for cursor)
uniform sampler2D uSpikes;  // spike texture: R=neuron_idx/neuronCount, G=time_ms/duration
uniform float uSpikeCount;   // number of valid spikes in texture

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // Background: dark navy
  vec3 col = vec3(0.04, 0.06, 0.12);

  // Grid lines every 10% of neuron rows
  float gridFreq = 0.1;
  float grid = step(0.995, mod(uv.y / gridFreq, 1.0));
  col = mix(col, vec3(0.12, 0.15, 0.22), grid * 0.5);

  // Playback cursor
  float cursorX = uTime / max(uDuration, 1.0);
  float cursorLine = step(0.997, 1.0 - abs(uv.x - cursorX) * uSize.x);
  col = mix(col, vec3(0.2, 0.8, 1.0), cursorLine * 0.6);

  // Spikes — iterate texture
  int count = int(uSpikeCount);
  for (int i = 0; i < 4096; i++) {
    if (i >= count) break;
    float tx = (float(i) + 0.5) / max(uSpikeCount, 1.0);
    vec4 spk = texture(uSpikes, vec2(tx, 0.5));
    float ny = spk.r;   // neuron_idx / neuronCount  [0,1]
    float tx2 = spk.g;  // time / duration           [0,1]

    float dx = abs(uv.x - tx2) * uSize.x;
    float dy = abs(uv.y - ny) * uSize.y;
    float r = sqrt(dx * dx + dy * dy);
    float glow = exp(-r * 0.5);
    col += vec3(0.1, 0.9, 0.7) * glow * 0.8;
  }

  fragColor = vec4(col, 1.0);
}
