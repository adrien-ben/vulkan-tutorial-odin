#version 460

const uint DISPLAY_MODE_COLORS = 0;
const uint DISPLAY_MODE_NORMALS = 1;
layout (constant_id = 0) const uint DISPLAY_MODE = DISPLAY_MODE_COLORS;

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec3 fragNormal;

layout(binding = 1) uniform sampler2D texSampler;

layout(location = 0) out vec4 outColor;

void main() {
    if (DISPLAY_MODE == DISPLAY_MODE_NORMALS) {
        outColor = vec4(0.5 + normalize(fragNormal) * 0.5, 1.0);
    } else {
        outColor = vec4(texture(texSampler, fragTexCoord).rgb, 1.0);
    }
}
