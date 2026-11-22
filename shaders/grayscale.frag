#pragma header

uniform float _amount;

void main()
{
	vec4 col = flixel_texture2D(bitmap, openfl_TextureCoordv);
	float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(col.rgb, vec3(gray), _amount);
	gl_FragColor = col;
}
