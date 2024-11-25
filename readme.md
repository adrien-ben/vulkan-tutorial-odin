# Vulkan Tutorial

Vulkan [tutorial][0] written in [Odin][1].

## Introduction

This repository will follow the structure of the original tutorial. Each commit will correspond to one page or on section of the page for long chapters.

Sometimes an 'extra' commit will be added with some refactoring, commenting or feature.

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

This section contains the summary of the project commits. Follow :rabbit2: to go to the related tutorial page.

### 1.1.1: Base code [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Base_code)

GLFW initialization, window's creation and main loop setup.

### 1.1.2: Instance [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Instance)

Create and destroy the Vulkan instance.

### 1.1.3: Validation layers [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Validation_layers)

Enable `VK_LAYER_KHRONOS_validation` validation layer and setup the debug messenger.

> Here we make use of Odin's [command-line defines][4] to control the activation of the validation layers (see [here](#running-the-project)).

### 1.1.4: Physical devices and queue families [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Physical_devices_and_queue_families)

Physical device and queue families selection.

### 1.1.5: Logical device and queues [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Logical_device_and_queues)

Create the logical device and retrieve a graphics queue.

### 1.2.1: Window surface [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Window_surface)

Create the window surface and retrieve a queue supporting presentation.

### 1.2.2: Swapchain [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Swap_chain)

Create the swapchain and retriving the swapchain images.

### 1.2.3: Image views [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Image_views)

Create the image views for the swapchain images.

### 1.3.2: Shader modules [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Shader_modules)

Create and compile the vertex and fragment shaders, load them, and the shader modules.

### 1.3.3: Fixed functions [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Fixed_functions)

Setup the states of the fixed functions of the graphics pipeline and create the pipeline layout.

### 1.3.4: Render passes [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Render_passes)

Create the render pass describing the attachments to use during rendering.

### 1.3.5: Graphics pipeline conclusion [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Conclusion)

Finish the graphics pipeline creation.

### 1.4.1: Framebuffers [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Framebuffers)

Create the swapchain framebuffers from the swapchain image views and the render pass.

### 1.4.2: Command buffers [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Command_buffers)

Create the command buffer and record commands to draw.

### 1.4.3: Rendering and presentation [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Rendering_and_presentation)

Finalize drawing the triangle to the screen!

### 1.4.4: Frames in flight [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Frames_in_flight)

Improve rendering by allowing overlap between cpu and gpu with multiple frames in flight.

### 1.5: Swap chain recreation [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Swap_chain_recreation)

Handle swapchain recreation and window's resize.

> There is a bit of factoring around the swapchain creation and its dependencies here.

> Resizing detection is also done differently, `glfwSetFramebufferSizeCallback` is not used and we just manually check if the framebuffer was resized with `glfwGetFramebufferSize`.

### 2.1: Vertex input description [:rabbit2:](https://vulkan-tutorial.com/Vertex_buffers/Vertex_input_description)

Move hardcoded vertices from the vertex shader to the application code and update pipeline's vertex input info.

> A new `vertex.odin` file is added to keep things more manageable.

### 2.2: Vertex buffer creation [:rabbit2:](https://vulkan-tutorial.com/Vertex_buffers/Vertex_buffer_creation)

Create the actual vertex buffer and its memory, fill it and bind it before drawing.

### 2.3: Staging buffer [:rabbit2:](https://vulkan-tutorial.com/Vertex_buffers/Staging_buffer)

Create a buffer whose memory is local to the graphics card and a staging buffer from which data is tranfered.

### 2.4: Index buffer [:rabbit2:](https://vulkan-tutorial.com/Vertex_buffers/Index_buffer)

Render a rectangle without duplicating vertices by using an index buffer.

### 3.1: Descriptor layout and buffer [:rabbit2:](https://vulkan-tutorial.com/Uniform_buffers/Descriptor_layout_and_buffer)

Update the vertex shader to apply a transformation and render it with a perspective camera.
Also create the descriptor set layout, the buffers used to send data to the shader and update it each frame.

### 3.2: Descriptor pool and sets [:rabbit2:](https://vulkan-tutorial.com/Uniform_buffers/Descriptor_pool_and_sets)

Create the descriptor set pool and sets, update them to point at the proper buffers and bind them before rendering.

### 4.1: Images [:rabbit2:](https://vulkan-tutorial.com/Texture_mapping/Images)

Load an image file and upload its data to the GPU.

### 4.2: Image view and sampler [:rabbit2:](https://vulkan-tutorial.com/Texture_mapping/Image_view_and_sampler)

Create the image view and sampler and enable anisotropic filtering.

### 4.3: Combined image sampler [:rabbit2:](https://vulkan-tutorial.com/Texture_mapping/Combined_image_sampler)

Update the descriptor sets, Vertex structure and shaders to use the loaded image as a texture for the displayed rectangle.

### 5: Depth buffering [:rabbit2:](https://vulkan-tutorial.com/Depth_buffering)

Render overlapping geometry, create a depth texture and set up depth testing.

### 6.0: Obj file loader

**This is not part of the original Vulkan tutorial!**

Implement a simple (and most likely incomplete) loader for .obj files in preparation for the next chapter.
It overlaps a little with the next chapter though as it already merges duplicate vertices and invert the texture coordinates y axis.

> This is a very simple loader, it might not work for other more complicated loader. Also it only outputs positions and texture coordinate since we won't use normals.



[0]: https://vulkan-tutorial.com/
[1]: https://odin-lang.org/
[2]: https://www.lunarg.com/vulkan-sdk/
[3]: https://odin-lang.org/docs/install/
[4]: https://odin-lang.org/docs/overview/#command-line-defines
