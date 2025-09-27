shader_type canvas_item;
render_mode unshaded, blend_mix;

// Softness in texture pixels
uniform float shadow_softness : hint_range(0.0, 32.0) = 4.0;

void fragment() {
    float a = texture(TEXTURE, UV).a;

    if (shadow_softness <= 0.0) {
        // Hard shadow (just alpha mask)
        COLOR = vec4(0.0, 0.0, 0.0, a);
    } else {
        float da = fwidth(a);
        float feather = smoothstep(0.0, da * shadow_softness, a);
        COLOR = vec4(0.0, 0.0, 0.0, feather);
    }
}
