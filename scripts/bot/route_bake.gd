class_name RouteBake
extends RefCounted

## Route graph links worked out ahead of time and kept in a file, so a map
## doesn't have to sample its ground for them at load. The file holds a
## format version, a key and the links; the key comes from what the links
## depend on, so a changed map never loads old links.
##   tools/bake-routes.sh

const VERSION := 1
const MAGIC := 0x52544531


## Key for the links to add on a graph with these points, from the points and
## a string of the settings that went into making the links.
static func key_for(points: PackedVector3Array, settings: String) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(("v%d %s" % [VERSION, settings]).to_utf8_buffer())
	hash.update(points.to_byte_array())
	return hash.finish().hex_encode()


## Writes the graph's links from index first up to end. Returns true if it saved.
static func save(path: String, key: String, graph: RouteGraph, first: int, end: int) -> bool:
	var count := end - first
	var from := PackedInt32Array()
	var to := PackedInt32Array()
	var flags := PackedByteArray()
	var steep := PackedFloat64Array()
	for k in count:
		var link := graph.links[first + k]
		from.append(link.from)
		to.append(link.to)
		flags.append(link.kind | (4 if link.must_jet else 0))
		steep.append(link.steep)
	var body := PackedByteArray()
	body.append_array(from.to_byte_array())
	body.append_array(to.to_byte_array())
	body.append_array(flags)
	body.append_array(steep.to_byte_array())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_32(MAGIC)
	file.store_pascal_string(key)
	file.store_32(count)
	file.store_32(body.size())
	file.store_buffer(body.compress(FileAccess.COMPRESSION_ZSTD))
	file.close()
	return true


## Adds the saved links to the graph. Returns false, adding nothing, if the
## file is missing, damaged or made for different points or settings.
static func load_into(path: String, key: String, graph: RouteGraph) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_32() != MAGIC:
		return false
	if file.get_pascal_string() != key:
		return false
	var count := file.get_32()
	var size := file.get_32()
	var body := file.get_buffer(file.get_length() - file.get_position()).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if body.size() != size or size != count * 17:
		return false
	var from := body.slice(0, count * 4).to_int32_array()
	var to := body.slice(count * 4, count * 8).to_int32_array()
	var flags := body.slice(count * 8, count * 9)
	var steep := body.slice(count * 9, count * 17).to_float64_array()
	var n := graph.points.size()
	for k in count:
		if from[k] < 0 or from[k] >= n or to[k] < 0 or to[k] >= n:
			return false
	for k in count:
		graph.add_link(from[k], to[k], (flags[k] & 3) as RouteGraph.Kind, flags[k] & 4 != 0, steep[k])
	return true
