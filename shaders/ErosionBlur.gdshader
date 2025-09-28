shader_type canvas_item;
render_mode blend_mix, unshaded;

// Total pixel distance outward after all levels
uniform float distance : hint_range(1.0, 32.0) = 8.0;
// Number of stacked erosion iterations
uniform int levels : hint_range(1, 16) = 4;
// Strength of each erosion step (0 = none, 1 = full)
uniform float strength : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 pixel = 1.0 / tex_size;

    vec4 tex = texture(TEXTURE, UV);
    float current_a = tex.a;

    // Hexagonal neighborhood offsets
    vec2 hex_offsets[6] = vec2[](
        vec2( 1.0,  0.0),   // right
        vec2(-1.0,  0.0),   // left
        vec2( 0.5,  0.866), // up-right
        vec2(-0.5, 0.866),  // up-left
        vec2( 0.5, -0.866), // down-right
        vec2(-0.5,-0.866)   // down-left
    );

    for (int l = 1; l <= levels; l++) {
        // Scale distance so the farthest ring = `distance`
        float dist = (distance * float(l)) / float(levels);

        float accum = 0.0;
        for (int i = 0; i < 6; i++) {
            accum += texture(TEXTURE, UV + hex_offsets[i] * dist * pixel).a;
        }
        float neighbor = accum / 6.0;

        // Progressively pull toward neighbors
        current_a = mix(current_a, neighbor, strength);
    }

    COLOR = vec4(tex.rgb, current_a) * COLOR; // respects Sprite2D.modulate
}
