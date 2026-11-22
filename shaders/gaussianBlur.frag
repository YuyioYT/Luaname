#pragma header

uniform float iTime;

uniform float loops;
uniform float quality;
uniform float strength;

void main() {
	vec2 uv=openfl_TextureCoordv;
	vec2 rad=strength/openfl_TextureSize;
	vec4 c=flixel_texture2D(bitmap,uv);
	float n=1.0;
	for(int d=0;d<16;d++) {
		if(float(d)>=loops) {
			break;
		}
		float a=6.2831853*float(d)/max(loops,1.0);
		for(int i=1;i<=6;i++) {
			if(float(i)>quality) {
				break;
			}
			float r=float(i)/max(quality,1.0);
			c+=flixel_texture2D(bitmap,uv+vec2(cos(a),sin(a))*rad*r);
			n+=1.0;
		}
	}
	gl_FragColor=c/n;
}
