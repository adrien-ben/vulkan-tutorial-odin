package main

import vk "vendor:vulkan"

begin_single_time_commands :: proc(
	device: vk.Device,
	command_pool: vk.CommandPool,
) -> vk.CommandBuffer {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
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

	return command_buffer
}

end_single_time_commands :: proc(
	device: vk.Device,
	command_pool: vk.CommandPool,
	command_buffer: vk.CommandBuffer,
	queue: vk.Queue,
) {
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

	result = vk.QueueSubmit(queue, 1, &submit_info, {})
	if result != .SUCCESS {
		panic("Failed to submit commands for buffer copy.")
	}

	result = vk.QueueWaitIdle(queue)
	if result != .SUCCESS {
		panic("Failed to wait for queue to be idle when copying buffer.")
	}

	vk.FreeCommandBuffers(device, command_pool, 1, &command_buffer)
}
