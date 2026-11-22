#pragma header

uniform vec2 rOffset;
uniform vec2 gOffset;
uniform vec2 bOffset;

void main()
{
	vec4 col1 = flixel_texture2D(bitmap, openfl_TextureCoordv.st - rOffset);
	vec4 col2 = flixel_texture2D(bitmap, openfl_TextureCoordv.st - gOffset);
	vec4 col3 = flixel_texture2D(bitmap, openfl_TextureCoordv.st - bOffset);

	gl_FragColor = vec4(col1.r, col2.g, col3.b, col2.a);
}
