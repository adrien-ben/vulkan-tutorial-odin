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
) -> (
	vk.Buffer,
	vk.DeviceMemory,
) {
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size_of(Vertex) * len(VERTICES),
		usage       = {.VERTEX_BUFFER},
		sharingMode = .EXCLUSIVE,
	}

	buffer: vk.Buffer
	result := vk.CreateBuffer(device, &create_info, nil, &buffer)
	if result != .SUCCESS {
		panic("Failed to create Vulkan buffer.")
	}

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer, &requirements)


	memory_type, found := find_memory_type(
		pdevice,
		requirements.memoryTypeBits,
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
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

	data: rawptr
	result = vk.MapMemory(device, memory, 0, create_info.size, {}, &data)
	if result != .SUCCESS {
		panic("Failed to map memory.")
	}
	intrinsics.mem_copy(data, raw_data(VERTICES[:]), create_info.size)
	vk.UnmapMemory(device, memory)

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
