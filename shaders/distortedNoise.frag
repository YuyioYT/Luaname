#pragma header

uniform float iTime;

uniform float strength;

float h(vec2 p) {
	return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);
}

void main() {
	vec2 uv=openfl_TextureCoordv;
	float n=h(vec2(floor(uv.y*60.0),floor(iTime*12.0)));
	uv.x+=(n-0.5)*0.04*strength*step(0.8,n);
	gl_FragColor=flixel_texture2D(bitmap,uv);
}
