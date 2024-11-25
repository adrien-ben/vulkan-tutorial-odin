package objloader

import "core:fmt"
import "core:testing"

@(test)
load_simple_obj :: proc(t: ^testing.T) {
	data := `v -0.5 -0.5 0
v 0.5 -0.5 0
v 0.5 0.5 0
v -0.5 0.5 0
vt 1 1
vt 0 1
vt 0 0
vt 1 0
f 1/1 2/2 3/3
f 3/3 4/4 1/1
`


	obj, err := load_from_bytes(transmute([]byte)data)
	defer destroy(obj)

	expected := Obj {
		vertices = [dynamic]Vertex {
			{position = {-0.5, -0.5, 0}, tex_coords = {1, 0}},
			{position = {0.5, -0.5, 0}, tex_coords = {0, 0}},
			{position = {0.5, 0.5, 0}, tex_coords = {0, 1}},
			{position = {-0.5, 0.5, 0}, tex_coords = {1, 1}},
		},
		indices  = [dynamic]u32{0, 1, 2, 2, 3, 0},
	}
	defer destroy(expected)

	testing.expect_value(t, len(obj.vertices), len(expected.vertices))
	for i in 0 ..< len(expected.vertices) {
		testing.expect_value(t, obj.vertices[i], expected.vertices[i])
	}

	testing.expect_value(t, len(obj.indices), len(expected.indices))
	for i in 0 ..< len(expected.indices) {
		testing.expect_value(t, obj.indices[i], expected.indices[i])
	}
}
