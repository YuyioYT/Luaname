#pragma header

uniform float iTime;

uniform float strength;

float h(vec2 p) {
	return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);
}

void main() {
	vec2 uv=openfl_TextureCoordv;
	vec4 c=flixel_texture2D(bitmap,uv);
	float n=h(uv*openfl_TextureSize+floor(iTime*30.0));
	c.rgb=mix(c.rgb,vec3(n),clamp(strength*0.01,0.0,1.0)*c.a);
	gl_FragColor=c;
}
