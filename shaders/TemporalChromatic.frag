#pragma header

uniform float time;
uniform float trailIntensity;

void main()
{
	vec2 uv = openfl_TextureCoordv;

	// Efecto de aberración que cambia con el tiempo
	float rShift = sin(time * 2.0) * 0.01 * trailIntensity;
	float bShift = cos(time * 2.0) * 0.01 * trailIntensity;

	// Muestreo de canales desplazados
	float r = texture2D(bitmap, vec2(uv.x + rShift, uv.y)).r;
	float g = texture2D(bitmap, uv).g;
	float b = texture2D(bitmap, vec2(uv.x + bShift, uv.y)).b;

	// Efecto de desvanecimiento para simular trail
	float fade = 0.8 + 0.2 * sin(time * 3.0);

	gl_FragColor = vec4(r * fade, g * fade, b * fade, texture2D(bitmap, uv).a);
}
