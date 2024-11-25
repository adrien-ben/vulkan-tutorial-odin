package main

import "base:intrinsics"
import obj "objloader"
import vk "vendor:vulkan"

get_vertex_binding_description :: proc() -> vk.VertexInputBindingDescription {
	return vk.VertexInputBindingDescription {
		binding = 0,
		stride = size_of(obj.Vertex),
		inputRate = .VERTEX,
	}
}

get_vertex_attribute_descriptions :: proc() -> [2]vk.VertexInputAttributeDescription {
	return [2]vk.VertexInputAttributeDescription {
		{
			binding = 0,
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(obj.Vertex, position)),
		},
		{
			binding = 0,
			location = 1,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(obj.Vertex, tex_coords)),
		},
	}
}

create_vertex_buffer :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
	vertices: []obj.Vertex,
) -> (
	vk.Buffer,
	vk.DeviceMemory,
) {
	size := vk.DeviceSize(size_of(obj.Vertex) * len(vertices))
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
	intrinsics.mem_copy(data, raw_data(vertices), size)
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

create_index_buffer :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
	indices: []u32,
) -> (
	vk.Buffer,
	vk.DeviceMemory,
) {
	size := vk.DeviceSize(size_of(u32) * len(indices))
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
	intrinsics.mem_copy(data, raw_data(indices), size)
	vk.UnmapMemory(device, staging_buffer_mem)

	final_buffer, final_buffer_mem := create_buffer(
		device,
		pdevice,
		size,
		{.TRANSFER_DST, .INDEX_BUFFER},
		{.DEVICE_LOCAL},
	)

	copy_buffer(device, command_pool, queue, staging_buffer, final_buffer, size)

	destroy_buffer(device, staging_buffer, staging_buffer_mem)

	return final_buffer, final_buffer_mem
}
