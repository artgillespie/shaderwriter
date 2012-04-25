uniform sampler2D inputImageTexture;
varying highp vec2 textureCoordinate;
 
highp float vignetteX = .80;
highp float vignetteY = .0;

void vignette(inout lowp vec3 rgb, in highp vec2 texCoord, in highp float x, in highp float y);
void saturate(inout lowp vec3 rgb, in lowp float saturation);
void haze(inout lowp vec3 rgb, in highp vec2 texCoord, in lowp vec3 color, in highp float slope, in highp float distance);
void contrast(inout lowp vec3 rgb, in highp float contrast);

mediump mat4 colorMatrix = mat4(
    vec4(1.0, 0.0, 0.0, 0.0),
    vec4(0.0, 1.0, 0.0, 0.0),
    vec4(0.0, 0.0, 1.0, 0.0),
    vec4(0.0, 0.0, 0.0, 1.0)
);

void main() {
    gl_FragColor = colorMatrix * texture2D(inputImageTexture, textureCoordinate);    
}

// Re-usable functions. Function calls don't appear to impact performance!

void vignette(inout lowp vec3 rgb, in highp vec2 texCoord, in highp float x, in highp float y) {
    lowp float d = distance(texCoord, vec2(0.5, 0.5));
    rgb *= smoothstep(x, y, d);
}

void contrast(inout lowp vec3 rgb, in highp float contrast) {
    rgb = (rgb - vec3(0.5)) * contrast + vec3(0.5);
}

const mediump vec3 luminanceWeighting = vec3(0.2125, 0.7154, 0.0721);
void saturate(inout lowp vec3 rgb, in lowp float saturation) {
    lowp float luminance = dot(rgb, luminanceWeighting);
    lowp vec3 greyScaleColor = vec3(luminance);
    rgb = mix(greyScaleColor, rgb, saturation);
}

void haze(inout lowp vec3 rgb, in highp vec2 texCoord, in lowp vec3 color, in highp float slope, in highp float distance) {	
	 highp float  d = texCoord.y * slope  +  distance; 
	 rgb = (rgb - d * color) / (1.0 - d); 	 
}
