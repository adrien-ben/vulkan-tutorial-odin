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

get_vertex_attribute_descriptions :: proc() -> [3]vk.VertexInputAttributeDescription {
	return [?]vk.VertexInputAttributeDescription {
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
		{
			binding = 0,
			location = 2,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(obj.Vertex, normal)),
		},
	}
}

create_vertex_buffer :: proc(
	using ctx: ^VkContext,
	vertices: []obj.Vertex,
) -> (
	final_buffer: vk.Buffer,
	final_buffer_mem: vk.DeviceMemory,
) {
	size := vk.DeviceSize(size_of(obj.Vertex) * len(vertices))
	staging_buffer, staging_buffer_mem := create_buffer(
		ctx,
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

	final_buffer, final_buffer_mem = create_buffer(
		ctx,
		size,
		{.TRANSFER_DST, .VERTEX_BUFFER},
		{.DEVICE_LOCAL},
	)

	copy_buffer(ctx, staging_buffer, final_buffer, size)

	destroy_buffer(ctx, staging_buffer, staging_buffer_mem)

	return
}

create_index_buffer :: proc(
	using ctx: ^VkContext,
	indices: []u32,
) -> (
	final_buffer: vk.Buffer,
	final_buffer_mem: vk.DeviceMemory,
) {
	size := vk.DeviceSize(size_of(u32) * len(indices))
	staging_buffer, staging_buffer_mem := create_buffer(
		ctx,
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

	final_buffer, final_buffer_mem = create_buffer(
		ctx,
		size,
		{.TRANSFER_DST, .INDEX_BUFFER},
		{.DEVICE_LOCAL},
	)

	copy_buffer(ctx, staging_buffer, final_buffer, size)

	destroy_buffer(ctx, staging_buffer, staging_buffer_mem)

	return
}
