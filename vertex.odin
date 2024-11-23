package main

import "base:intrinsics"
import "core:fmt"
import vk "vendor:vulkan"

Vec2 :: distinct [2]f32
Vec3 :: distinct [3]f32
Vertex :: struct {
	pos:   Vec2,
	color: Vec3,
}

VERTICES := [?]Vertex {
	{pos = {0, -0.5}, color = {1, 0, 0}},
	{pos = {0.5, 0.5}, color = {0, 1, 0}},
	{pos = {-0.5, 0.5}, color = {0, 0, 1}},
}

get_vertex_binding_description :: proc() -> vk.VertexInputBindingDescription {
	return vk.VertexInputBindingDescription {
		binding = 0,
		stride = size_of(Vertex),
		inputRate = .VERTEX,
	}
}

get_vertex_attribute_descriptions :: proc() -> [2]vk.VertexInputAttributeDescription {
	return [2]vk.VertexInputAttributeDescription {
		{binding = 0, location = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
		{
			binding = 0,
			location = 1,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Vertex, color)),
		},
	}
}

create_vertex_buffer :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
) -> (
	vk.Buffer,
	vk.DeviceMemory,
) {
	size: vk.DeviceSize = size_of(Vertex) * len(VERTICES)
	staging_buffer, staging_buffer_mem := create_buffer(
		device,
		pdevice,
		size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	data: rawptr
	result := vk.MapMemory(device, staging_buffer_mem, 0, size, {}, &data)
	if result != .SUCCESS {
		panic("Failed to map memory.")
	}
	intrinsics.mem_copy(data, raw_data(VERTICES[:]), size)
	vk.UnmapMemory(device, staging_buffer_mem)


	final_buffer, final_buffer_mem := create_buffer(
		device,
		pdevice,
		size,
		{.TRANSFER_DST, .VERTEX_BUFFER},
		{.DEVICE_LOCAL},
	)

	copy_buffer(device, command_pool, queue, staging_buffer, final_buffer, size)

	destroy_buffer(device, staging_buffer, staging_buffer_mem)

	return final_buffer, final_buffer_mem
}

destroy_buffer :: proc(device: vk.Device, buffer: vk.Buffer, memory: vk.DeviceMemory) {
	vk.DestroyBuffer(device, buffer, nil)
	vk.FreeMemory(device, memory, nil)
}

create_buffer :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
) -> (
	vk.Buffer,
	vk.DeviceMemory,
) {
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	buffer: vk.Buffer
	result := vk.CreateBuffer(device, &create_info, nil, &buffer)
	if result != .SUCCESS {
		panic("Failed to create Vulkan buffer.")
	}

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer, &requirements)


	memory_type, found := find_memory_type(pdevice, requirements.memoryTypeBits, properties)
	if !found {
		panic("Failed to find compatible memory type for vertex buffer memory.")
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = memory_type,
	}

	memory: vk.DeviceMemory
	result = vk.AllocateMemory(device, &alloc_info, nil, &memory)
	if result != .SUCCESS {
		panic("Failed to allocate memory for Vulkan buffer.")
	}

	result = vk.BindBufferMemory(device, buffer, memory, 0)
	if result != .SUCCESS {
		panic("Failed to bind memory to Vulkan buffer.")
	}

	return buffer, memory
}

find_memory_type :: proc(
	pdevice: vk.PhysicalDevice,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	u32,
	bool,
) {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(pdevice, &mem_properties)

	for i: u32 = 0; i < mem_properties.memoryTypeCount; i += 1 {
		mem_type := u32(1) << i
		mem_type_matches := (type_filter & mem_type) == mem_type

		mem_type_props := mem_properties.memoryTypes[i].propertyFlags
		mem_type_props_matches := (mem_type_props & properties) == properties

		if mem_type_matches && mem_type_props_matches do return i, true
	}

	return 0, false
}

copy_buffer :: proc(
	device: vk.Device,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
	src, dst: vk.Buffer,
	size: vk.DeviceSize,
) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
	result := vk.AllocateCommandBuffers(device, &alloc_info, &command_buffer)
	if result != .SUCCESS {
		panic("Failed to allocate command buffer for buffer copy.")
	}

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	result = vk.BeginCommandBuffer(command_buffer, &begin_info)
	if result != .SUCCESS {
		panic("Failed to begin command buffer for buffer copy.")
	}

	copy_region := vk.BufferCopy {
		size = size,
	}
	vk.CmdCopyBuffer(command_buffer, src, dst, 1, &copy_region)

	result = vk.EndCommandBuffer(command_buffer)
	if result != .SUCCESS {
		panic("Failed to end command buffer for copy.")
	}

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}

	result = vk.QueueSubmit(queue, 1, &submit_info, {})
	if result != .SUCCESS {
		panic("Failed to submit commands for buffer copy.")
	}

	result = vk.QueueWaitIdle(queue)
	if result != .SUCCESS {
		panic("Failed to wait for queue to be idle when copying buffer.")
	}

	vk.FreeCommandBuffers(device, command_pool, 1, &command_buffer)
}
