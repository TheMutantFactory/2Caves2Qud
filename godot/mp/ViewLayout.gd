# Where the split-screen panels go: of every grid that can hold the panels, the one
# whose cells are closest to the screen's own shape, largest first. One player gets
# the whole screen, two get side by side on a wide screen, three and four a 2x2.
class_name ViewLayout
extends RefCounted

const GUTTER := 6.0


static func panels(count: int, area: Rect2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if count <= 0:
		return rects
	var grid := best_grid(count, area.size)
	var columns: int = grid["columns"]
	var rows: int = grid["rows"]
	var cell := Vector2(area.size.x / float(columns), area.size.y / float(rows))
	for index in count:
		var origin := area.position + Vector2(float(index % columns) * cell.x, float(index / columns) * cell.y)
		rects.append(Rect2(origin, cell).grow(-GUTTER * 0.5))
	return rects


static func best_grid(count: int, area: Vector2) -> Dictionary:
	var best := {"columns": 1, "rows": count}
	var best_score := -1.0
	var want := area.x / maxf(1.0, area.y)
	for columns in range(1, count + 1):
		var rows := int(ceil(float(count) / float(columns)))
		var cell := Vector2(area.x / float(columns), area.y / float(rows))
		var aspect := cell.x / maxf(1.0, cell.y)
		var shape := minf(aspect / want, want / aspect)   # 1 = the screen's own shape
		var score := cell.x * cell.y * shape
		if score > best_score + 0.001:
			best_score = score
			best = {"columns": columns, "rows": rows}
	return best
