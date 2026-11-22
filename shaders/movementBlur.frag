#pragma header

uniform float iTime;

uniform float strength;
uniform float strengthY;

void main() {
	vec2 uv=openfl_TextureCoordv;
	vec4 c=vec4(0.0);
	float w=0.0;
	for(int i=-4;i<=4;i++) {
		float f=float(i)/4.0;
		float k=1.0-abs(f)*0.7;
		c+=flixel_texture2D(bitmap,uv+vec2(f*strength*0.05,f*strengthY*0.05))*k;
		w+=k;
	}
	gl_FragColor=c/w;
}
