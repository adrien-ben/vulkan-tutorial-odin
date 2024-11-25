package main

import "base:intrinsics"
import vk "vendor:vulkan"

Vec2 :: distinct [2]f32
Vec3 :: distinct [3]f32
Vertex :: struct {
	pos:        Vec3,
	color:      Vec3,
	tex_coords: Vec2,
}

VERTICES := [?]Vertex {
	{pos = {-0.5, -0.5, 0.2}, color = {1, 0, 0}, tex_coords = {1, 0}},
	{pos = {0.5, -0.5, 0.2}, color = {0, 1, 0}, tex_coords = {0, 0}},
	{pos = {0.5, 0.5, 0.2}, color = {0, 0, 1}, tex_coords = {0, 1}},
	{pos = {-0.5, 0.5, 0.2}, color = {1, 1, 1}, tex_coords = {1, 1}},
	{pos = {-0.5, -0.5, -0.2}, color = {1, 0, 0}, tex_coords = {1, 0}},
	{pos = {0.5, -0.5, -0.2}, color = {0, 1, 0}, tex_coords = {0, 0}},
	{pos = {0.5, 0.5, -0.2}, color = {0, 0, 1}, tex_coords = {0, 1}},
	{pos = {-0.5, 0.5, -0.2}, color = {1, 1, 1}, tex_coords = {1, 1}},
}
INDICES := [?]u16{0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4}

get_vertex_binding_description :: proc() -> vk.VertexInputBindingDescription {
	return vk.VertexInputBindingDescription {
		binding = 0,
		stride = size_of(Vertex),
		inputRate = .VERTEX,
	}
}

get_vertex_attribute_descriptions :: proc() -> [3]vk.VertexInputAttributeDescription {
	return [3]vk.VertexInputAttributeDescription {
		{
			binding = 0,
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Vertex, pos)),
		},
		{
			binding = 0,
			location = 1,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Vertex, color)),
		},
		{
			binding = 0,
			location = 2,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(Vertex, tex_coords)),
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

create_index_buffer :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
) -> (
	vk.Buffer,
	vk.DeviceMemory,
) {
	size: vk.DeviceSize = size_of(u16) * len(INDICES)
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
	intrinsics.mem_copy(data, raw_data(INDICES[:]), size)
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
