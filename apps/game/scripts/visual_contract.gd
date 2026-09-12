extends RefCounted
## Compare the shared renderer with points exported by the original Swift code.
## Explicit failures run in release exports too; no assert-only side effects.

static func compare_stage(stage: Control, fixture: Dictionary) -> Dictionary:
	var checks := 0
	var failures: Array[String] = []
	if not fixture.get("cases") is Array or fixture.cases.is_empty():
		return {"checks": 1, "failures": ["Native visual fixture has no cases."]}
	for case_index in range(fixture.cases.size()):
		var item: Dictionary = fixture.cases[case_index]
		if not item.get("size") is Array or item.size.size() != 2 or not item.get("points") is Array or not item.get("notes") is Array:
			failures.append("Invalid native visual case %d." % case_index)
			continue
		stage.size = Vector2(float(item.size[0]), float(item.size[1]))
		# Switching guidance must not change instrument positions or projection.
		for guidance in [0, 1, 2]:
			stage.guidance = guidance
			for point in item.points:
				checks += 1
				var actual: Vector2 = stage.project(float(point.lateral), float(point.beat))
				var expected := Vector2(float(point.point[0]), float(point.point[1]))
				# Godot Vector2 is float32 in official builds; Swift baseline is double.
				if actual.distance_to(expected) > 0.0002:
					failures.append("Case %d guidance %d: native point differs at lateral %s, beat %s." % [case_index, guidance, point.lateral, point.beat])
			for note in item.notes:
				checks += 1
				var actual: PackedVector2Array = stage.note_vertices(int(note.pad), float(note.beat))
				if actual.size() != note.vertices.size():
					failures.append("Case %d: pad %s has a different silhouette vertex count." % [case_index, note.pad])
					continue
				for vertex_index in range(actual.size()):
					checks += 1
					var expected := Vector2(float(note.vertices[vertex_index][0]), float(note.vertices[vertex_index][1]))
					if actual[vertex_index].distance_to(expected) > 0.0002:
						failures.append("Case %d guidance %d: pad %s beat %s vertex %d differs from Swift." % [case_index, guidance, note.pad, note.beat, vertex_index])
				checks += 1
				if absf(float(stage.far_visibility(float(note.beat))) - float(note.opacity)) > 0.000001:
					failures.append("Case %d: pad %s beat %s has different far opacity." % [case_index, note.pad, note.beat])
	return {"checks": checks, "failures": failures}
