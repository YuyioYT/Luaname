// Automatically converted with https://github.com/TheLeerName/ShadertoyToFlixel

#pragma header

#define iResolution vec3(openfl_TextureSize, 0.)
uniform float iTime;
#define iChannel0 bitmap
#define texture flixel_texture2D

// end of ShadertoyToFlixel header

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i), hash(i + vec2(0.0, 1.0)), f.x), f.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = fragCoord / iResolution.xy;
	vec3 color;

	float corruptionWave = sin(iTime * 1.5) * 0.5 + 0.5;
	float corruption = pow(corruptionWave, 3.0); // Picos ms agresivos

	float screenTear = noise(vec2(uv.y * 3.0, iTime * 2.0));
	float tearShift = (screenTear - 0.5) * 0.4 * corruption;

	float datamosh = noise(vec2(floor(uv.y * 15.0), iTime * 0.8));
	float datamoshShift = step(0.7, datamosh) * (hash(vec2(floor(uv.y * 20.0), iTime)) * 0.5);

	vec2 blockUV = floor(uv * vec2(15.0, 12.0));
	float blockCorrupt = hash(blockUV + iTime * 0.5);
	float blockShift = step(0.75, blockCorrupt) * corruption;
	float blockOffsetX = (hash(blockUV + 1.0) - 0.5) * 0.4;
	float blockOffsetY = (hash(blockUV + 2.0) - 0.5) * 0.3;

	float pixelLevel = mix(1.0, 60.0, corruption);
	vec2 pixelUV = floor(uv * pixelLevel) / pixelLevel;

	float invert = step(0.85, noise(vec2(iTime * 0.5, uv.y * 5.0)));

	float verticalShift = noise(vec2(iTime * 1.2, uv.x * 4.0)) * 0.3 * corruption;

	float chromaPower = corruption * 0.08;

	// Aplicar todos los desplazamientos
	vec2 uvR = uv + vec2(tearShift + datamoshShift + blockOffsetX * blockShift + chromaPower,
		verticalShift + blockOffsetY * blockShift);
	vec2 uvG = uv + vec2(tearShift * 0.7 + datamoshShift * 0.5 + blockOffsetX * blockShift * 0.5,
		verticalShift * 0.5);
	vec2 uvB = uv + vec2(tearShift - datamoshShift * 0.8 + blockOffsetX * blockShift - chromaPower,
		-verticalShift + blockOffsetY * blockShift * 0.7);

	vec2 pixelUvR = mix(uvR, floor(uvR * pixelLevel) / pixelLevel, corruption);
	vec2 pixelUvG = mix(uvG, floor(uvG * pixelLevel) / pixelLevel, corruption * 0.7);
	vec2 pixelUvB = mix(uvB, floor(uvB * pixelLevel) / pixelLevel, corruption);

	color.r = texture(iChannel0, pixelUvR).r;
	color.g = texture(iChannel0, pixelUvG).g;
	color.b = texture(iChannel0, pixelUvB).b;

	float flash = step(0.92, noise(vec2(iTime * 10.0, 0.0)));
	color = mix(color, vec3(1.0), flash * 0.3 * corruption);

	if (invert > 0.0) {
		color = mix(color, 1.0 - color, invert * corruption);
	}

	float corruptLines = noise(vec2(uv.y * 50.0, iTime * 5.0));
	float lineBreak = step(0.9, corruptLines);
	if (lineBreak > 0.0) {
		color = mix(color, vec3(hash(uv + iTime)), lineBreak * 0.6 * corruption);
	}

	float ghost = step(0.88, noise(vec2(uv.y * 8.0, iTime * 1.5)));
	if (ghost > 0.0) {
		vec3 ghostColor;
		ghostColor.r = texture(iChannel0, uv + vec2(0.05, 0.0)).r;
		ghostColor.g = texture(iChannel0, uv + vec2(-0.03, 0.02)).g;
		ghostColor.b = texture(iChannel0, uv + vec2(0.0, -0.04)).b;
		color = mix(color, ghostColor, ghost * corruption);
	}

	float digitalNoise = hash(uv * iTime + floor(iTime * 30.0)) * 0.15 * corruption;
	color += digitalNoise;

	float corruptionSweep = sin((uv.y - iTime * 0.5) * 50.0);
	float sweepIntensity = exp(-abs(uv.y - fract(iTime * 0.1)) * 5.0);
	color = mix(color, color.brg, sweepIntensity * 0.4 * corruption);

	float distortionWave = sin(uv.y * 20.0 + iTime * 3.0) * 0.02 * corruption;
	vec2 distortedUV = uv + vec2(distortionWave, 0.0);
	vec3 distortedColor = texture(iChannel0, distortedUV).rgb;
	color = mix(color, distortedColor, 0.3 * corruption);

	color = mix(color, color * 1.5, corruption * 0.3);

	color = (color - 0.5) * (1.0 + corruption * 0.5) + 0.5;

	fragColor = vec4(color, texture(iChannel0, fragCoord / iResolution.xy).a);
}

void main() {
	mainImage(gl_FragColor, openfl_TextureCoordv*openfl_TextureSize);
}
