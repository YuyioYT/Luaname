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

	float intensity = 1.0;
	float chaos = sin(iTime * 4.0) * 0.5 + 0.5;

	vec2 chaosUV = uv;
	chaosUV.x += sin(uv.y * 30.0 + iTime * 5.0) * 0.15 * intensity;
	chaosUV.y += cos(uv.x * 25.0 + iTime * 4.0) * 0.1 * intensity;

	float pixelSize = mix(600.0, 8.0, chaos);
	chaosUV = floor(chaosUV * pixelSize) / pixelSize;

	float colorRotate = iTime * 2.0;
	mat3 colorMatrix = mat3(
		cos(colorRotate), sin(colorRotate) * 0.3, 0.0,
		-sin(colorRotate) * 0.3, cos(colorRotate), sin(colorRotate) * 0.3,
		0.0, -sin(colorRotate) * 0.3, cos(colorRotate)
	);

	vec3 color;
	color.r = texture(iChannel0, chaosUV + vec2(0.05 * chaos, 0.03 * chaos)).r;
	color.g = texture(iChannel0, chaosUV).g;
	color.b = texture(iChannel0, chaosUV - vec2(0.05 * chaos, 0.03 * chaos)).b;

	color = colorMatrix * color;

	float flash = step(0.85, hash(vec2(iTime * 20.0)));
	color = mix(color, vec3(hash(uv * iTime)), flash * 0.7);

	if (hash(vec2(floor(uv.y * 10.0), floor(iTime * 3.0))) > 0.8) {
		vec2 datamoshUV = uv;
		datamoshUV.x += (hash(vec2(floor(uv.y * 8.0), 1.0)) - 0.5) * 0.5;
		datamoshUV.y += (hash(vec2(floor(uv.x * 8.0), 2.0)) - 0.5) * 0.3;
		color = mix(color, texture(iChannel0, datamoshUV).rgb, 0.8);
	}

	color += hash(uv + iTime * 10.0) * 0.2 * chaos;

	if (hash(vec2(floor(iTime * 2.0))) > 0.7) {
		color = 1.0 - color;
	}

	float tear = step(0.9, noise(vec2(uv.y * 3.0, iTime * 8.0)));
	if (tear > 0.0) {
		color.rgb = color.brg;
	}

	fragColor = vec4(color, texture(iChannel0, fragCoord / iResolution.xy).a);
}

void main() {
	mainImage(gl_FragColor, openfl_TextureCoordv*openfl_TextureSize);
}
