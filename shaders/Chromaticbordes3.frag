//SHADERTOY PORT FIX
#pragma header
vec2 uv = openfl_TextureCoordv.xy;
vec2 fragCoord = openfl_TextureCoordv * openfl_TextureSize;
vec2 iResolution = openfl_TextureSize;
uniform float iTime;
#define iChannel0 bitmap
#define texture flixel_texture2D
#define fragColor gl_FragColor
#define mainImage main
//****MAKE SURE TO remove the parameters from mainImage.

// Transverse Chromatic Aberration Shader

int sampleCount = 50;
float blur = 0.25;
float falloff = 3.0;

#define INPUT iChannel0

void main()
{
	// Normalize fragment coordinates to a range of 0 to 1
	vec2 destCoord = fragCoord / iResolution;

	// Calculate direction and velocity
	vec2 direction = normalize(destCoord - 0.5);
	vec2 velocity = direction * blur * pow(length(destCoord - 0.5), falloff);
	float inverseSampleCount = 1.0 / float(sampleCount);

	// Define increments for chromatic offsets
	vec2 incrementR = velocity * 1.0 * inverseSampleCount;
	vec2 incrementG = velocity * 2.0 * inverseSampleCount;
	vec2 incrementB = velocity * 4.0 * inverseSampleCount;

	// Initialize accumulators for RGB channels
	vec3 accumulator = vec3(0.0);
	vec2 offsetR = vec2(0.0);
	vec2 offsetG = vec2(0.0);
	vec2 offsetB = vec2(0.0);

	// Sample the texture multiple times
	for (int i = 0; i < sampleCount; i++) {
		accumulator.r += texture(INPUT, destCoord + offsetR).r;
		accumulator.g += texture(INPUT, destCoord + offsetG).g;
		accumulator.b += texture(INPUT, destCoord + offsetB).b;

		// Update offsets
		offsetR -= incrementR;
		offsetG -= incrementG;
		offsetB -= incrementB;
	}

	// Set the fragment color
	fragColor = vec4(accumulator / float(sampleCount), texture(INPUT, destCoord).a);
}
