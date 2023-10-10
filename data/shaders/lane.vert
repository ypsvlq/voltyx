attribute vec4 vertex;
uniform mat4x4 projection;
uniform mat4x4 view;
varying vec2 uv;

void main() {
	gl_Position = projection * view * vec4(vertex.x, 0, vertex.y, 1);
	uv = vertex.zw;
}
