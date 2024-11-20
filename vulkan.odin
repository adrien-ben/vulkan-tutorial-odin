package main

import "core:fmt"
import "vendor:glfw"

WIN_WIDTH :: 800
WIN_HEIGHT :: 600

main :: proc() {
	fmt.println("Hello Vulkan!")

	if !glfw.Init() {
		panic("Failed to init GLFW.")
	}
	defer {
		glfw.Terminate()
		fmt.println("GLFW terminated.")
	}
	fmt.println("GLFW initialized.")

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, false)
	window := glfw.CreateWindow(WIN_WIDTH, WIN_HEIGHT, "Vulkan", nil, nil)
	if window == nil {
		panic("Failed to create GLFW window.")
	}
	defer {
		glfw.DestroyWindow(window)
		fmt.println("Window destroyed.")
	}
	fmt.println("Window created.")

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
	}
}
