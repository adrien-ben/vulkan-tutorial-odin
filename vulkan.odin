package main

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

WIN_WIDTH :: 800
WIN_HEIGHT :: 600

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
	glfw.WindowHint(glfw.RESIZABLE, false)
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

	swapchain := create_swapchain(device, pdevice, surface, window)
	defer {
		vk.DestroySwapchainKHR(device, swapchain.handle, nil)
		fmt.println("Vulkan swapchain destroyed.")
	}
	fmt.printfln("Vulkan swapchain created: %#v.", swapchain)

	swapchain_images := get_swapchain_images(device, swapchain)
	defer {
		delete(swapchain_images)
	}

	swapchain_image_views := create_swapchain_image_views(device, swapchain, swapchain_images)
	defer {
		for view in swapchain_image_views {
			vk.DestroyImageView(device, view, nil)
		}
		delete(swapchain_image_views)
		fmt.println("Vulkan swapchain image views destroyed.")
	}
	fmt.println("Vulkan swapchain image views created.")

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
	}
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

SwapchainSupportDetails :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

delete_swapchain_support_details :: proc(details: SwapchainSupportDetails) {
	delete(details.formats)
	delete(details.present_modes)
}

query_swapchain_support :: proc(
	pdevice: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> SwapchainSupportDetails {
	details: SwapchainSupportDetails

	result := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(pdevice, surface, &details.capabilities)
	if result != .SUCCESS {
		panic("Failed to get physical device surface capabilities.")
	}

	fmt_count: u32
	result = vk.GetPhysicalDeviceSurfaceFormatsKHR(pdevice, surface, &fmt_count, nil)
	if result != .SUCCESS {
		panic("Failed to get physical device surface format count.")
	}
	details.formats = make([]vk.SurfaceFormatKHR, fmt_count)
	result = vk.GetPhysicalDeviceSurfaceFormatsKHR(
		pdevice,
		surface,
		&fmt_count,
		raw_data(details.formats),
	)
	if result != .SUCCESS {
		panic("Failed to list physical device surface formats.")
	}

	mode_count: u32
	result = vk.GetPhysicalDeviceSurfacePresentModesKHR(pdevice, surface, &mode_count, nil)
	if result != .SUCCESS {
		panic("Failed to get physical device surface present mode count.")
	}
	details.present_modes = make([]vk.PresentModeKHR, mode_count)
	result = vk.GetPhysicalDeviceSurfacePresentModesKHR(
		pdevice,
		surface,
		&mode_count,
		raw_data(details.present_modes),
	)
	if result != .SUCCESS {
		panic("Failed to get physical device surface present modes.")
	}

	return details
}

Swapchain :: struct {
	handle: vk.SwapchainKHR,
	format: vk.SurfaceFormatKHR,
	extent: vk.Extent2D,
}

create_swapchain :: proc(
	device: vk.Device,
	pdevice: PhysicalDevice,
	surface: vk.SurfaceKHR,
	window: glfw.WindowHandle,
) -> Swapchain {
	details := query_swapchain_support(pdevice.handle, surface)
	defer {
		delete_swapchain_support_details(details)
	}

	// select format
	format := details.formats[0]
	for f in details.formats {
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			format = f
		}
	}

	// select present mode
	present_mode := vk.PresentModeKHR.FIFO
	for m in details.present_modes {
		if m == .MAILBOX {
			present_mode = m
		}
	}

	// select swapchain extent
	extent: vk.Extent2D
	if details.capabilities.currentExtent.width != max(u32) {
		extent = details.capabilities.currentExtent
	} else {
		w, h := glfw.GetFramebufferSize(window)
		extent.width = clamp(
			u32(w),
			details.capabilities.minImageExtent.width,
			details.capabilities.maxImageExtent.width,
		)
		extent.height = clamp(
			u32(h),
			details.capabilities.minImageExtent.height,
			details.capabilities.maxImageExtent.height,
		)
	}

	// select image count
	image_count := details.capabilities.minImageCount + 1
	if details.capabilities.maxImageCount > 0 && image_count > details.capabilities.maxImageCount {
		image_count = details.capabilities.maxImageCount
	}

	// create the swapchain
	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface,
		minImageCount    = image_count,
		imageFormat      = format.format,
		imageColorSpace  = format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = details.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
	}

	q_indices := []u32 {
		u32(pdevice.queue_family_indices.graphics_family),
		u32(pdevice.queue_family_indices.present_family),
	}
	if pdevice.queue_family_indices.graphics_family !=
	   pdevice.queue_family_indices.present_family {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = u32(len(q_indices))
		create_info.pQueueFamilyIndices = raw_data(q_indices)
	} else {
		create_info.imageSharingMode = .EXCLUSIVE
	}

	swapchain: vk.SwapchainKHR
	result := vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain)
	if result != .SUCCESS {
		panic("Failed to create swapchain.")
	}
	return Swapchain{handle = swapchain, format = format, extent = extent}
}

get_swapchain_images :: proc(device: vk.Device, swapchain: Swapchain) -> []vk.Image {
	img_count: u32
	result := vk.GetSwapchainImagesKHR(device, swapchain.handle, &img_count, nil)
	if result != .SUCCESS {
		panic("Failed to get swapchain image count.")
	}
	imgs := make([]vk.Image, img_count)
	result = vk.GetSwapchainImagesKHR(device, swapchain.handle, &img_count, raw_data(imgs))
	if result != .SUCCESS {
		panic("Failed to get swapchain images.")
	}
	return imgs
}

create_swapchain_image_views :: proc(
	device: vk.Device,
	swapchain: Swapchain,
	imgs: []vk.Image,
) -> []vk.ImageView {
	views := make([]vk.ImageView, len(imgs))
	for img, index in imgs {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = img,
			viewType = .D2,
			format = swapchain.format.format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		result := vk.CreateImageView(device, &create_info, nil, &views[index])
		if result != .SUCCESS {
			panic("Failed to create swapchain image view.")
		}
	}
	return views
}
