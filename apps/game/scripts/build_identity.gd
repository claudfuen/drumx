extends RefCounted

const PATH = "res://build-info.json"
const REQUIRED = ["schema", "base_version", "version", "build_number", "channel", "commit", "short_commit", "dirty", "workflow_run", "release_tag"]

static func matches(value: Variant, pattern: String) -> bool:
	if not value is String: return false
	var expression := RegEx.new()
	return expression.compile(pattern) == OK and expression.search(value) != null

static func whole(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= 0 and float(value) <= 65535

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in REQUIRED:
		if not value.has(key): return false
	if not whole(value.schema) or int(value.schema) != 1 or not whole(value.build_number) or not value.dirty is bool:
		return false
	if not value.version is String or not value.channel is String: return false
	if not matches(value.base_version, "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"):
		return false
	for part in value.base_version.split("."):
		if part.length() > 5 or int(part) > 65535: return false
	if not matches(value.commit, "^[0-9a-f]{40}$") or not value.short_commit is String or value.short_commit != value.commit.left(12):
		return false
	if value.workflow_run != null and not matches(value.workflow_run, "^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+$"):
		return false
	if value.release_tag != null and (not matches(value.release_tag, "^[A-Za-z0-9][A-Za-z0-9._-]*$") or value.release_tag.length() > 128):
		return false
	if value.channel == "preview":
		return not value.dirty and int(value.build_number) > 0 and value.workflow_run != null and value.version == "%s-preview.%d" % [value.base_version, int(value.build_number)] and value.release_tag == "v" + value.version
	if value.channel == "dev":
		return int(value.build_number) == 0 and value.workflow_run == null and value.release_tag == null and value.version == "%s-dev+%s%s" % [value.base_version, value.short_commit, ".dirty" if value.dirty else ""]
	return false

static func load_info(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not valid(parser.data): return {}
	var result: Dictionary = parser.data.duplicate(true)
	result.schema = int(result.schema)
	result.build_number = int(result.build_number)
	return result

static func footer_label(info: Dictionary) -> String:
	if not valid(info): return "Development build · version unavailable"
	return str(info.version) if str(info.version).contains(info.short_commit) else "%s · %s" % [info.version, info.short_commit]

static func details(info: Dictionary) -> String:
	if not valid(info):
		return "Drumx development build\nVersion unavailable\n\nThis source or editor build has no valid generated build identity."
	var lines := ["Drumx " + str(info.version), "Commit: " + str(info.commit),
		"Channel: " + ("Experimental preview" if info.channel == "preview" else "Development"),
		"Build number: " + str(info.build_number), "Source: " + ("Local changes present" if info.dirty else "Clean checkout")]
	if info.release_tag != null: lines.append("Release: " + str(info.release_tag))
	if info.workflow_run != null: lines.append("Build workflow: " + str(info.workflow_run))
	return "\n".join(lines)

static func smoke_payload(info: Dictionary) -> Dictionary:
	return info.duplicate(true) if valid(info) else {"available": false, "message": "Development build; version unavailable"}

static func run_checks() -> Dictionary:
	var result := {"checks": 0, "failures": []}
	var check := func(ok: bool, description: String) -> void:
		result.checks += 1
		if not ok: result.failures.append(description)
	var info := {"schema": 1, "base_version": "0.1.0", "version": "0.1.0-preview.17", "build_number": 17,
		"channel": "preview", "commit": "a".repeat(40), "short_commit": "a".repeat(12), "dirty": false,
		"workflow_run": "https://github.com/claudfuen/drumx/actions/runs/123", "release_tag": "v0.1.0-preview.17"}
	check.call(valid(info), "Generated preview identity is accepted")
	check.call(footer_label(info) == "0.1.0-preview.17 · aaaaaaaaaaaa", "Menu includes exact version and short commit")
	check.call(details(info).contains(info.commit) and details(info).contains(info.workflow_run), "Copyable details include full commit and workflow")
	check.call(smoke_payload(info) == info, "Smoke reports the complete executable identity unchanged")
	for key in REQUIRED:
		var missing: Dictionary = info.duplicate(true)
		missing.erase(key)
		check.call(not valid(missing), "Missing " + str(key) + " is not a valid identity")
	for change in [{"schema": 2}, {"build_number": 1.5}, {"build_number": true}, {"build_number": -1}, {"build_number": 65536},
		{"version": "0.1.0-preview.18"}, {"base_version": "01.1.0"}, {"channel": "stable"},
		{"dirty": true}, {"short_commit": "b".repeat(12)}, {"commit": "a".repeat(12)},
		{"workflow_run": "https://example.com/actions/runs/123"}, {"workflow_run": null},
		{"release_tag": "bad\nrelease"}, {"release_tag": "v0.1.0-preview.18"}, {"release_tag": null}]:
		var changed: Dictionary = info.duplicate(true)
		changed.merge(change, true)
		check.call(not valid(changed), "Inconsistent identity rejected: " + str(change.keys()[0]))
	var development: Dictionary = info.duplicate(true)
	development.merge({"version": "0.1.0-dev+aaaaaaaaaaaa.dirty", "channel": "dev", "dirty": true,
		"build_number": 0, "workflow_run": null, "release_tag": null}, true)
	check.call(valid(development), "Local dirty development version is accepted and identified")
	check.call(footer_label(development) == development.version, "Development footer retains embedded commit without repeating it")
	check.call(details(development).contains("Local changes present"), "Details distinguish local edits")
	development.dirty = false
	development.version = "0.1.0-dev+aaaaaaaaaaaa"
	check.call(valid(development), "Clean local development identity is accepted")
	check.call(footer_label({}) == "Development build · version unavailable", "Missing metadata never invents a version")
	check.call(not smoke_payload({}).available, "Unstamped executable reports unavailable identity")
	check.call(load_info("res://missing-build-identity-fixture.json").is_empty(), "Missing metadata is a read-only development fallback")
	return result
