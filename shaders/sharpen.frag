#version 460 core

// Nitidez real (máscara de enfoque / unsharp mask con kernel laplaciano 3x3).
// Suma la diferencia entre el píxel y el promedio de sus vecinos: realza los
// bordes sin cambiar el brillo medio de la imagen (en zonas planas no hace nada).

#include <flutter/runtime_effect.glsl>

precision mediump float;

// El motor carga uSize (tamaño de la textura) y uTexture (la entrada del filtro).
uniform vec2 uSize;
uniform float uAmount;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec2 px = 1.0 / uSize;

  vec4 c = texture(uTexture, uv);
  vec4 n = texture(uTexture, uv + vec2(0.0, -px.y)) +
           texture(uTexture, uv + vec2(0.0, px.y)) +
           texture(uTexture, uv + vec2(-px.x, 0.0)) +
           texture(uTexture, uv + vec2(px.x, 0.0));

  vec3 sharp = c.rgb + uAmount * (4.0 * c.rgb - n.rgb);
  // Colores premultiplicados: el canal no puede superar al alfa.
  fragColor = vec4(clamp(sharp, vec3(0.0), vec3(c.a)), c.a);
}
