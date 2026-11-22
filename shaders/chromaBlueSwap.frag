#pragma header

uniform float iTime;

uniform float strength;

void main() {
	vec2 uv=openfl_TextureCoordv;
	vec4 c=flixel_texture2D(bitmap,uv);
	vec3 s=vec3(flixel_texture2D(bitmap,uv+vec2(strength,0.0)).r, c.g, flixel_texture2D(bitmap,uv-vec2(strength,0.0)).b);
	gl_FragColor=vec4(s.bgr*0.5+s*0.5,c.a);
}
