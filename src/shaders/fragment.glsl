#version 450 core
in vec2 fragPos;
in vec3 fragColor;
out vec4 outColor;

void main()
{
    float dist = length(fragPos);
   	if(dist > 0.5) 
       	discard;
 		// outColor = vec4(0.0, 1.0, 0.0, 1.0); 
   	else 
		outColor = vec4(fragColor * (dist > 0.4 ? 0.8 : 1.0), 1.0); 
}
