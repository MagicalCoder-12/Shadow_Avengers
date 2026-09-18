extends Control

# --- UI Node References ---
@onready var status: Label = $Panel/VBoxContainer/%Status
@onready var email: LineEdit = $Panel/VBoxContainer/%Email
@onready var password: LineEdit = $Panel/VBoxContainer/%Password
@onready var login: Button = $Panel/VBoxContainer/Login
@onready var signup: Button = $Panel/VBoxContainer/Signup
@onready var google: TextureButton = $Panel/VBoxContainer/HBoxContainer/Google

# This assumes you have the GodotFirebase plugin set up as an autoload singleton named "Firebase".
# If you named it something else, change "Firebase" to your autoload name.
func _ready() -> void:
	# Connect to the signals from the new FirebaseAuth script.
	# Note the signal names are slightly different (e.g., "login_succeeded" instead of "login_success").
	pass
	status.text = "Please log in or sign up."
# --- Button Press Handlers ---

func _on_login_pressed() -> void:
	var user_email = email.text
	var user_password = password.text

	if user_email.is_empty() or user_password.is_empty():
		status.text = "Email and password cannot be empty."
		return
		
	status.text = "Logging in..."

func _on_signup_pressed() -> void:
	var user_email = email.text
	var user_password = password.text

	if user_email.is_empty() or user_password.is_empty():
		status.text = "Email and password cannot be empty."
		return

	status.text = "Creating account..."

func _on_google_pressed() -> void:
	# ** THIS IS THE NEW WAY TO SIGN IN WITH GOOGLE **
	# This function starts the OAuth process. It will open a browser window
	# for the user to sign in and then listen for the response automatically.
	status.text = "Waiting for Google Sign-In..."
# --- Firebase Signal Handlers ---

func _on_login_succeeded(auth_result) -> void:
	# This single function now handles ALL successful logins:
	# - Email/Password
	# - Anonymous
	# - Google Sign-In (and other OAuth providers)
	if GameManager.debug_mode:
		print("Login successful! User data: ", auth_result)
	status.text = "Welcome"
	
	get_tree().change_scene_to_file("res://MainScenes/start_menu.tscn")
func _on_login_failed(code: String, message: String) -> void:
	# This function handles all failed login attempts, including Google Sign-In.
	if GameManager.debug_mode:
		print("Login failed! Error: %s - %s" % [code, message])
	status.text = "Login failed: %s" % message
func _on_signup_succeeded(auth_result: Dictionary) -> void:
	# This function is called when a new account is created successfully.
	if GameManager.debug_mode:
		print("Signup successful! User data: ", auth_result)
	status.text = "Account created successfully! You can now log in."
func _on_signup_failed(code: String, message: String) -> void:
	# This function is called if the account creation fails.
	if GameManager.debug_mode:
		print("Signup failed! Error: %s - %s" % [code, message])
	status.text = "Signup failed: %s" % message
