package main

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

WIN_WIDTH :: 800
WIN_HEIGHT :: 600

MAX_FRAMES_IN_FLIGHT :: 2

ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

DEVICE_EXTENSIONS := [?]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

main :: proc() {
	fmt.println("Hello Vulkan!")

	if !glfw.Init() {
		panic("Failed to init GLFW.")
	}
	defer {
		glfw.Terminate()
		fmt.println("GLFW terminated.")
	}
	fmt.println("GLFW initialized.")

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window := glfw.CreateWindow(WIN_WIDTH, WIN_HEIGHT, "Vulkan", nil, nil)
	if window == nil {
		panic("Failed to create GLFW window.")
	}
	defer {
		glfw.DestroyWindow(window)
		fmt.println("Window destroyed.")
	}
	fmt.println("Window created.")

	vk.load_proc_addresses((rawptr)(glfw.GetInstanceProcAddress))

	instance := create_instance()
	defer {
		vk.DestroyInstance(instance, nil)
		fmt.println("Vulkan instance destroyed.")
	}
	fmt.println("Vulkan instance created.")

	vk.load_proc_addresses(instance)

	when ENABLE_VALIDATION_LAYERS {
		debug_messenger := setup_debug_messenger(instance)
		defer {
			vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
			fmt.println("Vulkan debug messenger destroyed.")
		}
		fmt.println("Vulkan debug messenger created.")
	}

	surface := create_surface(instance, window)
	defer {
		vk.DestroySurfaceKHR(instance, surface, nil)
		fmt.println("Vulkan surface destroyed.")
	}
	fmt.println("Vulkan surface created.")

	pdevice, found := pick_physical_device(instance, surface)
	if !found {
		fmt.eprintln("No suitable Vulkan physical device found.")
		return
	}
	fmt.printfln("Vulkan physical device selected: %#v.", pdevice)

	device := create_logical_device(pdevice)
	defer {
		vk.DestroyDevice(device, nil)
		fmt.println("Vulkan logical device destroyed.")
	}
	fmt.println("Vulkan logical device created.")

	graphics_queue: vk.Queue
	vk.GetDeviceQueue(
		device,
		u32(pdevice.queue_family_indices.graphics_family),
		0,
		&graphics_queue,
	)

	present_queue: vk.Queue
	vk.GetDeviceQueue(device, u32(pdevice.queue_family_indices.present_family), 0, &present_queue)

	swapchain_support := query_swapchain_support(pdevice.handle, surface)
	defer {
		delete_swapchain_support_details(swapchain_support)
	}
	swapchain_config := select_swapchain_config(swapchain_support, window)

	render_pass := create_render_pass(device, swapchain_config)
	defer {
		vk.DestroyRenderPass(device, render_pass, nil)
		fmt.println("Vulkan render pass destroyed.")
	}
	fmt.println("Vulkan render pass created.")

	swapchain := create_swapchain(device, pdevice, surface, render_pass, swapchain_config)
	defer {
		destroy_swapchain(device, swapchain)
		fmt.println("Swapchain destroyed.")
	}
	fmt.println("Swapchain created.")

	graphics_pipeline_layout, graphics_pipeline := create_graphics_pipeline(device, render_pass)
	defer {
		vk.DestroyPipelineLayout(device, graphics_pipeline_layout, nil)
		vk.DestroyPipeline(device, graphics_pipeline, nil)
		fmt.println("Vulkan graphics pipeline and layout destroyed.")
	}
	fmt.println("Vulkan graphics pipeline and layout created.")

	command_pool := create_command_pool(device, pdevice.queue_family_indices.graphics_family)
	defer {
		vk.DestroyCommandPool(device, command_pool, nil)
		fmt.println("Vulkan command pool destroyed.")
	}
	fmt.println("Vulkan command pool created.")

	command_buffers := allocate_command_buffers(device, command_pool)
	fmt.println("Vulkan command buffer allocated.")

	sync_objs := create_sync_objects(device)
	defer {
		for o in sync_objs {
			destroy_sync_objects(device, o)
		}
		fmt.println("Vulkan sync objects destroyed.")
	}
	fmt.println("Vulkan sync objects created.")

	vertex_buffer, vertex_buffer_memory := create_vertex_buffer(
		device,
		pdevice.handle,
		command_pool,
		graphics_queue,
	)
	defer {
		destroy_buffer(device, vertex_buffer, vertex_buffer_memory)
		fmt.println("Vertex buffer destroyed.")
	}
	fmt.println("Vertex buffer created.")

	index_buffer, index_buffer_memory := create_index_buffer(
		device,
		pdevice.handle,
		command_pool,
		graphics_queue,
	)
	defer {
		destroy_buffer(device, index_buffer, index_buffer_memory)
		fmt.println("Index buffer destroyed.")
	}
	fmt.println("Index buffer created.")

	current_frame := 0
	is_swapchain_dirty := false
	fb_w, fb_h := glfw.GetFramebufferSize(window)
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		// check if window was resized and wait if it is minimized
		w, h := glfw.GetFramebufferSize(window)
		if w != fb_w || h != fb_h {
			if w == 0 || h == 0 {
				continue
			}
			fmt.println("Window has been resized.")
			fb_w = w
			fb_h = h
			is_swapchain_dirty = true
			continue
		}

		result: vk.Result
		if is_swapchain_dirty {
			swapchain = recreate_swapchain(
				device,
				pdevice,
				window,
				surface,
				render_pass,
				swapchain,
			)
			fmt.println("Swapchain recreated.")
			is_swapchain_dirty = false
		}

		sync_obj := sync_objs[current_frame]
		command_buffer := command_buffers[current_frame]

		// wait for previous frame
		result = vk.WaitForFences(device, 1, &sync_obj.in_flight, true, max(u64))
		if result != .SUCCESS {
			fmt.eprintfln("Failed to wait for fence: %v.", result)
			break
		}

		// acquire a new image from the swapchain
		image_index: u32
		result = vk.AcquireNextImageKHR(
			device,
			swapchain.handle,
			max(u64),
			sync_obj.image_available,
			{},
			&image_index,
		)
		if result == .ERROR_OUT_OF_DATE_KHR {
			is_swapchain_dirty = true
			continue
		} else if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
			fmt.eprintfln("Failed to acquire swapchain image: %v.", result)
			break
		}

		result = vk.ResetFences(device, 1, &sync_obj.in_flight)
		if result != .SUCCESS {
			fmt.eprintfln("Failed to reset fence: %v.", result)
			break
		}

		// record and submit drawing commands
		result = vk.ResetCommandBuffer(command_buffer, nil)
		if result != .SUCCESS {
			fmt.eprintfln("Failed to reset command buffer: %v.", result)
			break
		}

		record_command_buffer(
			command_buffer,
			render_pass,
			swapchain.framebuffers[image_index],
			swapchain.config,
			graphics_pipeline,
			&vertex_buffer,
			index_buffer,
		)

		submit_info := vk.SubmitInfo {
			sType                = .SUBMIT_INFO,
			waitSemaphoreCount   = 1,
			pWaitSemaphores      = &sync_obj.image_available,
			pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
			commandBufferCount   = 1,
			pCommandBuffers      = &command_buffer,
			signalSemaphoreCount = 1,
			pSignalSemaphores    = &sync_obj.render_finished,
		}
		result = vk.QueueSubmit(graphics_queue, 1, &submit_info, sync_obj.in_flight)
		if result != .SUCCESS {
			fmt.eprintfln("Failed to submit: %v.", result)
			break
		}

		// present the result to the screen!
		present_info := vk.PresentInfoKHR {
			sType              = .PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = &sync_obj.render_finished,
			swapchainCount     = 1,
			pSwapchains        = &swapchain.handle,
			pImageIndices      = &image_index,
		}
		result = vk.QueuePresentKHR(present_queue, &present_info)
		if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
			is_swapchain_dirty = true
		} else if result != .SUCCESS {
			fmt.eprintfln("Failed to acquire swapchain image: %v.", result)
			break
		}

		current_frame = (current_frame + 1) % MAX_FRAMES_IN_FLIGHT
	}

	vk.DeviceWaitIdle(device)
}

create_instance :: proc() -> vk.Instance {
	// list required instance extensions
	required_exts: [dynamic]cstring
	defer delete(required_exts)

	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	append(&required_exts, ..glfw_extensions[:])
	when ENABLE_VALIDATION_LAYERS {
		append(&required_exts, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}
	when ODIN_OS == .Darwin {
		append(&required_exts, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	result: vk.Result
	// check extensions support
	{
		supported_exts_count: u32
		result = vk.EnumerateInstanceExtensionProperties(nil, &supported_exts_count, nil)
		if result != .SUCCESS {
			panic("Failed to get instance extension count.")
		}

		supported_exts := make([]vk.ExtensionProperties, supported_exts_count)
		defer delete(supported_exts)
		result = vk.EnumerateInstanceExtensionProperties(
			nil,
			&supported_exts_count,
			raw_data(supported_exts),
		)
		if result != .SUCCESS {
			panic("Failed to list instance extensions.")
		}

		all_extensions_supported := true
		for required in required_exts {
			found := false
			for &supported in supported_exts {
				supported := cstring(&supported.extensionName[0])
				if supported == required {
					found = true
					break
				}
			}

			if !found {
				fmt.eprintfln("Required extension %v not supported.", required)
				all_extensions_supported = false
			}

		}
		if !all_extensions_supported {
			panic("Not all required instance extensions are supported.")
		}
	}

	// check validation layers support
	when ENABLE_VALIDATION_LAYERS {
		layer_count: u32
		result = vk.EnumerateInstanceLayerProperties(&layer_count, nil)
		if result != .SUCCESS {
			panic("Failed to get validation layer count.")
		}

		supported_layers := make([]vk.LayerProperties, layer_count)
		defer delete(supported_layers)
		result = vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(supported_layers))
		if result != .SUCCESS {
			panic("Failed to list validation layers.")
		}

		all_layers_supported := true
		for required in VALIDATION_LAYERS {
			found := false
			for &supported in supported_layers {
				supported := cstring(&supported.layerName[0])
				if supported == required {
					found = true
					break
				}
			}

			if !found {
				fmt.eprintfln("Required validation layer %v not supported.", required)
				all_layers_supported = false
			}
		}
		if !all_layers_supported {
			panic("Not all required validation layers are supported.")
		}
	}

	// create the instance
	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Vulkan Tutorial",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_0,
	}
	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(required_exts)),
		ppEnabledExtensionNames = raw_data(required_exts),
		enabledLayerCount       = 0,
	}
	when ENABLE_VALIDATION_LAYERS {
		create_info.enabledLayerCount = u32(len(VALIDATION_LAYERS))
		create_info.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS[:])

		debug_messenger_create_info := create_setup_messenger_create_info()
		create_info.pNext = &debug_messenger_create_info
	}
	when ODIN_OS == .Darwin {
		create_info.flags = {.ENUMERATE_PORTABILITY_KHR}
	}

	instance: vk.Instance
	result = vk.CreateInstance(&create_info, nil, &instance)
	if result != .SUCCESS {
		panic("Failed to create instance.")
	}

	return instance
}

when ENABLE_VALIDATION_LAYERS {
	messenger_callback :: proc "system" (
		severity: vk.DebugUtilsMessageSeverityFlagsEXT,
		_: vk.DebugUtilsMessageTypeFlagsEXT,
		data: ^vk.DebugUtilsMessengerCallbackDataEXT,
		_: rawptr,
	) -> b32 {
		context = runtime.default_context()

		switch severity {
		case {.ERROR}:
			fmt.eprintln("validation:", data.pMessage)
		case:
			fmt.println("validation:", data.pMessage)
		}

		return false
	}

	create_setup_messenger_create_info :: proc() -> vk.DebugUtilsMessengerCreateInfoEXT {
		return {
			sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
			messageType = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING},
			pfnUserCallback = messenger_callback,
		}
	}

	setup_debug_messenger :: proc(instance: vk.Instance) -> vk.DebugUtilsMessengerEXT {
		create_info := create_setup_messenger_create_info()
		messenger: vk.DebugUtilsMessengerEXT
		result := vk.CreateDebugUtilsMessengerEXT(instance, &create_info, nil, &messenger)
		if result != .SUCCESS {
			panic("Failed to create debug messenger.")
		}
		return messenger
	}
}

create_surface :: proc(instance: vk.Instance, window: glfw.WindowHandle) -> vk.SurfaceKHR {
	surface: vk.SurfaceKHR
	result := glfw.CreateWindowSurface(instance, window, nil, &surface)
	if result != .SUCCESS {
		panic("Failed to create surface.")
	}
	return surface
}

PhysicalDevice :: struct {
	handle:               vk.PhysicalDevice,
	name:                 string,
	queue_family_indices: QueueFamilyIndices,
}

QueueFamilyIndices :: struct {
	graphics_family: int,
	present_family:  int,
}

pick_physical_device :: proc(
	instance: vk.Instance,
	surface: vk.SurfaceKHR,
) -> (
	PhysicalDevice,
	bool,
) {
	device_count: u32
	if result := vk.EnumeratePhysicalDevices(instance, &device_count, nil); result != .SUCCESS {
		panic("Failed to get physical device count.")
	}

	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	if result := vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices));
	   result != .SUCCESS {
		panic("Failed to list physical devices.")
	}

	picked: PhysicalDevice
	best := 0
	found := false
	for d in devices {
		properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(d, &properties)

		name := cstring(&properties.deviceName[0])

		fmt.printfln("Checking physical device: %v.", name)

		qfamily_indices, ok := find_queue_families(d, surface)
		if !ok {
			fmt.println("No suitable queue family.")
			continue
		}

		// check device extension support
		{
			ext_count: u32
			if result := vk.EnumerateDeviceExtensionProperties(d, nil, &ext_count, nil);
			   result != .SUCCESS {
				panic("Failed to get device extension count.")
			}

			supported_exts := make([]vk.ExtensionProperties, ext_count)
			defer delete(supported_exts)
			if result := vk.EnumerateDeviceExtensionProperties(
				d,
				nil,
				&ext_count,
				raw_data(supported_exts),
			); result != .SUCCESS {
				panic("Failed to list device extensions.")
			}

			all_exts_supported := true
			for required in DEVICE_EXTENSIONS {
				found_ext := false
				for &supported in supported_exts {
					supported := cstring(&supported.extensionName[0])
					if supported == required {
						found_ext = true
						break
					}
				}

				if !found_ext {
					fmt.eprintfln("Required device extension %v not supported.", required)
					all_exts_supported = false
				}
			}
			if !all_exts_supported do continue
		}

		pd_score := get_pdevice_score(properties)
		if pd_score > best {
			picked.handle = d
			delete(picked.name)
			picked.name = strings.clone_from(name)
			picked.queue_family_indices = qfamily_indices
			best = pd_score
			found = true
		}
	}

	return picked, found
}

find_queue_families :: proc(
	pdevice: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> (
	QueueFamilyIndices,
	bool,
) {
	family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(pdevice, &family_count, nil)

	families := make([]vk.QueueFamilyProperties, family_count)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(pdevice, &family_count, raw_data(families))

	graphics_found := false
	present_found := false
	qfamily_indices: QueueFamilyIndices
	for f, index in families {
		if vk.QueueFlag.GRAPHICS in f.queueFlags && !graphics_found {
			qfamily_indices.graphics_family = index
			graphics_found = true
		}

		supports_presentation: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(pdevice, u32(index), surface, &supports_presentation)
		if supports_presentation && !present_found {
			qfamily_indices.present_family = index
			present_found = true
		}

		if graphics_found && present_found {
			return qfamily_indices, true
		}
	}

	return {}, false
}

get_pdevice_score :: proc(pdevice_properties: vk.PhysicalDeviceProperties) -> int {
	#partial switch pdevice_properties.deviceType {
	case .DISCRETE_GPU:
		return 100
	case .INTEGRATED_GPU:
		return 10
	}
	return 1
}

create_logical_device :: proc(pdevice: PhysicalDevice) -> vk.Device {
	families := []int {
		pdevice.queue_family_indices.graphics_family,
		pdevice.queue_family_indices.present_family,
	}
	slice.sort(families)
	unique_families := slice.unique(families)

	queue_priorities: f32 = 1.0

	queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo)
	defer delete(queue_create_infos)
	for f in unique_families {
		info := vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = u32(0),
			queueCount       = 1,
			pQueuePriorities = &queue_priorities,
		}
		append(&queue_create_infos, info)
	}

	device_features := vk.PhysicalDeviceFeatures{}

	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(len(queue_create_infos)),
		pQueueCreateInfos       = raw_data(queue_create_infos),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS[:]),
		pEnabledFeatures        = &device_features,
	}
	// for compatibility with older implementations
	when ENABLE_VALIDATION_LAYERS {
		device_create_info.enabledLayerCount = len(VALIDATION_LAYERS)
		device_create_info.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS[:])
	}

	device: vk.Device
	result := vk.CreateDevice(pdevice.handle, &device_create_info, nil, &device)
	if result != .SUCCESS {
		panic("Failed to create logical device.")
	}
	return device
}

create_render_pass :: proc(device: vk.Device, config: SwapchainConfig) -> vk.RenderPass {
	color_attachment := vk.AttachmentDescription {
		format         = config.format.format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_attachment_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = nil,
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	create_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	render_pass: vk.RenderPass
	result := vk.CreateRenderPass(device, &create_info, nil, &render_pass)
	if result != .SUCCESS {
		panic("Failed to create render pass.")
	}
	return render_pass
}

create_graphics_pipeline :: proc(
	device: vk.Device,
	render_pass: vk.RenderPass,
) -> (
	vk.PipelineLayout,
	vk.Pipeline,
) {
	// shader modules
	vertex_shader_src := #load("shaders/vertex.spv", []u32)
	vertex_shader_module := create_shader_module(device, vertex_shader_src)
	defer {
		vk.DestroyShaderModule(device, vertex_shader_module, nil)
		fmt.println("Vertex shader module destroyed.")
	}
	fmt.println("Vertex shader module created.")

	fragment_shader_src := #load("shaders/fragment.spv", []u32)
	fragment_shader_module := create_shader_module(device, fragment_shader_src)
	defer {
		vk.DestroyShaderModule(device, fragment_shader_module, nil)
		fmt.println("Fragment shader module destroyed.")
	}
	fmt.println("Fragment shader module created.")

	// shader stages
	shader_stages := []vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vertex_shader_module,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = fragment_shader_module,
			pName = "main",
		},
	}

	// dynamic states
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states),
	}

	// vertex input
	binding_desc := get_vertex_binding_description()
	attrib_descs := get_vertex_attribute_descriptions()
	vertex_input_state := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding_desc,
		vertexAttributeDescriptionCount = len(attrib_descs),
		pVertexAttributeDescriptions    = raw_data(attrib_descs[:]),
	}

	// input assembly
	input_assembly_state := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	// viewport and scissor
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		scissorCount  = 1,
		viewportCount = 1,
	}

	// rasterizer
	raster_state := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		lineWidth               = 1,
		cullMode                = {.BACK},
		frontFace               = .CLOCKWISE,
		depthBiasEnable         = false,
	}

	// multisampling
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {._1},
	}

	// color blending
	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable    = false,
	}
	color_blend_state := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	// layout
	layout_create_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}
	layout: vk.PipelineLayout
	result := vk.CreatePipelineLayout(device, &layout_create_info, nil, &layout)
	if result != .SUCCESS {
		panic("Failed to create graphics pipeline layout.")
	}

	// pipeline
	create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = u32(len(shader_stages)),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_state,
		pInputAssemblyState = &input_assembly_state,
		pViewportState      = &viewport_state,
		pRasterizationState = &raster_state,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blend_state,
		pDynamicState       = &dynamic_state,
		layout              = layout,
		renderPass          = render_pass,
		subpass             = 0,
	}

	pipeline: vk.Pipeline
	result = vk.CreateGraphicsPipelines(device, {}, 1, &create_info, nil, &pipeline)
	if result != .SUCCESS {
		panic("Failed to create graphics pipeline.")
	}

	return layout, pipeline
}

create_shader_module :: proc(device: vk.Device, src: []u32) -> vk.ShaderModule {
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = size_of(u32) * len(src),
		pCode    = raw_data(src),
	}

	module: vk.ShaderModule
	result := vk.CreateShaderModule(device, &create_info, nil, &module)
	if result != .SUCCESS {
		panic("Failed to create shader module.")
	}
	return module
}

create_command_pool :: proc(device: vk.Device, queue_family_index: int) -> vk.CommandPool {
	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = u32(queue_family_index),
	}

	pool: vk.CommandPool
	result := vk.CreateCommandPool(device, &create_info, nil, &pool)
	if result != .SUCCESS {
		panic("Failed to create command pool.")
	}
	return pool
}

allocate_command_buffers :: proc(
	device: vk.Device,
	pool: vk.CommandPool,
) -> [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}

	buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer
	result := vk.AllocateCommandBuffers(device, &alloc_info, raw_data(buffers[:]))
	if result != .SUCCESS {
		panic("Failed to allocate command buffer.")
	}
	return buffers
}

record_command_buffer :: proc(
	buffer: vk.CommandBuffer,
	render_pass: vk.RenderPass,
	framebuffer: vk.Framebuffer,
	config: SwapchainConfig,
	pipeline: vk.Pipeline,
	vertex_buffer: ^vk.Buffer,
	index_buffer: vk.Buffer,
) {
	cmd_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	result := vk.BeginCommandBuffer(buffer, &cmd_begin_info)
	if result != .SUCCESS {
		panic("Failed to begin command buffer.")
	}

	clear_color := vk.ClearValue {
		color = vk.ClearColorValue{float32 = {0, 0, 0, 1}},
	}
	render_pass_begin_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = render_pass,
		framebuffer = framebuffer,
		renderArea = {offset = {}, extent = config.extent},
		clearValueCount = 1,
		pClearValues = &clear_color,
	}

	vk.CmdBeginRenderPass(buffer, &render_pass_begin_info, .INLINE)
	vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline)

	offset: vk.DeviceSize = 0
	vk.CmdBindVertexBuffers(buffer, 0, 1, vertex_buffer, &offset)
	vk.CmdBindIndexBuffer(buffer, index_buffer, 0, .UINT16)

	viewport := vk.Viewport {
		width    = f32(config.extent.width),
		height   = f32(config.extent.height),
		maxDepth = 1,
	}
	vk.CmdSetViewport(buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = config.extent,
	}
	vk.CmdSetScissor(buffer, 0, 1, &scissor)

	vk.CmdDrawIndexed(buffer, u32(len(INDICES)), 1, 0, 0, 0)

	vk.CmdEndRenderPass(buffer)

	result = vk.EndCommandBuffer(buffer)
	if result != .SUCCESS {
		panic("Failed to end command buffer.")
	}
}

SyncObjects :: struct {
	image_available: vk.Semaphore,
	render_finished: vk.Semaphore,
	in_flight:       vk.Fence,
}

destroy_sync_objects :: proc(device: vk.Device, objs: SyncObjects) {
	vk.DestroySemaphore(device, objs.image_available, nil)
	vk.DestroySemaphore(device, objs.render_finished, nil)
	vk.DestroyFence(device, objs.in_flight, nil)
}

create_sync_objects :: proc(device: vk.Device) -> [MAX_FRAMES_IN_FLIGHT]SyncObjects {
	objs: [MAX_FRAMES_IN_FLIGHT]SyncObjects

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	for &o in objs {
		result := vk.CreateSemaphore(device, &semaphore_info, nil, &o.image_available)
		if result != .SUCCESS {
			panic("Failed to create image available semaphore.")
		}
		result = vk.CreateSemaphore(device, &semaphore_info, nil, &o.render_finished)
		if result != .SUCCESS {
			panic("Failed to create render finished semaphore.")
		}
		result = vk.CreateFence(device, &fence_info, nil, &o.in_flight)
		if result != .SUCCESS {
			panic("Failed to create fence.")
		}
	}

	return objs
}
