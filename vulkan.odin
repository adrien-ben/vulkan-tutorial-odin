package main

import "base:runtime"
import "core:log"
import "core:slice"
import "core:strings"
import "core:time"
import "vendor:glfw"
import vk "vendor:vulkan"

WIN_WIDTH :: 1280
WIN_HEIGHT :: 1024

MAX_FRAMES_IN_FLIGHT :: 2

ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, true)
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

DEVICE_EXTENSIONS := [?]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

rt_ctx: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	rt_ctx = context

	if !glfw.Init() {
		panic("Failed to init GLFW.")
	}
	defer {
		glfw.Terminate()
		log.debug("GLFW terminated.")
	}
	log.debug("GLFW initialized.")

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window := glfw.CreateWindow(WIN_WIDTH, WIN_HEIGHT, "Vulkan", nil, nil)
	if window == nil {
		panic("Failed to create GLFW window.")
	}
	defer {
		glfw.DestroyWindow(window)
		log.debug("Window destroyed.")
	}
	log.debug("Window created.")

	vulkan_ctx := create_vk_context(window)
	defer {
		destroy_vk_context(vulkan_ctx)
	}

	command_buffers := allocate_command_buffers(&vulkan_ctx)
	log.debug("Vulkan command buffer allocated.")

	swapchain_support := query_swapchain_support(&vulkan_ctx)
	defer {
		delete_swapchain_support_details(swapchain_support)
	}
	swapchain_config := select_swapchain_config(swapchain_support, window)

	color_buffer := create_color_buffer(&vulkan_ctx, swapchain_config)
	defer {
		destroy_attachment_buffer(&vulkan_ctx, color_buffer)
		log.debug("Color buffer destroyed.")
	}
	log.debug("Color buffer created.")

	depth_buffer := create_depth_buffer(&vulkan_ctx, swapchain_config)
	defer {
		destroy_attachment_buffer(&vulkan_ctx, depth_buffer)
		log.debug("Depth buffer destroyed.")
	}
	log.debug("Depth buffer created.")

	render_pass := create_render_pass(&vulkan_ctx, swapchain_config, depth_buffer.format)
	defer {
		vk.DestroyRenderPass(vulkan_ctx.device, render_pass, nil)
		log.debug("Vulkan render pass destroyed.")
	}
	log.debug("Vulkan render pass created.")

	swapchain := create_swapchain(
		&vulkan_ctx,
		color_buffer,
		depth_buffer,
		render_pass,
		swapchain_config,
	)
	defer {
		destroy_swapchain(&vulkan_ctx, swapchain)
		log.debug("Swapchain destroyed.")
	}
	log.debug("Swapchain created.")

	descriptor_set_layout := create_descriptor_set_layout(&vulkan_ctx)
	defer {
		vk.DestroyDescriptorSetLayout(vulkan_ctx.device, descriptor_set_layout, nil)
		log.debug("Descriptor set layout destroyed.")
	}
	log.debug("Descriptor set layout created.")

	graphics_pipeline_layout, graphics_pipeline := create_graphics_pipeline(
		&vulkan_ctx,
		render_pass,
		descriptor_set_layout,
	)
	defer {
		vk.DestroyPipelineLayout(vulkan_ctx.device, graphics_pipeline_layout, nil)
		vk.DestroyPipeline(vulkan_ctx.device, graphics_pipeline, nil)
		log.debug("Vulkan graphics pipeline and layout destroyed.")
	}
	log.debug("Vulkan graphics pipeline and layout created.")

	sync_objs := create_sync_objects(&vulkan_ctx)
	defer {
		for o in sync_objs {
			destroy_sync_objects(&vulkan_ctx, o)
		}
		log.debug("Vulkan sync objects destroyed.")
	}
	log.debug("Vulkan sync objects created.")

	ubo_buffers := create_uniform_buffers(&vulkan_ctx)
	defer {
		for b in ubo_buffers {
			destroy_ubo_buffer(&vulkan_ctx, b)
		}
		log.debug("UBO buffers destroyed.")
	}
	log.debug("UBO buffers created.")

	model := load_model(&vulkan_ctx)
	defer {
		destroy_model(&vulkan_ctx, model)
		log.debug("Model destroyed.")
	}
	log.debug("Model created.")

	descriptor_pool := create_descriptor_pool(&vulkan_ctx)
	defer {
		vk.DestroyDescriptorPool(vulkan_ctx.device, descriptor_pool, nil)
		log.debug("Descriptor pool destroyed.")
	}
	log.debug("Descriptor pool created.")

	descriptor_sets := create_descriptor_sets(
		&vulkan_ctx,
		descriptor_pool,
		descriptor_set_layout,
		ubo_buffers,
		model,
	)

	last := time.tick_now()
	rotation_degs: f32 = 0

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
			log.debug("Window has been resized.")
			fb_w = w
			fb_h = h
			is_swapchain_dirty = true
			continue
		}

		result: vk.Result
		if is_swapchain_dirty {
			color_buffer, depth_buffer, swapchain = recreate_swapchain(
				&vulkan_ctx,
				window,
				color_buffer,
				depth_buffer,
				render_pass,
				swapchain,
			)
			log.debug("Swapchain recreated.")
			is_swapchain_dirty = false
		}

		sync_obj := sync_objs[current_frame]
		command_buffer := command_buffers[current_frame]

		// wait for previous frame
		result = vk.WaitForFences(vulkan_ctx.device, 1, &sync_obj.in_flight, true, max(u64))
		if result != .SUCCESS {
			log.errorf("Failed to wait for fence: %v.", result)
			break
		}

		// acquire a new image from the swapchain
		image_index: u32
		result = vk.AcquireNextImageKHR(
			vulkan_ctx.device,
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
			log.errorf("Failed to acquire swapchain image: %v.", result)
			break
		}

		result = vk.ResetFences(vulkan_ctx.device, 1, &sync_obj.in_flight)
		if result != .SUCCESS {
			log.errorf("Failed to reset fence: %v.", result)
			break
		}

		// compute model rotation
		elasped_secs := f32(time.duration_seconds(time.tick_since(last)))
		last = time.tick_now()

		if glfw.GetKey(window, glfw.KEY_LEFT) == glfw.PRESS {
			rotation_degs -= 90 * elasped_secs
			if rotation_degs < -360 {
				rotation_degs += 360
			}
		} else if glfw.GetKey(window, glfw.KEY_RIGHT) == glfw.PRESS {
			rotation_degs += 90 * elasped_secs
			if rotation_degs > 360 {
				rotation_degs -= 360
			}
		}

		// record and submit drawing commands
		result = vk.ResetCommandBuffer(command_buffer, nil)
		if result != .SUCCESS {
			log.errorf("Failed to reset command buffer: %v.", result)
			break
		}

		record_command_buffer(
			command_buffer,
			render_pass,
			swapchain.framebuffers[image_index],
			swapchain.config,
			graphics_pipeline_layout,
			graphics_pipeline,
			model,
			descriptor_sets[current_frame],
		)

		update_uniform_buffer(ubo_buffers[current_frame], swapchain.config, rotation_degs)

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
		result = vk.QueueSubmit(vulkan_ctx.graphics_queue, 1, &submit_info, sync_obj.in_flight)
		if result != .SUCCESS {
			log.errorf("Failed to submit: %v.", result)
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
		result = vk.QueuePresentKHR(vulkan_ctx.present_queue, &present_info)
		if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
			is_swapchain_dirty = true
		} else if result != .SUCCESS {
			log.errorf("Failed to acquire swapchain image: %v.", result)
			break
		}

		current_frame = (current_frame + 1) % MAX_FRAMES_IN_FLIGHT
	}

	vk.DeviceWaitIdle(vulkan_ctx.device)
}

VkContext :: struct {
	instance:        vk.Instance,
	debug_messenger: Maybe(vk.DebugUtilsMessengerEXT),
	surface:         vk.SurfaceKHR,
	pdevice:         PhysicalDevice,
	device:          vk.Device,
	graphics_queue:  vk.Queue,
	present_queue:   vk.Queue,
	command_pool:    vk.CommandPool,
}

destroy_vk_context :: proc(using ctx: VkContext) {
	vk.DestroyCommandPool(device, command_pool, nil)
	log.debug("Vulkan command pool destroyed.")

	vk.DestroyDevice(device, nil)
	log.debug("Vulkan logical device destroyed.")

	destroy_physical_device(pdevice)

	vk.DestroySurfaceKHR(instance, surface, nil)
	log.debug("Vulkan surface destroyed.")

	if dm, ok := debug_messenger.?; ok {
		vk.DestroyDebugUtilsMessengerEXT(instance, dm, nil)
		log.debug("Vulkan debug messenger destroyed.")
	}

	vk.DestroyInstance(instance, nil)
	log.debug("Vulkan instance destroyed.")
}

create_vk_context :: proc(window: glfw.WindowHandle) -> (ctx: VkContext) {
	vk.load_proc_addresses((rawptr)(glfw.GetInstanceProcAddress))

	ctx.instance = create_instance()
	log.debug("Vulkan instance created.")

	vk.load_proc_addresses(ctx.instance)

	when ENABLE_VALIDATION_LAYERS {
		ctx.debug_messenger = setup_debug_messenger(ctx.instance)
		log.debug("Vulkan debug messenger created.")
	}

	ctx.surface = create_surface(ctx.instance, window)
	log.debug("Vulkan surface created.")

	found: bool
	ctx.pdevice, found = pick_physical_device(ctx.instance, ctx.surface)
	if !found {
		panic("No suitable Vulkan physical device found.")
	}
	log.infof("Vulkan physical device selected: %#v.", ctx.pdevice)

	ctx.device = create_logical_device(ctx.pdevice)
	log.debug("Vulkan logical device created.")

	vk.GetDeviceQueue(
		ctx.device,
		u32(ctx.pdevice.queue_family_indices.graphics_family),
		0,
		&ctx.graphics_queue,
	)

	vk.GetDeviceQueue(
		ctx.device,
		u32(ctx.pdevice.queue_family_indices.present_family),
		0,
		&ctx.present_queue,
	)

	ctx.command_pool = create_command_pool(
		ctx.device,
		ctx.pdevice.queue_family_indices.graphics_family,
	)
	log.debug("Vulkan command pool created.")

	return
}

create_instance :: proc() -> (instance: vk.Instance) {
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
				log.warnf("Required extension %v not supported.", required)
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
				log.warnf("Required validation layer %v not supported.", required)
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

	result = vk.CreateInstance(&create_info, nil, &instance)
	if result != .SUCCESS {
		panic("Failed to create instance.")
	}

	return
}

when ENABLE_VALIDATION_LAYERS {
	messenger_callback :: proc "system" (
		severity: vk.DebugUtilsMessageSeverityFlagsEXT,
		_: vk.DebugUtilsMessageTypeFlagsEXT,
		data: ^vk.DebugUtilsMessengerCallbackDataEXT,
		_: rawptr,
	) -> b32 {
		context = rt_ctx

		switch severity {
		case {.ERROR}:
			log.error("validation:", data.pMessage)
		case {.WARNING}:
			log.warn("validation:", data.pMessage)
		case {.INFO}:
			log.info("validation:", data.pMessage)
		case:
			log.debug("validation:", data.pMessage)
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

	setup_debug_messenger :: proc(
		instance: vk.Instance,
	) -> (
		messenger: vk.DebugUtilsMessengerEXT,
	) {
		create_info := create_setup_messenger_create_info()
		result := vk.CreateDebugUtilsMessengerEXT(instance, &create_info, nil, &messenger)
		if result != .SUCCESS {
			panic("Failed to create debug messenger.")
		}
		return
	}
}

create_surface :: proc(
	instance: vk.Instance,
	window: glfw.WindowHandle,
) -> (
	surface: vk.SurfaceKHR,
) {
	result := glfw.CreateWindowSurface(instance, window, nil, &surface)
	if result != .SUCCESS {
		panic("Failed to create surface.")
	}
	return
}

PhysicalDevice :: struct {
	handle:               vk.PhysicalDevice `fmt:"-"`,
	name:                 string,
	queue_family_indices: QueueFamilyIndices,
	properties:           vk.PhysicalDeviceProperties `fmt:"-"`,
	max_sample_count:     vk.SampleCountFlag,
}

destroy_physical_device :: proc(using pdevice: PhysicalDevice) {
	delete(name)
}

QueueFamilyIndices :: struct {
	graphics_family: int,
	present_family:  int,
}

pick_physical_device :: proc(
	instance: vk.Instance,
	surface: vk.SurfaceKHR,
) -> (
	picked: PhysicalDevice,
	found: bool,
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

	best := 0
	for d in devices {
		properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(d, &properties)

		name := cstring(&properties.deviceName[0])

		log.debugf("Checking physical device: %v.", name)

		qfamily_indices, ok := find_queue_families(d, surface)
		if !ok {
			log.debug("No suitable queue family.")
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
					log.debugf("Required device extension %v not supported.", required)
					all_exts_supported = false
				}
			}
			if !all_exts_supported do continue
		}

		// check features support
		supported_features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceFeatures(d, &supported_features)
		if !supported_features.samplerAnisotropy {
			log.debug("Sampler anisotropy is not supported.")
			continue
		}

		pd_score := get_pdevice_score(properties)
		if pd_score > best {
			picked.handle = d
			delete(picked.name)
			picked.name = strings.clone_from(name)
			picked.queue_family_indices = qfamily_indices
			picked.properties = properties
			picked.max_sample_count = find_max_usable_sample_count(properties)

			best = pd_score
			found = true
		}
	}

	return
}

find_queue_families :: proc(
	pdevice: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> (
	qfamily_indices: QueueFamilyIndices,
	found: bool,
) {
	family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(pdevice, &family_count, nil)

	families := make([]vk.QueueFamilyProperties, family_count)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(pdevice, &family_count, raw_data(families))

	graphics_found := false
	present_found := false
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
			found = true
			return
		}
	}

	return
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

find_max_usable_sample_count :: proc(
	pdevice_properties: vk.PhysicalDeviceProperties,
) -> (
	s: vk.SampleCountFlag,
) {
	supported_counts :=
		pdevice_properties.limits.framebufferColorSampleCounts &
		pdevice_properties.limits.framebufferDepthSampleCounts

	flags := []vk.SampleCountFlag{._64, ._32, ._16, ._8, ._4, ._2}

	for f in flags {
		if (supported_counts & {f}) == {f} {
			s = f
			return
		}
	}

	return
}

create_logical_device :: proc(pdevice: PhysicalDevice) -> (device: vk.Device) {
	families := []int {
		pdevice.queue_family_indices.graphics_family,
		pdevice.queue_family_indices.present_family,
	}
	slice.sort(families)
	unique_families := slice.unique(families)

	queue_priorities: f32 = 1.0

	queue_create_infos: [dynamic]vk.DeviceQueueCreateInfo
	defer delete(queue_create_infos)
	for f in unique_families {
		info := vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = u32(f),
			queueCount       = 1,
			pQueuePriorities = &queue_priorities,
		}
		append(&queue_create_infos, info)
	}

	device_features := vk.PhysicalDeviceFeatures {
		samplerAnisotropy = true,
	}

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

	result := vk.CreateDevice(pdevice.handle, &device_create_info, nil, &device)
	if result != .SUCCESS {
		panic("Failed to create logical device.")
	}
	return
}

create_render_pass :: proc(
	using ctx: ^VkContext,
	config: SwapchainConfig,
	depth_format: vk.Format,
) -> (
	render_pass: vk.RenderPass,
) {
	attachments := []vk.AttachmentDescription {
		// color
		{
			format = config.format.format,
			samples = {pdevice.max_sample_count},
			loadOp = .CLEAR,
			storeOp = .STORE,
			stencilLoadOp = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout = .UNDEFINED,
			finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
		},
		// depth
		{
			format = depth_format,
			samples = {ctx.pdevice.max_sample_count},
			loadOp = .CLEAR,
			storeOp = .DONT_CARE,
			stencilLoadOp = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout = .UNDEFINED,
			finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		},
		// resolve for msaa
		{
			format = config.format.format,
			samples = {._1},
			loadOp = .DONT_CARE,
			storeOp = .STORE,
			stencilLoadOp = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout = .UNDEFINED,
			finalLayout = .PRESENT_SRC_KHR,
		},
	}

	color_attachment_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	depth_attachment_ref := vk.AttachmentReference {
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	resolve_attachment_ref := vk.AttachmentReference {
		attachment = 2,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &color_attachment_ref,
		pDepthStencilAttachment = &depth_attachment_ref,
		pResolveAttachments     = &resolve_attachment_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		srcAccessMask = nil,
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
	}

	create_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = u32(len(attachments)),
		pAttachments    = raw_data(attachments),
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	result := vk.CreateRenderPass(device, &create_info, nil, &render_pass)
	if result != .SUCCESS {
		panic("Failed to create render pass.")
	}
	return
}

create_graphics_pipeline :: proc(
	using ctx: ^VkContext,
	render_pass: vk.RenderPass,
	descriptor_set_layout: vk.DescriptorSetLayout,
) -> (
	layout: vk.PipelineLayout,
	pipeline: vk.Pipeline,
) {
	// shader modules
	vertex_shader_src := #load("shaders/vertex.spv", []u32)
	vertex_shader_module := create_shader_module(device, vertex_shader_src)
	defer {
		vk.DestroyShaderModule(device, vertex_shader_module, nil)
		log.debug("Vertex shader module destroyed.")
	}
	log.debug("Vertex shader module created.")

	fragment_shader_src := #load("shaders/fragment.spv", []u32)
	fragment_shader_module := create_shader_module(device, fragment_shader_src)
	defer {
		vk.DestroyShaderModule(device, fragment_shader_module, nil)
		log.debug("Fragment shader module destroyed.")
	}
	log.debug("Fragment shader module created.")

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
		cullMode                = {},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
	}

	// multisampling
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {ctx.pdevice.max_sample_count},
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

	// depth stencil
	depth_stencil_state := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS,
	}

	// layout
	descriptor_set_layout := descriptor_set_layout
	layout_create_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &descriptor_set_layout,
	}
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
		pDepthStencilState  = &depth_stencil_state,
		pDynamicState       = &dynamic_state,
		layout              = layout,
		renderPass          = render_pass,
		subpass             = 0,
	}

	result = vk.CreateGraphicsPipelines(device, {}, 1, &create_info, nil, &pipeline)
	if result != .SUCCESS {
		panic("Failed to create graphics pipeline.")
	}

	return
}

create_shader_module :: proc(device: vk.Device, src: []u32) -> (module: vk.ShaderModule) {
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = size_of(u32) * len(src),
		pCode    = raw_data(src),
	}

	result := vk.CreateShaderModule(device, &create_info, nil, &module)
	if result != .SUCCESS {
		panic("Failed to create shader module.")
	}
	return
}
