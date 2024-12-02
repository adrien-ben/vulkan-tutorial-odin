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

destroy_texture_image :: proc(ctx: ^VkContext, using texture_image: TextureImage) {
	destroy_image(ctx, image, memory)
}

create_texture_image :: proc(using ctx: ^VkContext, path: string) -> (texture_img: TextureImage) {
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

	buffer, memory := create_buffer(ctx, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})

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
		ctx,
		texture_img.width,
		texture_img.height,
		texture_img.format,
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
		texture_img.levels,
		sample_count = ._1,
	)

	transition_image_layout(
		ctx,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{},
		{.TRANSFER_WRITE},
		{.TOP_OF_PIPE},
		{.TRANSFER},
		texture_img.image,
		texture_img.format,
		texture_img.levels,
	)

	copy_buffer_to_image(ctx, buffer, texture_img.image, texture_img.width, texture_img.height)

	generate_mipmaps(ctx, texture_img)

	destroy_buffer(ctx, buffer, memory)

	return
}

destroy_image :: proc(using ctx: ^VkContext, image: vk.Image, memory: vk.DeviceMemory) {
	vk.DestroyImage(device, image, nil)
	vk.FreeMemory(device, memory, nil)
}

create_image :: proc(
	using ctx: ^VkContext,
	width, height: int,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	properties: vk.MemoryPropertyFlags,
	mip_levels: int,
	sample_count: vk.SampleCountFlag,
) -> (
	image: vk.Image,
	image_mem: vk.DeviceMemory,
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
		samples = {sample_count},
	}

	result := vk.CreateImage(device, &create_info, nil, &image)
	if result != .SUCCESS {
		panic("Failed to create Vulkan image.")
	}

	requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, image, &requirements)

	mem_type, found := find_memory_type(ctx, requirements.memoryTypeBits, properties)
	if !found {
		panic("Failed to find compatible memory type for image memory.")
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = mem_type,
	}

	result = vk.AllocateMemory(device, &alloc_info, nil, &image_mem)
	if result != .SUCCESS {
		panic("Failed to allocate image memory.")
	}

	result = vk.BindImageMemory(device, image, image_mem, 0)
	if result != .SUCCESS {
		panic("Failed to bind image memory.")
	}

	return
}

transition_image_layout :: proc(
	using ctx: ^VkContext,
	old, new: vk.ImageLayout,
	srcAccessMask, dstAccessMask: vk.AccessFlags,
	srcStage, dstStage: vk.PipelineStageFlags,
	image: vk.Image,
	format: vk.Format,
	mip_levels: int,
) {
	command_buffer := begin_single_time_commands(ctx)

	cmd_transition_image_layout(
		command_buffer,
		old,
		new,
		srcAccessMask,
		dstAccessMask,
		srcStage,
		dstStage,
		image,
		format,
		mip_levels,
	)

	end_single_time_commands(ctx, command_buffer)
}

cmd_transition_image_layout :: proc(
	command_buffer: vk.CommandBuffer,
	old, new: vk.ImageLayout,
	srcAccessMask, dstAccessMask: vk.AccessFlags,
	srcStage, dstStage: vk.PipelineStageFlags,
	image: vk.Image,
	format: vk.Format,
	mip_levels: int,
) {
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
		srcAccessMask = srcAccessMask,
		dstAccessMask = dstAccessMask,
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

	vk.CmdPipelineBarrier(command_buffer, srcStage, dstStage, {}, 0, nil, 0, nil, 1, &barrier)
}

copy_buffer_to_image :: proc(
	using ctx: ^VkContext,
	src: vk.Buffer,
	dst: vk.Image,
	width, height: int,
) {
	command_buffer := begin_single_time_commands(ctx)

	region := vk.BufferImageCopy {
		imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		imageExtent = {width = u32(width), height = u32(height), depth = 1},
	}

	vk.CmdCopyBufferToImage(command_buffer, src, dst, .TRANSFER_DST_OPTIMAL, 1, &region)

	end_single_time_commands(ctx, command_buffer)
}

create_texture_image_view :: proc(
	using ctx: ^VkContext,
	using tex_image: TextureImage,
) -> vk.ImageView {
	return create_image_view(ctx, image, .R8G8B8A8_SRGB, {.COLOR}, levels)
}

create_image_view :: proc(
	using ctx: ^VkContext,
	image: vk.Image,
	format: vk.Format,
	aspect_mask: vk.ImageAspectFlags,
	mip_levels: int,
) -> (
	view: vk.ImageView,
) {
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

	result := vk.CreateImageView(device, &create_info, nil, &view)
	if result != .SUCCESS {
		panic("Failed to create image view.")
	}
	return
}

create_texture_sampler :: proc(
	using ctx: ^VkContext,
	anisotropy: f32,
	mip_levels: int,
) -> (
	sampler: vk.Sampler,
) {
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

	result := vk.CreateSampler(device, &create_info, nil, &sampler)
	if result != .SUCCESS {
		panic("Failed to create texture sampler.")
	}
	return
}

AttachmentBuffer :: struct {
	image:  vk.Image,
	memory: vk.DeviceMemory,
	view:   vk.ImageView,
	format: vk.Format,
}

destroy_attachment_buffer :: proc(ctx: ^VkContext, using buffer: AttachmentBuffer) {
	destroy_image(ctx, image, memory)
	vk.DestroyImageView(ctx.device, buffer.view, nil)
}

create_color_buffer :: proc(
	using ctx: ^VkContext,
	sc_config: SwapchainConfig,
) -> (
	b: AttachmentBuffer,
) {
	b.format = sc_config.format.format

	b.image, b.memory = create_image(
		ctx,
		int(sc_config.extent.width),
		int(sc_config.extent.height),
		b.format,
		.OPTIMAL,
		{.COLOR_ATTACHMENT},
		{.DEVICE_LOCAL},
		mip_levels = 1,
		sample_count = ctx.pdevice.max_sample_count,
	)

	transition_image_layout(
		ctx,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{},
		{},
		{.TOP_OF_PIPE},
		{.BOTTOM_OF_PIPE},
		b.image,
		b.format,
		1,
	)

	b.view = create_image_view(ctx, b.image, b.format, {.COLOR}, mip_levels = 1)

	return
}

create_depth_buffer :: proc(
	using ctx: ^VkContext,
	sc_config: SwapchainConfig,
) -> (
	b: AttachmentBuffer,
) {
	b.format = find_depth_format(pdevice.handle)

	b.image, b.memory = create_image(
		ctx,
		int(sc_config.extent.width),
		int(sc_config.extent.height),
		b.format,
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
		{.DEVICE_LOCAL},
		mip_levels = 1,
		sample_count = ctx.pdevice.max_sample_count,
	)

	transition_image_layout(
		ctx,
		.UNDEFINED,
		.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		{},
		{},
		{.TOP_OF_PIPE},
		{.BOTTOM_OF_PIPE},
		b.image,
		b.format,
		1,
	)

	b.view = create_image_view(ctx, b.image, b.format, {.DEPTH}, mip_levels = 1)

	return
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

generate_mipmaps :: proc(using ctx: ^VkContext, using texture_image: TextureImage) {
	fmt_properties: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(pdevice.handle, format, &fmt_properties)
	if !(fmt_properties.optimalTilingFeatures & {.SAMPLED_IMAGE_FILTER_LINEAR} ==
		   {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		panic("Texture image format does not support blitting.")
	}

	command_buffer := begin_single_time_commands(ctx)

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

	end_single_time_commands(ctx, command_buffer)
}
