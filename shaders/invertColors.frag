#pragma header

uniform float iTime;

uniform float lockAlpha;

void main() {
	vec4 c=flixel_texture2D(bitmap,openfl_TextureCoordv);
	c.rgb=(1.0-c.rgb/max(c.a,0.0001))*c.a;
	if(lockAlpha>0.5) {
		c.a=1.0;
	}
	gl_FragColor=c;
}
