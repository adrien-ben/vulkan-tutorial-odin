Write-Host "Compiling glsl shaders..."
glslangValidator -V -S vert -o .\shaders\vertex.spv .\shaders\vertex.glsl
glslangValidator -V -S frag -o .\shaders\fragment.spv .\shaders\fragment.glsl
