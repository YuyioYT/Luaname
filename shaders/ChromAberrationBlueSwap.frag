#pragma header

uniform float strength;

void main()
{
	vec2 uv = openfl_TextureCoordv;
	vec4 colR = flixel_texture2D(bitmap, vec2(uv.x + strength, uv.y));
	vec4 colG = flixel_texture2D(bitmap, vec2(uv.x - strength, uv.y));
	vec4 colB = flixel_texture2D(bitmap, uv);

	vec4 col = vec4(colR.r, colG.g, colB.b, colB.a);

	// Ajuste del color
	col = col * (1.0 - strength * 0.5);

	gl_FragColor = col;
}
