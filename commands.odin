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
	buffer: vk.CommandBuffer,
	render_pass: vk.RenderPass,
	framebuffer: vk.Framebuffer,
	config: SwapchainConfig,
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

	clear_values := []vk.ClearValue {
		{color = vk.ClearColorValue{float32 = {0, 0, 0, 1}}},
		{depthStencil = vk.ClearDepthStencilValue{depth = 1}},
	}
	render_pass_begin_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = render_pass,
		framebuffer = framebuffer,
		renderArea = {offset = {}, extent = config.extent},
		clearValueCount = u32(len(clear_values)),
		pClearValues = raw_data(clear_values),
	}

	vk.CmdBeginRenderPass(buffer, &render_pass_begin_info, .INLINE)
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

	vk.CmdEndRenderPass(buffer)

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
