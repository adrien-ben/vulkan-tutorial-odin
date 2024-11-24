package main

import "base:intrinsics"
import "core:math"
import "core:math/linalg"
import vk "vendor:vulkan"

Mat4 :: matrix[4, 4]f32

UniformBufferObject :: struct {
	model: Mat4,
	view:  Mat4,
	proj:  Mat4,
}

UboBuffer :: struct {
	buffer:     vk.Buffer,
	memory:     vk.DeviceMemory,
	mapped_ptr: rawptr,
}

create_descriptor_set_layout :: proc(device: vk.Device) -> vk.DescriptorSetLayout {
	layout_binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.VERTEX},
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &layout_binding,
	}

	layout: vk.DescriptorSetLayout
	result := vk.CreateDescriptorSetLayout(device, &create_info, nil, &layout)
	if result != .SUCCESS {
		panic("Failed to create descriptor set layout")
	}
	return layout
}

destroy_ubo_buffer :: proc(device: vk.Device, buffer: UboBuffer) {
	destroy_buffer(device, buffer.buffer, buffer.memory)
}

create_uniform_buffers :: proc(
	device: vk.Device,
	pdevice: vk.PhysicalDevice,
) -> [MAX_FRAMES_IN_FLIGHT]UboBuffer {
	buffers: [MAX_FRAMES_IN_FLIGHT]UboBuffer

	buffer_size: vk.DeviceSize = size_of(UniformBufferObject)
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		buffers[i].buffer, buffers[i].memory = create_buffer(
			device,
			pdevice,
			buffer_size,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)

		vk.MapMemory(device, buffers[i].memory, 0, buffer_size, {}, &buffers[i].mapped_ptr)
	}

	return buffers
}

update_uniform_buffer :: proc(
	buffer: UboBuffer,
	swapchain_config: SwapchainConfig,
	total_time_s: f32,
) {
	obj: UniformBufferObject

	obj.model = linalg.matrix4_rotate(math.to_radians(f32(90)) * total_time_s, [3]f32{0, 0, 1})
	obj.view = linalg.matrix4_look_at([3]f32{2, 2, 2}, [3]f32{0, 0, 0}, [3]f32{0, 0, 1})
	obj.proj = linalg.matrix4_perspective(
		math.to_radians(f32(45)),
		f32(swapchain_config.extent.width) / f32(swapchain_config.extent.height),
		0.1,
		10,
	)
	obj.proj[1][1] *= -1

	intrinsics.mem_copy(buffer.mapped_ptr, &obj, size_of(UniformBufferObject))
}
