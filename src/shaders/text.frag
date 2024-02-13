varying vec2 texcoord;
uniform sampler2D texture;
uniform vec3 color;

void main() {
    float alpha = texture2D(texture, texcoord).a;
    gl_FragColor = vec4(color, alpha);
}
