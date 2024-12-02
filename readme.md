# Vulkan Tutorial

Vulkan [tutorial][0] written in [Odin][1].

![result](/result.png "Final result")

## Introduction

This repository will follow the structure of the original tutorial. Each commit will correspond to one page or on section of the page for long chapters.

Sometimes an 'extra' commit will be added with some refactoring, commenting or feature.

There are a few more things covered in the [more][5] branch. 

## Requirements

You need to have a [Vulkan SDK][2] and the [Odin compiler][3].

## Running the project

```sh
# if you need to recompile the shaders
.\scripts\compile_shaders.ps1
# or ./scripts/compile_shaders.sh on linux

# compile and run the application
odin run .

# or with validation layers
odin run . -define:ENABLE_VALIDATION_LAYERS=true
```

## Commits

This section contains the summary of the project commits. Follow :rabbit2: to go to the related tutorial page and :smirk_cat: to go to the commit details.

### 1.1.1: Base code [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Base_code) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/a9f536894ec19df532365953d819b088e7e0c409)

GLFW initialization, window's creation and main loop setup.

### 1.1.2: Instance [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Instance) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/47f80889c7d217800027a737e233f82f40225d7d)

Create and destroy the Vulkan instance.

### 1.1.3: Validation layers [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Validation_layers) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/4112b47237e5a297221ad214eeff92f698017fa4)

Enable `VK_LAYER_KHRONOS_validation` validation layer and setup the debug messenger.

> Here we make use of Odin's [command-line defines][4] to control the activation of the validation layers (see [here](#running-the-project)).

### 1.1.4: Physical devices and queue families [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Physical_devices_and_queue_families) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/de593fb9aadedf31608d22421dbabc6fdd932f61)

Physical device and queue families selection.

### 1.1.5: Logical device and queues [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Logical_device_and_queues) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/ab33e87628e4de04e6965e3eeb99f80a6f5a9963)

Create the logical device and retrieve a graphics queue.

### 1.2.1: Window surface [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Window_surface) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/1065f5f9b2da690ed1a363dd4003abf6a1e4951d)

Create the window surface and retrieve a queue supporting presentation.

### 1.2.2: Swapchain [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Swap_chain) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/6837021099df672e282f394b6216a6c7f7eb8d5b)

Create the swapchain and retriving the swapchain images.

### 1.2.3: Image views [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Image_views) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/95c40631c9898b4da91aacba7de7ff249fbbcfa0)

Create the image views for the swapchain images.

### 1.3.2: Shader modules [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Shader_modules) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/4a2469ccee2cadbce85f4aea12c7535c64231ebe)

Create and compile the vertex and fragment shaders, load them, and the shader modules.

### 1.3.3: Fixed functions [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Fixed_functions) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/be32fbaa5269bfa863ebc953d88f43faf54da2f5)

Setup the states of the fixed functions of the graphics pipeline and create the pipeline layout.

### 1.3.4: Render passes [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Render_passes) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/f48f87c17d5a7d6bc52834a2f4d5d7038f1fd6c6)

Create the render pass describing the attachments to use during rendering.

### 1.3.5: Graphics pipeline conclusion [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Conclusion) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/4c54ad10b6c5ed57447f5b436e69731b48b60750)

Finish the graphics pipeline creation.

### 1.4.1: Framebuffers [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Framebuffers) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/becb034658915b9f1df1e372c31b76604074fa3f)

Create the swapchain framebuffers from the swapchain image views and the render pass.

### 1.4.2: Command buffers [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Command_buffers) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/316cbb211381b34d55dfbc3a2387cc8b37f85132)

Create the command buffer and record commands to draw.

### 1.4.3: Rendering and presentation [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Rendering_and_presentation) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/1544475ade1d713fdb506ffcd8e8000f54e2bfbe)

Finalize drawing the triangle to the screen!

### 1.4.4: Frames in flight [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Frames_in_flight) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/35316417372d8f98a08990ed1a8b9aeece8ccb30)

Improve rendering by allowing overlap between cpu and gpu with multiple frames in flight.

### 1.5: Swap chain recreation [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Swap_chain_recreation) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/0d3026e2a86f70f9e7276a622aba95fe40f595b5)

Handle swapchain recreation and window's resize.

> There is a bit of factoring around the swapchain creation and its dependencies here.

> Resizing detection is also done differently, `glfwSetFramebufferSizeCallback` is not used and we just manually check if the framebuffer was resized with `glfwGetFramebufferSize`.

### 2.1: Vertex input description [:rabbit2:](https://vulkan-tutorial.com/Vertex_buffers/Vertex_input_description) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/392daaf41001447482c16cdfa8e9a4d33bae353b)

Move hardcoded vertices from the vertex shader to the application code and update pipeline's vertex input info.

> A new `vertex.odin` file is added to keep things more manageable.

### 2.2: Vertex buffer creation [:rabbit2:](https://vulkan-tutorial.com/Vertex_buffers/Vertex_buffer_creation) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/c26a2d79da79ba3fc67f5ce86ec4270125022cbe)

Create the actual vertex buffer and its memory, fill it and bind it before drawing.

### 2.3: Staging buffer [:rabbit2:](https://vulkan-tutorial.com/Vertex_buffers/Staging_buffer) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/1e671ee886002db570cb07a9a5ac970ba2f09ace)

Create a buffer whose memory is local to the graphics card and a staging buffer from which data is tranfered.

### 2.4: Index buffer [:rabbit2:](https://vulkan-tutorial.com/Vertex_buffers/Index_buffer) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/2c4f55e72bb3b57ac27df50d0f05f688396c78a8)

Render a rectangle without duplicating vertices by using an index buffer.

### 3.1: Descriptor layout and buffer [:rabbit2:](https://vulkan-tutorial.com/Uniform_buffers/Descriptor_layout_and_buffer) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/2b48402abf4a13e45cef7beb699c4938d4a2217e)

Update the vertex shader to apply a transformation and render it with a perspective camera.
Also create the descriptor set layout, the buffers used to send data to the shader and update it each frame.

### 3.2: Descriptor pool and sets [:rabbit2:](https://vulkan-tutorial.com/Uniform_buffers/Descriptor_pool_and_sets) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/4173db8246df3c5cda0801d0f5949f8e10e74646)

Create the descriptor set pool and sets, update them to point at the proper buffers and bind them before rendering.

### 4.1: Images [:rabbit2:](https://vulkan-tutorial.com/Texture_mapping/Images) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/eff2d8abc94731cd30fa96b5b1f3780433252a55)

Load an image file and upload its data to the GPU.

### 4.2: Image view and sampler [:rabbit2:](https://vulkan-tutorial.com/Texture_mapping/Image_view_and_sampler) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/81ef9de5fb9cf0a6725ba4753b309dc51d9ef5c3)

Create the image view and sampler and enable anisotropic filtering.

### 4.3: Combined image sampler [:rabbit2:](https://vulkan-tutorial.com/Texture_mapping/Combined_image_sampler) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/125e3c2f54b3a9dcbb160fdbac523b94eb3258eb)

Update the descriptor sets, Vertex structure and shaders to use the loaded image as a texture for the displayed rectangle.

### 5: Depth buffering [:rabbit2:](https://vulkan-tutorial.com/Depth_buffering) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/57734c6b04bda781805a1e89676a3c7b2e36c3fd)

Render overlapping geometry, create a depth texture and set up depth testing.

### 6.0: Obj file loader [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/fa295d4abeb2a97888e3146af3144cc9173f1de3)

**This is not part of the original Vulkan tutorial!**

Implement a simple (and most likely incomplete) loader for .obj files in preparation for the next chapter.
It overlaps a little with the next chapter though as it already merges duplicate vertices and invert the texture coordinates y axis.

> This is a very simple loader, it might not work for other more complicated loader. Also it only outputs positions and texture coordinate since we won't use normals.

### 6: Loading models [:rabbit2:](https://vulkan-tutorial.com/Loading_models) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/8096588d847a5fae5da1ac9ac717d8221ae84303)

Load an .obj model and render it.

> Since we don't use the vertex color anymore I just remove them altogether.

> The tutorial already mentions it but the model doesn't play nicely with backface culling so I disabled it.

### 7: Generating Mipmaps [:rabbit2:](https://vulkan-tutorial.com/Generating_Mipmaps) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/9ffb71a55e425014495fe6443a6fb73e087a4c71)

Generate mipmaps for the model texture and update sampler to make use of the new mip levels.

> Model rotation is now controlled with the right and left keys.

### 8: Multisampling [:rabbit2:](https://vulkan-tutorial.com/Multisampling) [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/b8a7ec9fdd0b16693b25546a7eae902073fbc952)

Add MSAA support.

### Extra.2: Cleanup and refactoring [:smirk_cat:](https://github.com/adrien-ben/vulkan-tutorial-odin/commit/b64bd0ffd0da0db6ac42f7235a0339eaf4ec7986)

**This is not part of the original Vulkan tutorial!**

Clean up the code, refactor to avoid passing to many things around all the time, make to code more "Odin-like" by applying idioms from the language.



[0]: https://vulkan-tutorial.com/
[1]: https://odin-lang.org/
[2]: https://www.lunarg.com/vulkan-sdk/
[3]: https://odin-lang.org/docs/install/
[4]: https://odin-lang.org/docs/overview/#command-line-defines
[5]: https://github.com/adrien-ben/vulkan-tutorial-odin/tree/more
