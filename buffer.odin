package main

import vk "vendor:vulkan"

destroy_buffer :: proc(using ctx: ^VkContext, buffer: vk.Buffer, memory: vk.DeviceMemory) {
	vk.DestroyBuffer(device, buffer, nil)
	vk.FreeMemory(device, memory, nil)
}

create_buffer :: proc(
	using ctx: ^VkContext,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
) -> (
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
) {
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	result := vk.CreateBuffer(device, &create_info, nil, &buffer)
	if result != .SUCCESS {
		panic("Failed to create Vulkan buffer.")
	}

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer, &requirements)


	memory_type, found := find_memory_type(ctx, requirements.memoryTypeBits, properties)
	if !found {
		panic("Failed to find compatible memory type for vertex buffer memory.")
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = memory_type,
	}

	result = vk.AllocateMemory(device, &alloc_info, nil, &memory)
	if result != .SUCCESS {
		panic("Failed to allocate memory for Vulkan buffer.")
	}

	result = vk.BindBufferMemory(device, buffer, memory, 0)
	if result != .SUCCESS {
		panic("Failed to bind memory to Vulkan buffer.")
	}

	return
}

find_memory_type :: proc(
	using ctx: ^VkContext,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	u32,
	bool,
) {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(pdevice.handle, &mem_properties)

	for i: u32 = 0; i < mem_properties.memoryTypeCount; i += 1 {
		mem_type := u32(1) << i
		mem_type_matches := (type_filter & mem_type) == mem_type

		mem_type_props := mem_properties.memoryTypes[i].propertyFlags
		mem_type_props_matches := (mem_type_props & properties) == properties

		if mem_type_matches && mem_type_props_matches do return i, true
	}

	return 0, false
}

copy_buffer :: proc(using ctx: ^VkContext, src, dst: vk.Buffer, size: vk.DeviceSize) {
	command_buffer := begin_single_time_commands(ctx)

	copy_region := vk.BufferCopy {
		size = size,
	}
	vk.CmdCopyBuffer(command_buffer, src, dst, 1, &copy_region)

	end_single_time_commands(ctx, command_buffer)
}
