extends Translation
## Presentation-only translation. Rules, commands and replay data stay unchanged.

var entries: Dictionary = {}
var templates: Array[Dictionary] = []
var numeric_fragments: Array[Dictionary] = []
var fragments: Array[String] = []
var cache: Dictionary = {}


func _init() -> void:
	locale = "en"
	for path: String in ["res://localization/en_ui.json", "res://localization/en_content.json", "res://localization/en_messages.json"]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			entries.merge(data as Dictionary, true)
	var format_pattern := RegEx.create_from_string("%[-+0-9.]*[sdf]")
	for source: String in entries:
		var tokens := format_pattern.search_all(source)
		if tokens.is_empty():
			fragments.append(source)
			continue
		var pattern := "^"
		var cursor := 0
		var numeric_only := true
		for token: RegExMatch in tokens:
			if token.get_string().ends_with("s"):
				numeric_only = false
			pattern += _escape_regex(source.substr(cursor, token.get_start() - cursor))
			pattern += "([\\s\\S]*?)" if token.get_string().ends_with("s") else "(-?[0-9]+(?:\\.[0-9]+)?)"
			cursor = token.get_end()
		pattern += _escape_regex(source.substr(cursor)) + "$"
		templates.append({"pattern": RegEx.create_from_string(pattern), "text": String(entries[source]), "tokens": format_pattern.search_all(String(entries[source]))})
		if numeric_only:
			numeric_fragments.append({"pattern": RegEx.create_from_string(pattern.substr(1, pattern.length() - 2)), "text": String(entries[source]), "tokens": format_pattern.search_all(String(entries[source])), "length": source.length()})
	fragments.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	numeric_fragments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["length"]) > int(b["length"]))


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	return StringName(render(String(src_message)))


func render(source: String, depth: int = 0) -> String:
	if cache.has(source):
		return String(cache[source])
	if entries.has(source):
		return String(entries[source])
	if source.is_empty() or depth > 8:
		return source
	for entry: Dictionary in templates:
		var matched: RegExMatch = (entry["pattern"] as RegEx).search(source)
		if matched == null:
			continue
		var result := String(entry["text"])
		var tokens: Array = entry["tokens"] as Array
		# Work backwards so inserting a value cannot become another placeholder.
		for index: int in range(tokens.size() - 1, -1, -1):
			var token := tokens[index] as RegExMatch
			var value := render(matched.get_string(index + 1), depth + 1)
			result = result.substr(0, token.get_start()) + value + result.substr(token.get_end())
		return _remember(source, result)
	if source.contains("\n"):
		var lines := source.split("\n")
		for index: int in lines.size():
			lines[index] = render(lines[index], depth + 1)
		return _remember(source, "\n".join(lines))
	if source.begins_with("[color=") and source.ends_with("[/color]"):
		var close := source.find("]") + 1
		return source.left(close) + render(source.substr(close, source.length() - close - 8), depth + 1) + "[/color]"
	# Joined card names, descriptions and resource chips are translated at the
	# display boundary, never by mutating catalog dictionaries.
	var result := source
	# Numeric chips also occur inside joined labels (cost + range, use limits).
	# String templates stay anchored because their captures have no safe boundary.
	for entry: Dictionary in numeric_fragments:
		var matches := (entry["pattern"] as RegEx).search_all(result)
		for index: int in range(matches.size() - 1, -1, -1):
			var matched := matches[index]
			var replacement := String(entry["text"])
			var tokens: Array = entry["tokens"] as Array
			for token_index: int in range(tokens.size() - 1, -1, -1):
				var token := tokens[token_index] as RegExMatch
				replacement = replacement.substr(0, token.get_start()) + matched.get_string(token_index + 1) + replacement.substr(token.get_end())
			result = result.substr(0, matched.get_start()) + replacement + result.substr(matched.get_end())
	for fragment: String in fragments:
		if result.contains(fragment):
			result = result.replace(fragment, String(entries[fragment]))
	return _remember(source, result)


func _remember(source: String, result: String) -> String:
	if cache.size() > 4096:
		cache.clear()
	cache[source] = result
	return result


func _escape_regex(value: String) -> String:
	var result := ""
	for character: String in value:
		if "\\.^$|?*+()[]{}".contains(character):
			result += "\\"
		result += character
	return result
