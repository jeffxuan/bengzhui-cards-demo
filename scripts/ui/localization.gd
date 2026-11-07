extends RefCounted

const EnglishTranslationScript = preload("res://scripts/ui/english_translation.gd")
static var english: Translation
static var language: String = "zh_CN"


static func set_language(value: String) -> void:
	if english == null:
		english = EnglishTranslationScript.new()
		TranslationServer.add_translation(english)
		# Release scripted translations while the GDScript runtime is still alive.
		# The native TranslationServer otherwise outlives it during engine shutdown.
		(Engine.get_main_loop() as SceneTree).root.tree_exiting.connect(shutdown, CONNECT_ONE_SHOT)
	language = "en" if value == "en" else "zh_CN"
	TranslationServer.set_locale(language)


static func shutdown() -> void:
	if english != null:
		TranslationServer.remove_translation(english)
		english = null


static func text(source: String) -> String:
	if language != "en" or english == null:
		return source
	return String(english.call("render", source))
