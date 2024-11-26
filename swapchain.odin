package main

import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

SwapchainSupportDetails :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

SwapchainConfig :: struct {
	format:       vk.SurfaceFormatKHR,
	present_mode: vk.PresentModeKHR,
	extent:       vk.Extent2D,
	image_count:  u32,
	transform:    vk.SurfaceTransformFlagsKHR,
}

Swapchain :: struct {
	handle:       vk.SwapchainKHR,
	config:       SwapchainConfig,
	images:       []vk.Image,
	views:        []vk.ImageView,
	framebuffers: []vk.Framebuffer,
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

select_swapchain_config :: proc(
	details: SwapchainSupportDetails,
	window: glfw.WindowHandle,
) -> SwapchainConfig {
	config: SwapchainConfig

	// select format
	config.format = details.formats[0]
	for f in details.formats {
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			config.format = f
		}
	}

	// select present mode
	config.present_mode = vk.PresentModeKHR.FIFO
	for m in details.present_modes {
		if m == .MAILBOX {
			config.present_mode = m
		}
	}

	// select swapchain extent
	if details.capabilities.currentExtent.width != max(u32) {
		config.extent = details.capabilities.currentExtent
	} else {
		w, h := glfw.GetFramebufferSize(window)
		config.extent.width = clamp(
			u32(w),
			details.capabilities.minImageExtent.width,
			details.capabilities.maxImageExtent.width,
		)
		config.extent.height = clamp(
			u32(h),
			details.capabilities.minImageExtent.height,
			details.capabilities.maxImageExtent.height,
		)
	}

	// select image count
	config.image_count = details.capabilities.minImageCount + 1
	if details.capabilities.maxImageCount > 0 &&
	   config.image_count > details.capabilities.maxImageCount {
		config.image_count = details.capabilities.maxImageCount
	}

	// set transform
	config.transform = details.capabilities.currentTransform

	return config
}

destroy_swapchain :: proc(device: vk.Device, swapchain: Swapchain) {
	for fb in swapchain.framebuffers {
		vk.DestroyFramebuffer(device, fb, nil)
	}
	delete(swapchain.framebuffers)
	fmt.println("Vulkan swapchain framebuffers destroyed.")


	for view in swapchain.views {
		vk.DestroyImageView(device, view, nil)
	}
	delete(swapchain.views)
	fmt.println("Vulkan swapchain image views destroyed.")

	delete(swapchain.images)

	vk.DestroySwapchainKHR(device, swapchain.handle, nil)
	fmt.println("Vulkan swapchain destroyed.")
}

create_swapchain :: proc(
	device: vk.Device,
	pdevice: PhysicalDevice,
	surface: vk.SurfaceKHR,
	color_buffer: AttachmentBuffer,
	depth_buffer: AttachmentBuffer,
	render_pass: vk.RenderPass,
	config: SwapchainConfig,
) -> Swapchain {
	// create the swapchain
	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface,
		minImageCount    = config.image_count,
		imageFormat      = config.format.format,
		imageColorSpace  = config.format.colorSpace,
		imageExtent      = config.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = config.transform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = config.present_mode,
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

	swapchain := Swapchain {
		config = config,
	}

	result := vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain.handle)
	if result != .SUCCESS {
		panic("Failed to create Vulkan swapchain.")
	}

	swapchain.images = get_swapchain_images(device, swapchain.handle)
	fmt.println("Vulkan swapchain image created.")

	swapchain.views = create_swapchain_image_views(device, config, swapchain.images)
	fmt.println("Vulkan swapchain image views created.")

	swapchain.framebuffers = create_swapchain_framebuffers(
		device,
		config,
		swapchain.views,
		color_buffer,
		depth_buffer,
		render_pass,
	)
	fmt.println("Vulkan swapchain framebuffers created.")

	return swapchain
}

recreate_swapchain :: proc(
	device: vk.Device,
	pdevice: PhysicalDevice,
	window: glfw.WindowHandle,
	surface: vk.SurfaceKHR,
	color_buffer: AttachmentBuffer,
	depth_buffer: AttachmentBuffer,
	sample_count: vk.SampleCountFlag,
	render_pass: vk.RenderPass,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
	current: Swapchain,
) -> (
	AttachmentBuffer,
	AttachmentBuffer,
	Swapchain,
) {
	result := vk.DeviceWaitIdle(device)
	if result != .SUCCESS {
		panic("Failed to wait for device to be idle.")
	}

	destroy_attachment_buffer(device, color_buffer)
	destroy_attachment_buffer(device, depth_buffer)
	destroy_swapchain(device, current)

	swapchain_support := query_swapchain_support(pdevice.handle, surface)
	defer {
		delete_swapchain_support_details(swapchain_support)
	}
	swapchain_config := select_swapchain_config(swapchain_support, window)

	color_buffer := create_color_buffer(
		device,
		pdevice.handle,
		swapchain_config,
		command_pool,
		queue,
		sample_count,
	)
	depth_buffer := create_depth_buffer(
		device,
		pdevice.handle,
		swapchain_config,
		command_pool,
		queue,
		sample_count,
	)
	swapchain := create_swapchain(
		device,
		pdevice,
		surface,
		color_buffer,
		depth_buffer,
		render_pass,
		swapchain_config,
	)

	return color_buffer, depth_buffer, swapchain
}

get_swapchain_images :: proc(device: vk.Device, swapchain: vk.SwapchainKHR) -> []vk.Image {
	img_count: u32
	result := vk.GetSwapchainImagesKHR(device, swapchain, &img_count, nil)
	if result != .SUCCESS {
		panic("Failed to get swapchain image count.")
	}
	imgs := make([]vk.Image, img_count)
	result = vk.GetSwapchainImagesKHR(device, swapchain, &img_count, raw_data(imgs))
	if result != .SUCCESS {
		panic("Failed to get swapchain images.")
	}
	return imgs
}

create_swapchain_image_views :: proc(
	device: vk.Device,
	config: SwapchainConfig,
	imgs: []vk.Image,
) -> []vk.ImageView {
	views := make([]vk.ImageView, len(imgs))
	for img, index in imgs {
		views[index] = create_image_view(
			device,
			img,
			config.format.format,
			{.COLOR},
			mip_levels = 1,
		)
	}
	return views
}

create_swapchain_framebuffers :: proc(
	device: vk.Device,
	config: SwapchainConfig,
	views: []vk.ImageView,
	color_buffer: AttachmentBuffer,
	depth_buffer: AttachmentBuffer,
	render_pass: vk.RenderPass,
) -> []vk.Framebuffer {
	framebuffers := make([]vk.Framebuffer, len(views))
	for view, index in views {
		attachments := []vk.ImageView{color_buffer.view, depth_buffer.view, view}
		create_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = u32(len(attachments)),
			pAttachments    = raw_data(attachments),
			width           = config.extent.width,
			height          = config.extent.height,
			layers          = 1,
		}

		result := vk.CreateFramebuffer(device, &create_info, nil, &framebuffers[index])
		if result != .SUCCESS {
			panic("Failed to create swapchain framebuffer.")
		}
	}
	return framebuffers
}
