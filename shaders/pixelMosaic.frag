#pragma header

uniform float iTime;

uniform float strength;

void main() {
	vec2 uv=openfl_TextureCoordv;
	float s=max(strength,0.0)*0.04;
	if(s>0.0005) {
		uv=(floor(uv/s)+0.5)*s;
	}
	gl_FragColor=flixel_texture2D(bitmap,uv);
}
