package objloader

import "core:os"
import "core:strconv"
import "core:strings"

Vec3 :: [3]f32
Vec2 :: [2]f32

@(private)
Face :: struct {
	position: [3]int,
	coords:   [3]int,
	normal:   [3]int,
}

Vertex :: struct {
	position:   Vec3,
	tex_coords: Vec2,
	normal:     Vec3,
}

Obj :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
}

Error :: enum {
	None,
	OS,
	InvalidVertexPosition,
	InvalidVertexTextureCoordinates,
	InvalidVertexNormal,
	UnsupportedQuadFaces,
	InvalidFace,
	InvalidFaceIndex,
}

destroy :: proc(using obj: Obj) {
	delete(vertices)
	delete(indices)
}


load_from_file :: proc(path: string) -> (o: Obj, error: Error) {
	data, success := os.read_entire_file(path)
	if !success {
		error = .OS
		return
	}
	defer delete(data)

	return load_from_bytes(data)
}

@(private)
load_from_bytes :: proc(data: []byte) -> (o: Obj, error: Error) {
	data_str := string(data)

	positions: [dynamic]Vec3
	defer delete(positions)
	coords: [dynamic]Vec2
	defer delete(coords)
	normals: [dynamic]Vec3
	defer delete(normals)
	faces: [dynamic]Face
	defer delete(faces)

	for line in strings.split_lines_iterator(&data_str) {
		if strings.starts_with(line, "v ") {
			// parse position: x, y, z, [w]
			components, ok := parse_vertex_attribute_f32(4, line)
			if !ok {
				error = .InvalidVertexPosition
				return
			}

			append(&positions, components.xyz)
		} else if strings.starts_with(line, "vt ") {
			// parse texture coordinates: u, v, [w]
			components, ok := parse_vertex_attribute_f32(3, line)
			if !ok {
				error = .InvalidVertexTextureCoordinates
				return
			}

			components.y = 1 - components.y
			append(&coords, components.xy)
		} else if strings.starts_with(line, "vn ") {
			// parse normal: x, y, z
			components, ok := parse_vertex_attribute_f32(3, line)
			if !ok {
				error = .InvalidVertexNormal
				return
			}

			append(&normals, components)
		} else if strings.starts_with(line, "f ") {
			// parse face

			face: Face
			line := line
			i := 0
			for token in strings.split_iterator(&line, " ") {
				if i == 4 {
					error = .UnsupportedQuadFaces
					return
				}

				if i > 0 {
					face_indices: [3]int // position, [texture coordinates, [normal]]

					token := token
					j := 0
					for face_idx in strings.split_iterator(&token, "/") {
						if j == 3 {
							error = .InvalidFace
							return
						}


						v, parsed := strconv.parse_int(face_idx)
						if !parsed {
							error = .InvalidFaceIndex
							return
						}
						face_indices[j] = v

						j += 1
					}

					face.position[i - 1] = face_indices[0] - 1
					face.coords[i - 1] = face_indices[1] - 1
					face.normal[i - 1] = face_indices[2] - 1
				}
				i += 1
			}

			append(&faces, face)
		}
	}

	index_per_vertex: map[Vertex]u32
	defer delete(index_per_vertex)

	index: u32 = 0
	for face in faces {
		for i in 0 ..= 2 {
			v: Vertex
			if face.position[i] >= 0 {
				v.position = positions[face.position[i]]
			}
			if face.coords[i] >= 0 {
				v.tex_coords = coords[face.coords[i]]
			}
			if face.normal[i] >= 0 {
				v.normal = normals[face.normal[i]]
			}

			idx, ok := index_per_vertex[v]
			if !ok {
				append(&o.vertices, v)

				idx = index
				index_per_vertex[v] = idx
				index += 1
			}

			append(&o.indices, idx)
		}
	}

	return
}

parse_vertex_attribute_f32 :: proc($N: int, line: string) -> (res: [N]f32, ok: bool) {
	i := 0
	line := line
	for token in strings.split_iterator(&line, " ") {
		if i == N + 1 {
			return
		}

		if i > 0 {
			v, parsed := strconv.parse_f32(token)
			if !parsed {
				return
			}
			res[i - 1] = v
		}
		i += 1
	}
	ok = true
	return
}
