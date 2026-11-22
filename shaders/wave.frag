#pragma header

uniform float iTime;

uniform float waveSpeed;
uniform float waveFrq;
uniform float waveAmp;

void main() {
	vec2 uv=openfl_TextureCoordv;
	uv.x+=sin(uv.y*waveFrq*100.0+iTime*waveSpeed*10.0)*waveAmp*0.1;
	gl_FragColor=flixel_texture2D(bitmap,uv);
}
