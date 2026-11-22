// Automatically converted with https://github.com/TheLeerName/ShadertoyToFlixel

#pragma header
vec4 flixel_texture2D(sampler2D bitmap, vec2 coord, float idk) { return flixel_texture2D(bitmap, coord); } // third argument fix

#define iResolution openfl_TextureSize
uniform float iTime;
#define iChannel0 bitmap
uniform sampler2D iChannel1;
uniform sampler2D iChannel2;
uniform sampler2D iChannel3;

// functions used from: https://www.shadertoy.com/view/XtyGzV
// remove pixels behind viewer from: https://www.shadertoy.com/view/3syczy

uniform float curveX;
uniform float curveY;

float wiggle(float u) {
	return 27.0*(1.0 - 2.0*u);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord ) {

	float scl = 1.0/iResolution.y;
	vec2 uv = (fragCoord.xy - 0.5*iResolution.xy) * scl;

	float a = 1.0, b = 0.0, c = 0.0;

	//              scaleX     parallelogramY          curveX
	//          parallelogramX     scaleY              curveY
	//            positionX      positionY              zoom
	mat3 H = mat3(   1.0,           0.0,  wiggle( 0.5 + curveX / 10. ),
		0.0,           1.0,  wiggle( 0.5 + curveY / 10. ),
		0.0,           0.0,                1.0);

	vec3 Huv = H * vec3(uv, 1.0);

	vec2 tex = Huv.xy / Huv.z + 0.5;

	tex.x += 0.4;
	tex /= vec2(1.8, 1.0); // return normal resolution

	fragColor = flixel_texture2D(iChannel0, tex);

	fragColor = mix(vec4(0.0), fragColor, vec4(step(0.0, Huv.z))); // remove pixels behind viewer

	//if (tex.x < 0. || tex.x > 1. || tex.y < 0. || tex.y > 1.) fragColor = vec4(0.0);
	fragColor *= smoothstep(0.0, 0.01, tex.x) * smoothstep(0.0, 0.01, tex.y) * smoothstep(1.0, 0.99, tex.x) * smoothstep(1.0, 0.99, tex.y);
}

void main() {
	mainImage(gl_FragColor, openfl_TextureCoordv*openfl_TextureSize);
}
