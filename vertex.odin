package main

import vk "vendor:vulkan"

Vec2 :: distinct [2]f32
Vec3 :: distinct [3]f32
Vertex :: struct {
	pos:   Vec2,
	color: Vec3,
}

VERTICES :: [?]Vertex {
	{pos = {0, -0.5}, color = {1, 0, 0}},
	{pos = {0.5, 0.5}, color = {0, 1, 0}},
	{pos = {-0.5, 0.5}, color = {0, 0, 1}},
}

get_vertex_binding_description :: proc() -> vk.VertexInputBindingDescription {
	return vk.VertexInputBindingDescription {
		binding = 0,
		stride = size_of(Vertex),
		inputRate = .VERTEX,
	}
}

get_vertex_attribute_descriptions :: proc() -> [2]vk.VertexInputAttributeDescription {
	return [2]vk.VertexInputAttributeDescription {
		{binding = 0, location = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
		{
			binding = 0,
			location = 1,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Vertex, color)),
		},
	}
}
