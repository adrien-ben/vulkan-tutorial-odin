package main

import "core:log"
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
	handle: vk.SwapchainKHR,
	config: SwapchainConfig,
	images: []vk.Image,
	views:  []vk.ImageView,
}

delete_swapchain_support_details :: proc(details: SwapchainSupportDetails) {
	delete(details.formats)
	delete(details.present_modes)
}

query_swapchain_support :: proc(using ctx: ^VkContext) -> (details: SwapchainSupportDetails) {
	result := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		pdevice.handle,
		surface,
		&details.capabilities,
	)
	if result != .SUCCESS {
		panic("Failed to get physical device surface capabilities.")
	}

	fmt_count: u32
	result = vk.GetPhysicalDeviceSurfaceFormatsKHR(pdevice.handle, surface, &fmt_count, nil)
	if result != .SUCCESS {
		panic("Failed to get physical device surface format count.")
	}
	details.formats = make([]vk.SurfaceFormatKHR, fmt_count)
	result = vk.GetPhysicalDeviceSurfaceFormatsKHR(
		pdevice.handle,
		surface,
		&fmt_count,
		raw_data(details.formats),
	)
	if result != .SUCCESS {
		panic("Failed to list physical device surface formats.")
	}

	mode_count: u32
	result = vk.GetPhysicalDeviceSurfacePresentModesKHR(pdevice.handle, surface, &mode_count, nil)
	if result != .SUCCESS {
		panic("Failed to get physical device surface present mode count.")
	}
	details.present_modes = make([]vk.PresentModeKHR, mode_count)
	result = vk.GetPhysicalDeviceSurfacePresentModesKHR(
		pdevice.handle,
		surface,
		&mode_count,
		raw_data(details.present_modes),
	)
	if result != .SUCCESS {
		panic("Failed to get physical device surface present modes.")
	}

	return
}

select_swapchain_config :: proc(
	details: SwapchainSupportDetails,
	window: glfw.WindowHandle,
) -> (
	config: SwapchainConfig,
) {
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

	return
}

destroy_swapchain :: proc(using ctx: ^VkContext, swapchain: Swapchain) {
	for view in swapchain.views {
		vk.DestroyImageView(device, view, nil)
	}
	delete(swapchain.views)
	log.debug("Vulkan swapchain image views destroyed.")

	delete(swapchain.images)

	vk.DestroySwapchainKHR(device, swapchain.handle, nil)
	log.debug("Vulkan swapchain destroyed.")
}

create_swapchain :: proc(
	using ctx: ^VkContext,
	color_buffer: AttachmentBuffer,
	depth_buffer: AttachmentBuffer,
	config: SwapchainConfig,
) -> (
	swapchain: Swapchain,
) {
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

	swapchain.config = config

	result := vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain.handle)
	if result != .SUCCESS {
		panic("Failed to create Vulkan swapchain.")
	}

	swapchain.images = get_swapchain_images(ctx, swapchain.handle)
	log.debug("Vulkan swapchain image created.")

	swapchain.views = create_swapchain_image_views(ctx, config, swapchain.images)
	log.debug("Vulkan swapchain image views created.")

	return
}

recreate_swapchain :: proc(
	using ctx: ^VkContext,
	window: glfw.WindowHandle,
	old_color_buffer: AttachmentBuffer,
	old_depth_buffer: AttachmentBuffer,
	current: Swapchain,
) -> (
	new_color_buffer: AttachmentBuffer,
	new_depth_buffer: AttachmentBuffer,
	new_swapchain: Swapchain,
) {
	result := vk.DeviceWaitIdle(device)
	if result != .SUCCESS {
		panic("Failed to wait for device to be idle.")
	}

	destroy_attachment_buffer(ctx, old_color_buffer)
	destroy_attachment_buffer(ctx, old_depth_buffer)
	destroy_swapchain(ctx, current)

	swapchain_support := query_swapchain_support(ctx)
	defer {
		delete_swapchain_support_details(swapchain_support)
	}
	swapchain_config := select_swapchain_config(swapchain_support, window)

	new_color_buffer = create_color_buffer(ctx, swapchain_config)
	new_depth_buffer = create_depth_buffer(ctx, swapchain_config)
	new_swapchain = create_swapchain(ctx, new_color_buffer, new_depth_buffer, swapchain_config)

	return
}

get_swapchain_images :: proc(
	using ctx: ^VkContext,
	swapchain: vk.SwapchainKHR,
) -> (
	imgs: []vk.Image,
) {
	img_count: u32
	result := vk.GetSwapchainImagesKHR(device, swapchain, &img_count, nil)
	if result != .SUCCESS {
		panic("Failed to get swapchain image count.")
	}
	imgs = make([]vk.Image, img_count)
	result = vk.GetSwapchainImagesKHR(device, swapchain, &img_count, raw_data(imgs))
	if result != .SUCCESS {
		panic("Failed to get swapchain images.")
	}
	return
}

create_swapchain_image_views :: proc(
	using ctx: ^VkContext,
	config: SwapchainConfig,
	imgs: []vk.Image,
) -> (
	views: []vk.ImageView,
) {
	views = make([]vk.ImageView, len(imgs))
	for img, index in imgs {
		views[index] = create_image_view(ctx, img, config.format.format, {.COLOR}, mip_levels = 1)
	}
	return
}
