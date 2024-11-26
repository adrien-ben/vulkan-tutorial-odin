package main

import obj "objloader"
import vk "vendor:vulkan"

Model :: struct {
	vertex_count:         int,
	vertex_buffer:        vk.Buffer,
	vertex_buffer_memory: vk.DeviceMemory,
	index_count:          int,
	index_buffer:         vk.Buffer,
	index_buffer_memory:  vk.DeviceMemory,
	texture_image:        TextureImage,
	texture_view:         vk.ImageView,
	texture_sampler:      vk.Sampler,
}

destroy_model :: proc(device: vk.Device, using model: Model) {
	destroy_buffer(device, vertex_buffer, vertex_buffer_memory)
	destroy_buffer(device, index_buffer, index_buffer_memory)
	destroy_texture_image(device, texture_image)
	vk.DestroyImageView(device, texture_view, nil)
	vk.DestroySampler(device, texture_sampler, nil)
}

load_model :: proc(
	device: vk.Device,
	pdevice: PhysicalDevice,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
) -> (
	m: Model,
) {
	model, err := obj.load_from_file("./assets/viking_room.obj")
	if err != nil {
		panic("Failed to load model from file.")
	}

	m.vertex_count = len(model.vertices)
	m.vertex_buffer, m.vertex_buffer_memory = create_vertex_buffer(
		device,
		pdevice.handle,
		command_pool,
		queue,
		model.vertices[:],
	)

	m.index_count = len(model.indices)
	m.index_buffer, m.index_buffer_memory = create_index_buffer(
		device,
		pdevice.handle,
		command_pool,
		queue,
		model.indices[:],
	)

	m.texture_image = create_texture_image(
		device,
		pdevice.handle,
		command_pool,
		queue,
		"./assets/viking_room.png",
	)
	m.texture_view = create_texture_image_view(device, m.texture_image)
	m.texture_sampler = create_texture_sampler(
		device,
		pdevice.properties.limits.maxSamplerAnisotropy,
		m.texture_image.levels,
	)

	obj.destroy(model)

	return
}
