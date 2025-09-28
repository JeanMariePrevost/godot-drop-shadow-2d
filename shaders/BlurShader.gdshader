shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float softness : hint_range(0.0, 10.0) = 2.0;

void fragment() {
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 pixel = 1.0 / tex_size;

    // offset distance in pixels
    float r = softness;

    // sample center + 4 neighbors
    vec4 col = texture(TEXTURE, UV);
    col += texture(TEXTURE, UV + vec2( r, 0.0) * pixel);
    col += texture(TEXTURE, UV + vec2(-r, 0.0) * pixel);
    col += texture(TEXTURE, UV + vec2(0.0,  r) * pixel);
    col += texture(TEXTURE, UV + vec2(0.0, -r) * pixel);

    // average
    COLOR = col / 5.0;
}
