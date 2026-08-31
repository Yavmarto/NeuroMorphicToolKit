#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uCurrentTimeMs;
uniform float uFadeDuration;   // ms over which a spike fades (default 20)
uniform sampler2D uSpikes;     // R=x_norm, G=y_norm, B=birth_time_norm
uniform float uSpikeCount;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 col = vec3(0.02, 0.04, 0.08);

  int count = int(uSpikeCount);
  for (int i = 0; i < 4096; i++) {
    if (i >= count) break;
    float tx = (float(i) + 0.5) / max(uSpikeCount, 1.0);
    vec4 s = texture(uSpikes, vec2(tx, 0.5));
    float sx = s.r;
    float sy = s.g;
    float birthMs = s.b * uCurrentTimeMs;
    float age = uCurrentTimeMs - birthMs;
    float alpha = max(0.0, 1.0 - age / max(uFadeDuration, 1.0));

    vec2 delta = (uv - vec2(sx, sy)) * uSize;
    float dist = length(delta);
    float glow = exp(-dist * dist * 0.04) * alpha;
    col += vec3(0.2, 0.7, 1.0) * glow;
  }

  fragColor = vec4(min(col, vec3(1.0)), 1.0);
}
