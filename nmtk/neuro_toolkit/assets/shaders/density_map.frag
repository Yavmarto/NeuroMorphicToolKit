#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D uDensityGrid; // 1D row-major flattened
uniform vec2 uGridDim;          // width, height

out vec4 fragColor;

// simple plasma/magma colormap approximation
vec3 magma(float t) {
  return vec3(
    clamp(t * 3.0, 0.0, 1.0),
    clamp(pow(t * 1.5, 2.0), 0.0, 1.0),
    clamp(t * 2.0, 0.0, 0.5) + t * 0.5
  );
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // convert screen UV to grid cell index
  float col = floor(uv.x * uGridDim.x);
  float row = floor(uv.y * uGridDim.y);
  float idx = row * uGridDim.x + col;
  float totalCells = uGridDim.x * uGridDim.y;

  vec3 color = vec3(0.04, 0.06, 0.12); // background

  if (idx < totalCells) {
    float tx = (idx + 0.5) / totalCells;
    vec4 val = texture(uDensityGrid, vec2(tx, 0.5));
    float density = val.r;

    if (density > 0.001) {
      color = mix(color, magma(density), density * 0.8 + 0.2);
    }
  }

  // Smooth interpolation over cell edges
  vec2 gridUv = fract(uv * uGridDim);
  float edge = max(
    smoothstep(0.95, 1.0, gridUv.x) + smoothstep(0.05, 0.0, gridUv.x),
    smoothstep(0.95, 1.0, gridUv.y) + smoothstep(0.05, 0.0, gridUv.y)
  );
  color = mix(color, vec3(1.0), edge * 0.05);

  fragColor = vec4(color, 1.0);
}
