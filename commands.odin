package main

import vk "vendor:vulkan"

create_command_pool :: proc(device: vk.Device, queue_family_index: int) -> (pool: vk.CommandPool) {
	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = u32(queue_family_index),
	}

	result := vk.CreateCommandPool(device, &create_info, nil, &pool)
	if result != .SUCCESS {
		panic("Failed to create command pool.")
	}
	return
}

allocate_command_buffers :: proc(
	using ctx: ^VkContext,
) -> (
	buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}

	result := vk.AllocateCommandBuffers(device, &alloc_info, raw_data(buffers[:]))
	if result != .SUCCESS {
		panic("Failed to allocate command buffer.")
	}
	return
}

record_command_buffer :: proc(
	ctx: ^VkContext,
	buffer: vk.CommandBuffer,
	config: SwapchainConfig,
	color_buffer: AttachmentBuffer,
	depth_buffer: AttachmentBuffer,
	resolve_image: vk.Image,
	resolve_view: vk.ImageView,
	pipeline_layout: vk.PipelineLayout,
	pipeline: vk.Pipeline,
	model: Model,
	descriptor_set: vk.DescriptorSet,
) {
	cmd_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	result := vk.BeginCommandBuffer(buffer, &cmd_begin_info)
	if result != .SUCCESS {
		panic("Failed to begin command buffer.")
	}

	cmd_transition_image_layout(
		buffer,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{},
		{.COLOR_ATTACHMENT_WRITE},
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		resolve_image,
		color_buffer.format,
		1,
	)

	color_attachment_info := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		clearValue = vk.ClearValue{color = vk.ClearColorValue{float32 = {0, 0, 0, 1}}},
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		imageView = color_buffer.view,
		loadOp = .CLEAR,
		storeOp = .STORE,
		resolveImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		resolveImageView = resolve_view,
		resolveMode = {.AVERAGE},
	}
	depth_attachment_info := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		clearValue = vk.ClearValue{depthStencil = vk.ClearDepthStencilValue{depth = 1}},
		imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		imageView = depth_buffer.view,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		resolveMode = {},
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment_info,
		pDepthAttachment = &depth_attachment_info,
		layerCount = 1,
		renderArea = {extent = config.extent},
	}
	vk.CmdBeginRenderingKHR(buffer, &rendering_info)

	vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline)

	vertex_buffer := model.vertex_buffer
	offset: vk.DeviceSize = 0
	vk.CmdBindVertexBuffers(buffer, 0, 1, &vertex_buffer, &offset)

	index_buffer := model.index_buffer
	vk.CmdBindIndexBuffer(buffer, index_buffer, 0, .UINT32)

	descriptor_set := descriptor_set
	vk.CmdBindDescriptorSets(buffer, .GRAPHICS, pipeline_layout, 0, 1, &descriptor_set, 0, nil)

	viewport := vk.Viewport {
		width    = f32(config.extent.width),
		height   = f32(config.extent.height),
		maxDepth = 1,
	}
	vk.CmdSetViewport(buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = config.extent,
	}
	vk.CmdSetScissor(buffer, 0, 1, &scissor)
	vk.CmdDrawIndexed(buffer, u32(model.index_count), 1, 0, 0, 0)

	vk.CmdEndRenderingKHR(buffer)

	cmd_transition_image_layout(
		buffer,
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_WRITE},
		{},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		resolve_image,
		color_buffer.format,
		1,
	)

	result = vk.EndCommandBuffer(buffer)
	if result != .SUCCESS {
		panic("Failed to end command buffer.")
	}
}

begin_single_time_commands :: proc(using ctx: ^VkContext) -> (command_buffer: vk.CommandBuffer) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = command_pool,
		commandBufferCount = 1,
	}

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

	return
}

end_single_time_commands :: proc(using ctx: ^VkContext, command_buffer: vk.CommandBuffer) {
	result := vk.EndCommandBuffer(command_buffer)
	if result != .SUCCESS {
		panic("Failed to end command buffer for copy.")
	}

	command_buffer := command_buffer
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}

	result = vk.QueueSubmit(graphics_queue, 1, &submit_info, {})
	if result != .SUCCESS {
		panic("Failed to submit commands for buffer copy.")
	}

	result = vk.QueueWaitIdle(graphics_queue)
	if result != .SUCCESS {
		panic("Failed to wait for queue to be idle when copying buffer.")
	}

	vk.FreeCommandBuffers(device, command_pool, 1, &command_buffer)
}
