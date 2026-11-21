extends RefCounted
## Keeps the save on this device, as one JSON file (user://ocsvr_save.json).
##
## SaveService talks to a backend through two calls, load_data() and
## save_data(). This one is the local file; phase 5 adds an OCS backend with the
## same two calls, so nothing else in the game changes.

const DEFAULT_PATH := "user://ocsvr_save.json"

var path := DEFAULT_PATH


func _init(save_path := DEFAULT_PATH) -> void:
	path = save_path


## The saved data, or {} when there is none yet. A file that isn't valid JSON is
## kept next to it as .bad (so nothing is silently lost) and {} is returned.
func load_data() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Save file %s isn't valid JSON; kept as %s.bad and starting fresh" % [path, path])
		DirAccess.copy_absolute(path, path + ".bad")
		return {}
	return data


## Writes the data. It goes to a .tmp file first and is then renamed over the
## old save, so a crash mid-write never leaves half a file. True when saved.
func save_data(data: Dictionary) -> bool:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_error("Can't write the save to %s (error %d)" % [temp, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp, path) == OK
