package objloader

import "core:os"
import "core:strconv"
import "core:strings"

Vec3 :: distinct [3]f32
Vec2 :: distinct [2]f32

@(private)
Face :: struct {
	position: [3]int,
	coords:   [3]int,
}

Vertex :: struct {
	position:   Vec3,
	tex_coords: Vec2,
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

	o, error = load_from_bytes(data)
	return
}

@(private)
load_from_bytes :: proc(data: []byte) -> (o: Obj, error: Error) {
	data_str := string(data)

	positions: [dynamic]Vec3
	defer delete(positions)
	coords: [dynamic]Vec2
	defer delete(coords)
	faces: [dynamic]Face
	defer delete(faces)

	for line in strings.split_lines_iterator(&data_str) {
		if strings.starts_with(line, "v ") {
			// parse position

			components: [4]f32 // x, y, z, [w]
			line := line
			i := 0
			for token in strings.split_iterator(&line, " ") {
				if i == 5 {
					error = .InvalidVertexPosition
					return
				}

				if i > 0 {
					v, parsed := strconv.parse_f32(token)
					if !parsed {
						error = .InvalidVertexPosition
						return
					}
					components[i - 1] = v
				}
				i += 1
			}

			pos := Vec3{components[0], components[1], components[2]}
			append(&positions, pos)
		} else if strings.starts_with(line, "vt ") {
			// parse texture coordinates

			components: [3]f32 // u, v, [w]
			line := line
			i := 0
			for token in strings.split_iterator(&line, " ") {
				if i == 4 {
					error = .InvalidVertexTextureCoordinates
					return
				}

				if i > 0 {
					v, parsed := strconv.parse_f32(token)
					if !parsed {
						error = .InvalidVertexTextureCoordinates
						return
					}
					components[i - 1] = v
				}
				i += 1
			}

			uv := Vec2{components[0], 1 - components[1]}
			append(&coords, uv)
		} else if strings.starts_with(line, "f") {
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
			v := Vertex {
				position   = positions[face.position[i]],
				tex_coords = coords[face.coords[i]],
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
