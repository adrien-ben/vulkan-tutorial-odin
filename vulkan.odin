package main

import "base:runtime"
import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

WIN_WIDTH :: 800
WIN_HEIGHT :: 600

ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

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

	vk.load_proc_addresses((rawptr)(glfw.GetInstanceProcAddress))

	instance := create_instance()
	defer {
		vk.DestroyInstance(instance, nil)
		fmt.println("Vulkan instance destroyed.")
	}
	fmt.println("Vulkan instance created.")

	vk.load_proc_addresses(instance)

	when ENABLE_VALIDATION_LAYERS {
		debug_messenger := setup_debug_messenger(instance)
		defer {
			vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
			fmt.println("Vulkan debug messenger destroyed.")
		}
		fmt.println("Vulkan debug messenger created.")
	}

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
	}
}

create_instance :: proc() -> vk.Instance {
	// list required instance extensions
	required_exts: [dynamic]cstring
	defer delete(required_exts)

	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	append(&required_exts, ..glfw_extensions[:])
	when ENABLE_VALIDATION_LAYERS {
		append(&required_exts, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}
	when ODIN_OS == .Darwin {
		append(&required_exts, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	result: vk.Result
	// check extensions support
	{
		supported_exts_count: u32
		result = vk.EnumerateInstanceExtensionProperties(nil, &supported_exts_count, nil)
		if result != .SUCCESS {
			panic("Failed to get instance extension count.")
		}

		supported_exts := make([]vk.ExtensionProperties, supported_exts_count)
		defer delete(supported_exts)
		result = vk.EnumerateInstanceExtensionProperties(
			nil,
			&supported_exts_count,
			raw_data(supported_exts),
		)
		if result != .SUCCESS {
			panic("Failed to list instance extensions.")
		}

		all_extensions_supported := true
		for required in required_exts {
			found := false
			for &supported in supported_exts {
				supported := cstring(&supported.extensionName[0])
				if supported == required {
					found = true
					break
				}
			}

			if !found {
				fmt.eprintln("Required extension", required, "not supported")
				all_extensions_supported = false
			}

		}
		if !all_extensions_supported {
			panic("Not all required instance extensions are supported.")
		}
	}

	// check validation layers support
	when ENABLE_VALIDATION_LAYERS {
		layer_count: u32
		result = vk.EnumerateInstanceLayerProperties(&layer_count, nil)
		if result != .SUCCESS {
			panic("Failed to get validation layer count.")
		}

		supported_layers := make([]vk.LayerProperties, layer_count)
		defer delete(supported_layers)
		result = vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(supported_layers))
		if result != .SUCCESS {
			panic("Failed to list validation layers.")
		}

		all_layers_supported := true
		for required in VALIDATION_LAYERS {
			found := false
			for &supported in supported_layers {
				supported := cstring(&supported.layerName[0])
				if supported == required {
					found = true
					break
				}
			}

			if !found {
				fmt.eprintln("Required validation layer", required, "not supported")
				all_layers_supported = false
			}
		}
		if !all_layers_supported {
			panic("Not all required validation layers are supported.")
		}
	}

	// create the instance
	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Vulkan Tutorial",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_0,
	}
	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(required_exts)),
		ppEnabledExtensionNames = raw_data(required_exts),
		enabledLayerCount       = 0,
	}
	when ENABLE_VALIDATION_LAYERS {
		create_info.enabledLayerCount = u32(len(VALIDATION_LAYERS))
		create_info.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS[:])

		debug_messenger_create_info := create_setup_messenger_create_info()
		create_info.pNext = &debug_messenger_create_info
	}
	when ODIN_OS == .Darwin {
		create_info.flags = {.ENUMERATE_PORTABILITY_KHR}
	}

	instance: vk.Instance
	result = vk.CreateInstance(&create_info, nil, &instance)
	if result != .SUCCESS {
		panic("Failed to create instance.")
	}

	return instance
}

when ENABLE_VALIDATION_LAYERS {
	messenger_callback :: proc "system" (
		severity: vk.DebugUtilsMessageSeverityFlagsEXT,
		_: vk.DebugUtilsMessageTypeFlagsEXT,
		data: ^vk.DebugUtilsMessengerCallbackDataEXT,
		_: rawptr,
	) -> b32 {
		context = runtime.default_context()

		switch severity {
		case {.ERROR}:
			fmt.eprintln("validation:", data.pMessage)
		case:
			fmt.println("validation:", data.pMessage)
		}

		return false
	}

	create_setup_messenger_create_info :: proc() -> vk.DebugUtilsMessengerCreateInfoEXT {
		return {
			sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
			messageType = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING},
			pfnUserCallback = messenger_callback,
		}
	}

	setup_debug_messenger :: proc(instance: vk.Instance) -> vk.DebugUtilsMessengerEXT {
		create_info := create_setup_messenger_create_info()
		messenger: vk.DebugUtilsMessengerEXT
		result := vk.CreateDebugUtilsMessengerEXT(instance, &create_info, nil, &messenger)
		if result != .SUCCESS {
			panic("Failed to create debug messenger.")
		}
		return messenger
	}
}
