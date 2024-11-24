package main

import "base:intrinsics"
import "core:fmt"
import img "core:image"
import "core:image/png"
import vk "vendor:vulkan"

create_texture_image :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
) -> (
	vk.Image,
	vk.DeviceMemory,
) {
	image, err := img.load("./assets/texture.png", {.alpha_add_if_missing})
	if err != nil {
		panic("Failed to open image file.")
	}

	img_width := image.width
	img_height := image.height
	size := vk.DeviceSize(img_width * img_height * image.channels * (image.depth / 8))

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

	vk_image, vk_image_mem := create_image(
		device,
		pdevice,
		img_width,
		img_height,
		.R8G8B8A8_SRGB,
		.OPTIMAL,
		{.TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
	)

	transition_image_layout(
		device,
		command_pool,
		queue,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		vk_image,
	)

	copy_buffer_to_image(device, command_pool, queue, buffer, vk_image, img_width, img_height)

	transition_image_layout(
		device,
		command_pool,
		queue,
		.TRANSFER_DST_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		vk_image,
	)

	destroy_buffer(device, buffer, memory)

	return vk_image, vk_image_mem
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
) -> (
	vk.Image,
	vk.DeviceMemory,
) {
	create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {width = u32(width), height = u32(height), depth = 1},
		mipLevels = 1,
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
) {
	command_buffer := begin_single_time_commands(device, command_pool)

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = old,
		newLayout = new,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
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
