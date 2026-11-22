#pragma header

uniform float rOffset;
uniform float gOffset;
uniform float bOffset;

void main()
{
	vec4 col1 = flixel_texture2D(bitmap, openfl_TextureCoordv.st - vec2(rOffset, 0.0));
	vec4 col2 = flixel_texture2D(bitmap, openfl_TextureCoordv.st - vec2(gOffset, 0.0));
	vec4 col3 = flixel_texture2D(bitmap, openfl_TextureCoordv.st - vec2(bOffset, 0.0));

	gl_FragColor = vec4(col1.r, col2.g, col3.b, col2.a);
}
