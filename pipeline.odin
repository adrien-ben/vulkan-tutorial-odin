package main

import "core:log"
import "core:os"
import "core:slice"
import "core:time"
import vk "vendor:vulkan"

ENABLE_PIPELINE_CACHE :: #config(ENABLE_PIPELINE_CACHE, true)

PIPELINE_CACHE_FILE_PATH :: "pipeline_cache.bin"

create_graphics_pipeline_layout :: proc(
	using ctx: ^VkContext,
	descriptor_set_layout: vk.DescriptorSetLayout,
) -> (
	layout: vk.PipelineLayout,
) {
	// layout
	descriptor_set_layout := descriptor_set_layout
	layout_create_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &descriptor_set_layout,
	}
	result := vk.CreatePipelineLayout(device, &layout_create_info, nil, &layout)
	if result != .SUCCESS {
		panic("Failed to create graphics pipeline layout.")
	}
	return
}

when ENABLE_PIPELINE_CACHE {
	create_pipeline_cache :: proc(using ctx: ^VkContext) -> (cache: vk.PipelineCache) {
		create_info := vk.PipelineCacheCreateInfo {
			sType = .PIPELINE_CACHE_CREATE_INFO,
		}

		data, success := os.read_entire_file(PIPELINE_CACHE_FILE_PATH)
		defer delete(data)
		if success && len(data) > size_of(vk.PipelineCacheHeaderVersionOne) {
			header := slice.to_type(data, vk.PipelineCacheHeaderVersionOne)
			expected_header := vk.PipelineCacheHeaderVersionOne {
				headerSize        = size_of(vk.PipelineCacheHeaderVersionOne),
				headerVersion     = .ONE,
				vendorID          = pdevice.properties.vendorID,
				deviceID          = pdevice.properties.deviceID,
				pipelineCacheUUID = pdevice.properties.pipelineCacheUUID,
			}

			if header == expected_header {
				create_info.initialDataSize = len(data)
				create_info.pInitialData = raw_data(data)
			} else {
				log.warn(
					"Found cached pipeline data but it's incompatible with selected physical device.",
				)
			}
		}

		if vk.CreatePipelineCache(device, &create_info, nil, &cache) != .SUCCESS {
			panic("Failed to create pipeline cache.")
		}
		return
	}

	save_and_destroy_pipeline_cache :: proc(using ctx: ^VkContext, cache: vk.PipelineCache) {
		success: bool
		max_data_size: int
		result := vk.GetPipelineCacheData(device, cache, &max_data_size, nil)
		if result == .SUCCESS && max_data_size > 0 {
			data_size := max_data_size
			data := make([dynamic]byte, data_size)
			defer delete(data)
			if vk.GetPipelineCacheData(device, cache, &data_size, raw_data(data)) == .SUCCESS {
				if max_data_size > data_size {
					// From spec: on return the variable (pDataSize) is overwritten with the amount of data actually written to pData
					resize(&data, data_size)
				}
				success = os.write_entire_file(PIPELINE_CACHE_FILE_PATH, data[:])
			}
		}

		if success {
			log.info("Pipeline cache saved to disk.")
		} else {
			log.warn("Failed to serialize pipeline data cache.")
		}

		vk.DestroyPipelineCache(device, cache, nil)
	}
}

create_graphics_pipeline :: proc(
	using ctx: ^VkContext,
	cache: vk.PipelineCache,
	layout: vk.PipelineLayout,
	color_format: vk.Format,
	depth_format: vk.Format,
	display_mode: DisplayMode,
) -> (
	pipeline: vk.Pipeline,
) {
	start := time.tick_now()

	// shader modules
	vertex_shader_src := #load("shaders/vertex.spv", []u32)
	vertex_shader_module := create_shader_module(device, vertex_shader_src)
	defer {
		vk.DestroyShaderModule(device, vertex_shader_module, nil)
		log.debug("Vertex shader module destroyed.")
	}
	log.debug("Vertex shader module created.")

	fragment_shader_src := #load("shaders/fragment.spv", []u32)
	fragment_shader_module := create_shader_module(device, fragment_shader_src)
	defer {
		vk.DestroyShaderModule(device, fragment_shader_module, nil)
		log.debug("Fragment shader module destroyed.")
	}
	log.debug("Fragment shader module created.")

	// shader stages
	fragment_stage_specialization_entries := vk.SpecializationMapEntry {
		constantID = 0,
		offset     = 0,
		size       = size_of(u32),
	}
	display_mode := display_mode
	fragment_stage_specialization := vk.SpecializationInfo {
		dataSize      = size_of(u32),
		mapEntryCount = 1,
		pMapEntries   = &fragment_stage_specialization_entries,
		pData         = &display_mode,
	}

	shader_stages := []vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vertex_shader_module,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = fragment_shader_module,
			pName = "main",
			pSpecializationInfo = &fragment_stage_specialization,
		},
	}

	// dynamic states
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states),
	}

	// vertex input
	binding_desc := get_vertex_binding_description()
	attrib_descs := get_vertex_attribute_descriptions()
	vertex_input_state := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding_desc,
		vertexAttributeDescriptionCount = len(attrib_descs),
		pVertexAttributeDescriptions    = raw_data(attrib_descs[:]),
	}

	// input assembly
	input_assembly_state := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	// viewport and scissor
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		scissorCount  = 1,
		viewportCount = 1,
	}

	// rasterizer
	raster_state := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		lineWidth               = 1,
		cullMode                = {},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
	}

	// multisampling
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {ctx.pdevice.max_sample_count},
	}

	// color blending
	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable    = false,
	}
	color_blend_state := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	// depth stencil
	depth_stencil_state := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS,
	}

	// dynamic rendering
	color_format := color_format
	rendering_state := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &color_format,
		depthAttachmentFormat   = depth_format,
	}

	// pipeline
	create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = u32(len(shader_stages)),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_state,
		pInputAssemblyState = &input_assembly_state,
		pViewportState      = &viewport_state,
		pRasterizationState = &raster_state,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blend_state,
		pDepthStencilState  = &depth_stencil_state,
		pDynamicState       = &dynamic_state,
		pNext               = &rendering_state,
		layout              = layout,
	}

	result := vk.CreateGraphicsPipelines(device, cache, 1, &create_info, nil, &pipeline)
	if result != .SUCCESS {
		panic("Failed to create graphics pipeline.")
	}

	dur := time.tick_since(start)
	log.infof("Pipeline creation time: %v micro seconds", u64(time.duration_microseconds(dur)))

	return
}

create_shader_module :: proc(device: vk.Device, src: []u32) -> (module: vk.ShaderModule) {
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = size_of(u32) * len(src),
		pCode    = raw_data(src),
	}

	result := vk.CreateShaderModule(device, &create_info, nil, &module)
	if result != .SUCCESS {
		panic("Failed to create shader module.")
	}
	return
}
