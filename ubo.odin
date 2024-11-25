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
	layout_bindings := []vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX},
		},
		{
			binding = 1,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(layout_bindings)),
		pBindings    = raw_data(layout_bindings),
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
	obj.proj = perspective(
		math.to_radians(f32(45)),
		f32(swapchain_config.extent.width) / f32(swapchain_config.extent.height),
		0.1,
		10,
	)

	intrinsics.mem_copy(buffer.mapped_ptr, &obj, size_of(UniformBufferObject))
}

perspective :: proc(fovy, aspect, near, far: f32) -> (m: Mat4) {
	f := 1 / math.tan(fovy * 0.5)
	m[0, 0] = f / aspect
	m[1, 1] = -f
	m[2, 2] = -far / (far - near)
	m[3, 2] = -1
	m[2, 3] = -(far * near) / (far - near)

	return
}

create_descriptor_pool :: proc(device: vk.Device) -> vk.DescriptorPool {
	pool_sizes := []vk.DescriptorPoolSize {
		{type = .UNIFORM_BUFFER, descriptorCount = MAX_FRAMES_IN_FLIGHT},
		{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = MAX_FRAMES_IN_FLIGHT},
	}

	create_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes),
		maxSets       = MAX_FRAMES_IN_FLIGHT,
	}

	pool: vk.DescriptorPool
	result := vk.CreateDescriptorPool(device, &create_info, nil, &pool)
	if result != .SUCCESS {
		panic("Failed to create descriptor pool.")
	}
	return pool
}

create_descriptor_sets :: proc(
	device: vk.Device,
	pool: vk.DescriptorPool,
	layout: vk.DescriptorSetLayout,
	ubo_buffers: [MAX_FRAMES_IN_FLIGHT]UboBuffer,
	texture_image_view: vk.ImageView,
	texture_image_sampler: vk.Sampler,
) -> [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet {

	layouts: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		layouts[i] = layout
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool,
		descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = raw_data(layouts[:]),
	}

	sets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet
	result := vk.AllocateDescriptorSets(device, &alloc_info, raw_data(sets[:]))
	if result != .SUCCESS {
		panic("Failed to allocate descriptor sets.")
	}

	for set, index in sets {
		buffer_info := vk.DescriptorBufferInfo {
			buffer = ubo_buffers[index].buffer,
			offset = 0,
			range  = size_of(UniformBufferObject),
		}

		image_info := vk.DescriptorImageInfo {
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
			imageView   = texture_image_view,
			sampler     = texture_image_sampler,
		}

		desc_write := []vk.WriteDescriptorSet {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = set,
				dstBinding = 0,
				dstArrayElement = 0,
				descriptorType = .UNIFORM_BUFFER,
				descriptorCount = 1,
				pBufferInfo = &buffer_info,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = set,
				dstBinding = 1,
				dstArrayElement = 0,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				pImageInfo = &image_info,
			},
		}

		vk.UpdateDescriptorSets(device, u32(len(desc_write)), raw_data(desc_write), 0, nil)
	}

	return sets
}
