shader_type canvas_item;

uniform float radius : hint_range(0.0, 32.0) = 8.0;
uniform float softness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    float a = base.a;

    vec2 texel = TEXTURE_PIXEL_SIZE * radius;
    const int N = 8;
    vec2 dirs[N] = vec2[](
        vec2(1.0,0.0), vec2(-1.0,0.0),
        vec2(0.0,1.0), vec2(0.0,-1.0),
        vec2(0.7071,0.7071), vec2(-0.7071,0.7071),
        vec2(-0.7071,-0.7071), vec2(0.7071,-0.7071)
    );

    float sum = a;
    for (int i=0; i<N; i++) {
        sum += texture(TEXTURE, UV + dirs[i]*texel).a;
    }
    float avg = sum / float(N+1);

    // Interpolate between original and blurred alpha
    float out_a = mix(a, avg, softness);
    COLOR = vec4(base.rgb, out_a);
}
