extends Node

signal auth_state_changed(user: Dictionary)
signal auth_error(message: String)
signal profile_saved

const AUTH_BASE_URL := "https://identitytoolkit.googleapis.com/v1/accounts"
const FIRESTORE_BASE_URL := "https://firestore.googleapis.com/v1/projects"

var current_user: Dictionary = {}
var _id_token: String = ""
var _api_key: String = ""
var _project_id: String = ""


func _ready() -> void:
	_api_key = str(ProjectSettings.get_setting("firebase/api_key", "")).strip_edges()
	_project_id = str(ProjectSettings.get_setting("firebase/project_id", "")).strip_edges()


func sign_up_with_email(email: String, password: String) -> bool:
	return await _authenticate("signUp", email, password)


func sign_in_with_email(email: String, password: String) -> bool:
	return await _authenticate("signInWithPassword", email, password)


func sign_out() -> void:
	_id_token = ""
	current_user.clear()
	auth_state_changed.emit({})


func save_player_profile(profile: Dictionary) -> bool:
	if not _require_authentication():
		return false

	var uid := str(current_user.get("uid", ""))
	var url := "%s/%s/databases/(default)/documents/playerProfiles/%s" % [
		FIRESTORE_BASE_URL, _project_id, uid
	]
	var fields: Dictionary = {}
	for key in profile:
		fields[str(key)] = _to_firestore_value(profile[key])

	var result: Dictionary = await _send_json_request(
		url,
		HTTPClient.METHOD_PATCH,
		{
			"Authorization": "Bearer " + _id_token,
			"Content-Type": "application/json"
		},
		JSON.stringify({"fields": fields})
	)
	if not result.get("ok", false):
		auth_error.emit(str(result.get("error", "Could not save player profile.")))
		return false

	profile_saved.emit()
	return true


func load_player_profile() -> Dictionary:
	if not _require_authentication():
		return {}

	var uid := str(current_user.get("uid", ""))
	var url := "%s/%s/databases/(default)/documents/playerProfiles/%s" % [
		FIRESTORE_BASE_URL, _project_id, uid
	]
	var result: Dictionary = await _send_json_request(
		url,
		HTTPClient.METHOD_GET,
		{"Authorization": "Bearer " + _id_token}
	)
	if not result.get("ok", false):
		auth_error.emit(str(result.get("error", "Could not load player profile.")))
		return {}

	var document: Dictionary = result.get("data", {})
	var firestore_fields: Dictionary = document.get("fields", {})
	var profile: Dictionary = {}
	for key in firestore_fields:
		profile[str(key)] = _from_firestore_value(firestore_fields[key])
	return profile


func _authenticate(endpoint: String, email: String, password: String) -> bool:
	if not _has_firebase_config():
		auth_error.emit("Set firebase/api_key and firebase/project_id in Project Settings first.")
		return false
	if email.strip_edges().is_empty() or password.is_empty():
		auth_error.emit("Email and password are required.")
		return false

	var url := "%s:%s?key=%s" % [AUTH_BASE_URL, endpoint, _api_key.uri_encode()]
	var result: Dictionary = await _send_json_request(
		url,
		HTTPClient.METHOD_POST,
		{"Content-Type": "application/json"},
		JSON.stringify({
			"email": email.strip_edges(),
			"password": password,
			"returnSecureToken": true
		})
	)
	if not result.get("ok", false):
		auth_error.emit(str(result.get("error", "Firebase authentication failed.")))
		return false

	var response: Dictionary = result.get("data", {})
	_id_token = str(response.get("idToken", ""))
	current_user = {
		"uid": str(response.get("localId", "")),
		"email": str(response.get("email", email.strip_edges())),
		"display_name": str(response.get("displayName", ""))
	}
	if _id_token.is_empty() or str(current_user.uid).is_empty():
		_id_token = ""
		current_user.clear()
		auth_error.emit("Firebase returned an incomplete authentication response.")
		return false

	auth_state_changed.emit(current_user.duplicate(true))
	return true


func _has_firebase_config() -> bool:
	if _api_key.is_empty() or _project_id.is_empty():
		return false
	return true


func _require_authentication() -> bool:
	if not _has_firebase_config():
		auth_error.emit("Set firebase/api_key and firebase/project_id in Project Settings first.")
		return false
	if _id_token.is_empty() or current_user.is_empty():
		auth_error.emit("Sign in before accessing player profiles.")
		return false
	return true


func _send_json_request(
	url: String,
	method: HTTPClient.Method,
	headers: Dictionary,
	body: String = ""
) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var header_list: PackedStringArray = []
	for key in headers:
		header_list.append("%s: %s" % [key, headers[key]])

	var request_error := http.request(url, header_list, method, body)
	if request_error != OK:
		http.queue_free()
		return {"ok": false, "error": "Could not start Firebase request (error %d)." % request_error}

	var response: Array = await http.request_completed
	http.queue_free()
	var result_code: int = response[0]
	var response_code: int = response[1]
	var response_body: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Firebase network request failed (error %d)." % result_code}
	if response_code < 200 or response_code >= 300:
		var error_info: Dictionary = data.get("error", {})
		return {
			"ok": false,
			"error": _firebase_error_message(str(error_info.get("message", "HTTP %d" % response_code)))
		}
	return {"ok": true, "data": data}


func _firebase_error_message(code: String) -> String:
	match code:
		"EMAIL_EXISTS":
			return "An account with this email already exists."
		"EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS":
			return "The email or password is incorrect."
		"WEAK_PASSWORD":
			return "The password must contain at least 6 characters."
		"INVALID_EMAIL":
			return "Enter a valid email address."
		"API_KEY_INVALID":
			return "The Firebase API key is invalid."
		"PROJECT_NOT_FOUND":
			return "The Firebase project was not found."
		_:
			return "Firebase error: %s" % code


func _to_firestore_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			return {"nullValue": null}
		TYPE_BOOL:
			return {"booleanValue": value}
		TYPE_INT:
			return {"integerValue": str(value)}
		TYPE_FLOAT:
			return {"doubleValue": value}
		TYPE_ARRAY:
			var values: Array = []
			for item in value:
				values.append(_to_firestore_value(item))
			return {"arrayValue": {"values": values}}
		TYPE_DICTIONARY:
			var fields: Dictionary = {}
			for key in value:
				fields[str(key)] = _to_firestore_value(value[key])
			return {"mapValue": {"fields": fields}}
		_:
			return {"stringValue": str(value)}


func _from_firestore_value(value: Dictionary) -> Variant:
	if value.has("stringValue"):
		return value["stringValue"]
	if value.has("booleanValue"):
		return value["booleanValue"]
	if value.has("integerValue"):
		return int(value["integerValue"])
	if value.has("doubleValue"):
		return float(value["doubleValue"])
	if value.has("nullValue"):
		return null
	if value.has("arrayValue"):
		var values: Array = value["arrayValue"].get("values", [])
		var decoded: Array = []
		for item in values:
			decoded.append(_from_firestore_value(item))
		return decoded
	if value.has("mapValue"):
		var fields: Dictionary = value["mapValue"].get("fields", {})
		var decoded: Dictionary = {}
		for key in fields:
			decoded[str(key)] = _from_firestore_value(fields[key])
		return decoded
	return null
