package main

import vk "vendor:vulkan"

SyncObjects :: struct {
	image_available: vk.Semaphore,
	render_finished: vk.Semaphore,
	in_flight:       vk.Fence,
}

destroy_sync_objects :: proc(ctx: ^VkContext, using objs: SyncObjects) {
	vk.DestroySemaphore(ctx.device, image_available, nil)
	vk.DestroySemaphore(ctx.device, render_finished, nil)
	vk.DestroyFence(ctx.device, in_flight, nil)
}

create_sync_objects :: proc(using ctx: ^VkContext) -> (objs: [MAX_FRAMES_IN_FLIGHT]SyncObjects) {
	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	for &o in objs {
		result := vk.CreateSemaphore(device, &semaphore_info, nil, &o.image_available)
		if result != .SUCCESS {
			panic("Failed to create image available semaphore.")
		}
		result = vk.CreateSemaphore(device, &semaphore_info, nil, &o.render_finished)
		if result != .SUCCESS {
			panic("Failed to create render finished semaphore.")
		}
		result = vk.CreateFence(device, &fence_info, nil, &o.in_flight)
		if result != .SUCCESS {
			panic("Failed to create fence.")
		}
	}

	return
}
