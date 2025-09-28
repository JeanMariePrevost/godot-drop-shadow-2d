shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float corner_radius : hint_range(0.0, 0.5) = 0.1; // roundness of corners
uniform float softness      : hint_range(0.0, 0.5) = 0.2; // fade thickness inward

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    vec2 uv = UV;

    // Distance outside rounded rect baseline
    vec2 d = abs(uv - vec2(0.5)) - vec2(0.5 - (corner_radius + softness));
    float outside = length(max(d, 0.0));

    // Define thresholds: fully inside until corner_radius, then fade inward
    float inner = corner_radius;
    float outer = corner_radius + softness;

    // Feather factor: solid inside inner, fade across softness band
    float feather = 1.0 - smoothstep(inner, outer, outside);

    COLOR = vec4(tex.rgb, tex.a * feather) * COLOR;
}
