attribute vec4 vertex;
uniform mat4 projection;
varying vec2 uv;

void main() {
	gl_Position = projection * vec4(vertex.xy, 0.0, 1.0);
	uv = vertex.zw;
}
