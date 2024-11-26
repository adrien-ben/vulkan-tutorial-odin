package main

import "base:intrinsics"
import img "core:image"
import "core:image/png"
import "core:math"
import vk "vendor:vulkan"

TextureImage :: struct {
	image:                 vk.Image,
	memory:                vk.DeviceMemory,
	format:                vk.Format,
	width, height, levels: int,
}

destroy_texture_image :: proc(device: vk.Device, using texture_image: TextureImage) {
	destroy_image(device, image, memory)
}

create_texture_image :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
	path: string,
) -> (
	texture_img: TextureImage,
) {
	image, err := img.load(path, {.alpha_add_if_missing})
	if err != nil {
		panic("Failed to open image file.")
	}

	size := vk.DeviceSize(image.width * image.height * image.channels * (image.depth / 8))
	texture_img.width = image.width
	texture_img.height = image.height
	texture_img.levels = int(
		math.floor(math.log2(f32(max(texture_img.width, texture_img.height)))),
	)

	buffer, memory := create_buffer(
		device,
		pdevice,
		size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	data: rawptr
	result := vk.MapMemory(device, memory, 0, size, {}, &data)
	if result != .SUCCESS {
		panic("Failed to map memory.")
	}
	intrinsics.mem_copy(data, raw_data(image.pixels.buf), size)
	vk.UnmapMemory(device, memory)

	img.destroy(image)

	texture_img.format = .R8G8B8A8_SRGB
	texture_img.image, texture_img.memory = create_image(
		device,
		pdevice,
		texture_img.width,
		texture_img.height,
		texture_img.format,
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
		texture_img.levels,
	)

	transition_image_layout(
		device,
		command_pool,
		queue,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		texture_img.image,
		texture_img.format,
		texture_img.levels,
	)

	copy_buffer_to_image(
		device,
		command_pool,
		queue,
		buffer,
		texture_img.image,
		texture_img.width,
		texture_img.height,
	)

	generate_mipmaps(device, pdevice, command_pool, queue, texture_img)

	destroy_buffer(device, buffer, memory)

	return
}

destroy_image :: proc(device: vk.Device, image: vk.Image, memory: vk.DeviceMemory) {
	vk.DestroyImage(device, image, nil)
	vk.FreeMemory(device, memory, nil)
}

create_image :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	width, height: int,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	properties: vk.MemoryPropertyFlags,
	mip_levels: int,
) -> (
	vk.Image,
	vk.DeviceMemory,
) {
	create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {width = u32(width), height = u32(height), depth = 1},
		mipLevels = u32(mip_levels),
		arrayLayers = 1,
		format = format,
		tiling = tiling,
		initialLayout = .UNDEFINED,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		samples = {._1},
	}

	image: vk.Image
	result := vk.CreateImage(device, &create_info, nil, &image)
	if result != .SUCCESS {
		panic("Failed to create Vulkan image.")
	}

	requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, image, &requirements)

	mem_type, found := find_memory_type(pdevice, requirements.memoryTypeBits, properties)
	if !found {
		panic("Failed to find compatible memory type for image memory.")
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = mem_type,
	}

	image_mem: vk.DeviceMemory
	result = vk.AllocateMemory(device, &alloc_info, nil, &image_mem)
	if result != .SUCCESS {
		panic("Failed to allocate image memory.")
	}

	result = vk.BindImageMemory(device, image, image_mem, 0)
	if result != .SUCCESS {
		panic("Failed to bind image memory.")
	}

	return image, image_mem
}

transition_image_layout :: proc(
	device: vk.Device,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
	old, new: vk.ImageLayout,
	image: vk.Image,
	format: vk.Format,
	mip_levels: int,
) {
	command_buffer := begin_single_time_commands(device, command_pool)

	aspeck_mask: vk.ImageAspectFlags = {.COLOR}
	if new == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		aspeck_mask = {.DEPTH}
		if has_stencil(format) {
			aspeck_mask |= {.STENCIL}
		}
	}

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = old,
		newLayout = new,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = aspeck_mask,
			baseMipLevel = 0,
			levelCount = u32(mip_levels),
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	srcStage, dstStage: vk.PipelineStageFlags
	if old == .UNDEFINED && new == .TRANSFER_DST_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.TRANSFER_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.TRANSFER}
	} else if old == .TRANSFER_DST_OPTIMAL && new == .SHADER_READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		srcStage = {.TRANSFER}
		dstStage = {.FRAGMENT_SHADER}
	} else if old == .UNDEFINED && new == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.EARLY_FRAGMENT_TESTS}
	} else {
		panic("Unsupported image layout transition")
	}

	vk.CmdPipelineBarrier(command_buffer, srcStage, dstStage, {}, 0, nil, 0, nil, 1, &barrier)

	end_single_time_commands(device, command_pool, command_buffer, queue)
}

copy_buffer_to_image :: proc(
	device: vk.Device,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
	src: vk.Buffer,
	dst: vk.Image,
	width, height: int,
) {
	command_buffer := begin_single_time_commands(device, command_pool)

	region := vk.BufferImageCopy {
		imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		imageExtent = {width = u32(width), height = u32(height), depth = 1},
	}

	vk.CmdCopyBufferToImage(command_buffer, src, dst, .TRANSFER_DST_OPTIMAL, 1, &region)

	end_single_time_commands(device, command_pool, command_buffer, queue)
}

create_texture_image_view :: proc(
	device: vk.Device,
	using tex_image: TextureImage,
) -> vk.ImageView {
	return create_image_view(device, image, .R8G8B8A8_SRGB, {.COLOR}, levels)
}

create_image_view :: proc(
	device: vk.Device,
	image: vk.Image,
	format: vk.Format,
	aspect_mask: vk.ImageAspectFlags,
	mip_levels: int,
) -> vk.ImageView {
	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = format,
		subresourceRange = {
			aspectMask = aspect_mask,
			levelCount = u32(mip_levels),
			layerCount = 1,
		},
	}

	view: vk.ImageView
	result := vk.CreateImageView(device, &create_info, nil, &view)
	if result != .SUCCESS {
		panic("Failed to create image view.")
	}
	return view
}

create_texture_sampler :: proc(device: vk.Device, anisotropy: f32, mip_levels: int) -> vk.Sampler {
	create_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		anisotropyEnable        = anisotropy > 0,
		maxAnisotropy           = anisotropy,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = .LINEAR,
		mipLodBias              = 0,
		minLod                  = 0,
		maxLod                  = f32(mip_levels),
	}

	sampler: vk.Sampler
	result := vk.CreateSampler(device, &create_info, nil, &sampler)
	if result != .SUCCESS {
		panic("Failed to create texture sampler.")
	}
	return sampler
}

DepthBuffer :: struct {
	image:  vk.Image,
	memory: vk.DeviceMemory,
	view:   vk.ImageView,
	format: vk.Format,
}

destroy_depth_buffer :: proc(device: vk.Device, buffer: DepthBuffer) {
	destroy_image(device, buffer.image, buffer.memory)
	vk.DestroyImageView(device, buffer.view, nil)
}

create_depth_buffer :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	sc_config: SwapchainConfig,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
) -> DepthBuffer {
	format := find_depth_format(pdevice)

	image, memory := create_image(
		device,
		pdevice,
		int(sc_config.extent.width),
		int(sc_config.extent.height),
		format,
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
		{.DEVICE_LOCAL},
		mip_levels = 1,
	)

	view := create_image_view(device, image, format, {.DEPTH}, mip_levels = 1)

	transition_image_layout(
		device,
		command_pool,
		queue,
		.UNDEFINED,
		.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		image,
		format,
		mip_levels = 1,
	)

	return DepthBuffer{image = image, memory = memory, view = view, format = format}
}

find_depth_format :: proc(pdevice: vk.PhysicalDevice) -> vk.Format {
	candidates := []vk.Format{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}
	format, found := find_supported_format(
		pdevice,
		candidates,
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
	)
	if !found {
		panic("Failed to find a supported format for depth buffer.")
	}
	return format
}

find_supported_format :: proc(
	pdevice: vk.PhysicalDevice,
	candidates: []vk.Format,
	tiling: vk.ImageTiling,
	features: vk.FormatFeatureFlags,
) -> (
	vk.Format,
	bool,
) {
	for f in candidates {
		properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(pdevice, f, &properties)

		if (tiling == .LINEAR && (properties.linearTilingFeatures & features) == features) ||
		   (tiling == .OPTIMAL && (properties.optimalTilingFeatures & features) == features) {
			return f, true
		}
	}
	return nil, false
}

has_stencil :: proc(format: vk.Format) -> bool {
	return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
}

generate_mipmaps :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
	using texture_image: TextureImage,
) {
	fmt_properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(pdevice, format, &fmt_properties)
	if !(fmt_properties.optimalTilingFeatures & {.SAMPLED_IMAGE_FILTER_LINEAR} ==
		   {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		panic("Texture image format does not support blitting.")
	}

	command_buffer := begin_single_time_commands(device, command_pool)

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		image = image,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			levelCount = 1,
		},
	}

	mip_w := width
	mip_h := height
	for i in 1 ..< levels {
		barrier.subresourceRange.baseMipLevel = u32(i - 1)
		barrier.oldLayout = .TRANSFER_DST_OPTIMAL
		barrier.newLayout = .TRANSFER_SRC_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.TRANSFER_READ}

		vk.CmdPipelineBarrier(
			command_buffer,
			{.TRANSFER},
			{.TRANSFER},
			{},
			0,
			nil,
			0,
			nil,
			1,
			&barrier,
		)

		next_mip_w := mip_w / 2 if mip_w > 1 else 1
		next_mip_h := mip_h / 2 if mip_h > 1 else 1
		blit := vk.ImageBlit {
			srcOffsets = [2]vk.Offset3D{{0, 0, 0}, {i32(mip_w), i32(mip_h), 1}},
			dstOffsets = [2]vk.Offset3D{{0, 0, 0}, {i32(next_mip_w), i32(next_mip_h), 1}},
			srcSubresource = {
				aspectMask = {.COLOR},
				mipLevel = u32(i - 1),
				baseArrayLayer = 0,
				layerCount = 1,
			},
			dstSubresource = {
				aspectMask = {.COLOR},
				mipLevel = u32(i),
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		vk.CmdBlitImage(
			command_buffer,
			image,
			.TRANSFER_SRC_OPTIMAL,
			image,
			.TRANSFER_DST_OPTIMAL,
			1,
			&blit,
			.LINEAR,
		)

		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_READ}
		barrier.dstAccessMask = {.SHADER_READ}

		vk.CmdPipelineBarrier(
			command_buffer,
			{.TRANSFER},
			{.FRAGMENT_SHADER},
			{},
			0,
			nil,
			0,
			nil,
			1,
			&barrier,
		)

		mip_w = next_mip_w
		mip_h = next_mip_h
	}

	barrier.subresourceRange.baseMipLevel = u32(levels - 1)
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = {.TRANSFER_READ}
	barrier.dstAccessMask = {.SHADER_READ}

	vk.CmdPipelineBarrier(
		command_buffer,
		{.TRANSFER},
		{.FRAGMENT_SHADER},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)

	end_single_time_commands(device, command_pool, command_buffer, queue)
}
