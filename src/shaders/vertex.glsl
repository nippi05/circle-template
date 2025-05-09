#version 450 core
layout (location = 0) in vec2 offset;
layout (location = 1) in float radius;
layout (location = 2) in vec3 color; 
out vec2 fragPos;
out vec3 fragColor;

void main()
{
	vec2 pos[3] = vec2[3](
    	vec2(1.0, 0.0),                                  // Vertex 1
    	vec2(-0.5, sqrt(3.0) / 2.0),                    // Vertex 2
    	vec2(-0.5, -sqrt(3.0) / 2.0)                    // Vertex 3
	);

    fragPos = pos[gl_VertexID];
    fragColor = color; 
    gl_Position = vec4(radius * pos[gl_VertexID] + offset.xy, 0.0,  1.0);
}
