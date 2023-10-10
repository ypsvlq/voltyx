varying vec2 uv;
uniform sampler2D texture;

vec3 track_color = vec3(0.9, 0.9, 0.9);
vec3 left_color = vec3(0.11373, 0.89804, 0.92549);
vec3 right_color = vec3(0.96863, 0.38039, 0.76471);

void main() {
	vec3 sample = texture2D(texture, uv).rgb;
	vec3 color = left_color * sample.b + track_color * sample.g + right_color * sample.r;
	gl_FragColor = vec4(color, 1);
}
