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

INSTANCE_EXTENSIONS := [?]cstring{vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME}

ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

DEVICE_EXTENSIONS := [?]cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
	vk.KHR_DEPTH_STENCIL_RESOLVE_EXTENSION_NAME,
	vk.KHR_CREATE_RENDERPASS_2_EXTENSION_NAME,
	vk.KHR_MULTIVIEW_EXTENSION_NAME,
	vk.KHR_MAINTENANCE_2_EXTENSION_NAME,
	vk.KHR_SYNCHRONIZATION_2_EXTENSION_NAME,
}

DisplayMode :: enum u32 {
	Colors,
	Normals,
}

rt_ctx: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	rt_ctx = context

	display_mode: DisplayMode

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

	swapchain := create_swapchain(&vulkan_ctx, color_buffer, depth_buffer, swapchain_config)
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

	graphics_pipeline_layout := create_graphics_pipeline_layout(&vulkan_ctx, descriptor_set_layout)
	defer {
		vk.DestroyPipelineLayout(vulkan_ctx.device, graphics_pipeline_layout, nil)
		log.debug("Vulkan graphics pipeline layout destroyed.")
	}
	log.debug("Vulkan graphics pipeline layout created.")

	pipeline_cache: vk.PipelineCache
	when ENABLE_PIPELINE_CACHE {
		pipeline_cache = create_pipeline_cache(&vulkan_ctx)
		defer {
			save_and_destroy_pipeline_cache(&vulkan_ctx, pipeline_cache)
			log.debug("Pipeline cache destroyed.")
		}
		log.debug("Pipeline cache created.")
	}

	graphics_pipeline := create_graphics_pipeline(
		&vulkan_ctx,
		pipeline_cache,
		graphics_pipeline_layout,
		color_buffer.format,
		depth_buffer.format,
		display_mode,
	)
	defer {
		vk.DestroyPipeline(vulkan_ctx.device, graphics_pipeline, nil)
		log.debug("Vulkan graphics pipeline destroyed.")
	}
	log.debug("Vulkan graphics pipeline created.")

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

		// check if display mode was changed
		new_display_mode := display_mode
		if glfw.GetKey(window, glfw.KEY_1) == glfw.PRESS {
			new_display_mode = .Colors
		} else if glfw.GetKey(window, glfw.KEY_2) == glfw.PRESS {
			new_display_mode = .Normals
		}

		if display_mode != new_display_mode {
			display_mode = new_display_mode
			vk.DeviceWaitIdle(vulkan_ctx.device)
			vk.DestroyPipeline(vulkan_ctx.device, graphics_pipeline, nil)
			graphics_pipeline = create_graphics_pipeline(
				&vulkan_ctx,
				pipeline_cache,
				graphics_pipeline_layout,
				color_buffer.format,
				depth_buffer.format,
				display_mode,
			)
			log.debug("Graphics pipeline recreated after display mode change.")
		}

		result: vk.Result
		if is_swapchain_dirty {
			color_buffer, depth_buffer, swapchain = recreate_swapchain(
				&vulkan_ctx,
				window,
				color_buffer,
				depth_buffer,
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
			&vulkan_ctx,
			command_buffer,
			swapchain.config,
			color_buffer,
			depth_buffer,
			swapchain.images[image_index],
			swapchain.views[image_index],
			graphics_pipeline_layout,
			graphics_pipeline,
			model,
			descriptor_sets[current_frame],
		)

		update_uniform_buffer(ubo_buffers[current_frame], swapchain.config, rotation_degs)

		cmd_buffer_info := vk.CommandBufferSubmitInfo {
			sType         = .COMMAND_BUFFER_SUBMIT_INFO,
			commandBuffer = command_buffer,
		}
		wait_sem_info := vk.SemaphoreSubmitInfo {
			sType     = .SEMAPHORE_SUBMIT_INFO,
			semaphore = sync_obj.image_available,
			stageMask = {.COLOR_ATTACHMENT_OUTPUT},
		}
		signal_sem_info := vk.SemaphoreSubmitInfo {
			sType     = .SEMAPHORE_SUBMIT_INFO,
			semaphore = sync_obj.render_finished,
			stageMask = {.COLOR_ATTACHMENT_OUTPUT},
		}
		submit_info := vk.SubmitInfo2 {
			sType                    = .SUBMIT_INFO_2,
			commandBufferInfoCount   = 1,
			pCommandBufferInfos      = &cmd_buffer_info,
			waitSemaphoreInfoCount   = 1,
			pWaitSemaphoreInfos      = &wait_sem_info,
			signalSemaphoreInfoCount = 1,
			pSignalSemaphoreInfos    = &signal_sem_info,
		}
		result = vk.QueueSubmit2KHR(vulkan_ctx.graphics_queue, 1, &submit_info, sync_obj.in_flight)
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
	append(&required_exts, ..INSTANCE_EXTENSIONS[:])
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
		dynamic_rendering_features := vk.PhysicalDeviceDynamicRenderingFeatures {
			sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
		}
		synchronization2_features := vk.PhysicalDeviceSynchronization2Features {
			sType = .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES,
			pNext = &dynamic_rendering_features,
		}
		supported_features := vk.PhysicalDeviceFeatures2 {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
			pNext = &synchronization2_features,
		}
		vk.GetPhysicalDeviceFeatures2KHR(d, &supported_features)
		if !supported_features.features.samplerAnisotropy {
			log.debug("Sampler anisotropy is not supported.")
			continue
		}
		if !dynamic_rendering_features.dynamicRendering {
			log.debug("Dynamic rendering is not supported.")
			continue
		}
		if !synchronization2_features.synchronization2 {
			log.debug("Synchronization2 is not supported.")
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

	dynamic_rendering_features := vk.PhysicalDeviceDynamicRenderingFeatures {
		sType            = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
		dynamicRendering = true,
	}
	synchronization2_features := vk.PhysicalDeviceSynchronization2Features {
		sType            = .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES,
		synchronization2 = true,
		pNext            = &dynamic_rendering_features,
	}
	device_features := vk.PhysicalDeviceFeatures {
		samplerAnisotropy = true,
	}
	device_features2 := vk.PhysicalDeviceFeatures2 {
		sType    = .PHYSICAL_DEVICE_FEATURES_2,
		pNext    = &synchronization2_features,
		features = device_features,
	}

	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(len(queue_create_infos)),
		pQueueCreateInfos       = raw_data(queue_create_infos),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS[:]),
		pNext                   = &device_features2,
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
