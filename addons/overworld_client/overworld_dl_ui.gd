# MIT License
# 
# Copyright (c) 2022 Lincoln Bryant
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

@tool
extends VBoxContainer

var godobuf_parser = preload('res://addons/overworld_client/vendor/godobuf/parser.gd').new()

var manifest = []

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

###############################################################################
###  Signal Handlers                                                        ###
###############################################################################

func _on_http_request_request_completed(result, response_code, headers, body):
	var outdir = $OContainer/OutputDir.text
	if manifest.is_empty():
		if response_code == 200:
				var json = JSON.new()
				json.parse(body.get_string_from_utf8())
				manifest = json.get_data()
				print("Downloaded manifest: " + str(manifest))
		else:
			print("[Error[] Couldn't download file. Response code: " + str(response_code))
	else:
		# Must be downloading a proto file or library, write it to disk in the specified dir
		if response_code == 200:
			# Filename - a bit brittle. Check the content header from the webserver
			var file= headers[0].split("=",false,2)[1]
			var content = body
			var outfile = FileAccess.new()
			var error = outfile.open(outdir + "/" + file, FileAccess.WRITE)
			outfile.store_buffer(content)
			outfile.close()
		else:
			print("[Error[] Couldn't download file. Response code: " + str(response_code))


func _on_output_button_pressed():
	var dialog = $FileDialog
	center_dialog(dialog)
	dialog.popup()


func _on_file_dialog_dir_selected(dir):
	$OContainer/OutputDir.text = dir


func _on_compile_button_pressed():
	# Pre-flight checks
	if DirAccess.open($OContainer/OutputDir.text) == null:
		show_dialog("Error", "Cannot write to output directory! Does it exist and have the correct permissions?")
		return
	elif !"http" in $ServerAddress.text: 
		show_dialog("Error", "You must specify the full URI! e.g., http:// or https://")
		return
	elif $OContainer/OutputDir.text == "":
		show_dialog("Error", "You must select a directory for output!")
		return
	var http_path = $ServerAddress.text + "/client/manifest"
	# Cancel any current request
	print("Aborting in-flight requests and connecting to " + $ServerAddress.text + "...")
	$HttpRequest.cancel_request()
	manifest = []
	await download_manifest(http_path)
	print("Finished manifest. Downloading items..")
	await download_items(manifest)
	compile_protos($OContainer/OutputDir.text, $SaveProtos.is_pressed())
	

			
###############################################################################
###  Download Functions                                                     ###
###############################################################################

func get_protofiles_in_dir(directory: String) -> Array:
	var protos = []
	var dir = DirAccess.open(directory)
	if dir:
		dir.list_dir_begin() # TODOGODOT4 fill missing arguments https://github.com/godotengine/godot/pull/40547
		var file_name = dir.get_next()
		while file_name != "":
			if ".proto" in file_name:
				protos.append(file_name)
			file_name = dir.get_next()
	return protos


func download_items(manifest):
	var address = $ServerAddress.text
	for item in manifest:
		print("Downloading " + item)
		$HttpRequest.request(address + "/client/manifest?file=" + item)
		await $HttpRequest.request_completed


func download_manifest(address: String):
	if manifest == []: 
		# Download the manifest
		$HttpRequest.request(address)
		await $HttpRequest.request_completed

###############################################################################
###  Compilation Functions                                                  ###
###############################################################################

func compile_protos(directory: String, devmode: bool):
	# Search a given directory for protobuf files
	# compile them into GDScript and delete them
	var protofiles = get_protofiles_in_dir(directory)
	var godobuf_core = "res://addons/overworld_client/vendor/godobuf/protobuf_core.gd"
	var outdir = $OContainer/OutputDir.text
	for input_file in protofiles:
		var output_file = outdir + "/" + output_name(input_file)
		print("Output dir is " + outdir)
		print("Input file is " + input_file)
		print("Output file is " + output_file)
		print(godobuf_parser)
		godobuf_parser.work(outdir + "/", input_file, output_file, godobuf_core)
		# Delete the proto files unless we're in dev mode
		if !devmode:
			# delete the proto file
			var dir = DirAccess.open(outdir)
			if dir:
				dir.remove(outdir + "/" + input_file)
	show_dialog("Success", "Successfully compiled library!")


###############################################################################
###  Dialog Functions                                                       ###
###############################################################################

func show_dialog(title: String, msg: String):
	var dialog = $AcceptDialog
	center_dialog(dialog)
	dialog.title = title
	dialog.dialog_text = msg
	dialog.popup()


func center_dialog(dialog: Node):
	var posX = (get_viewport().size.x - dialog.size.x) / 2
	var posY = (get_viewport().size.y - dialog.size.y) / 2
	dialog.set_position(Vector2(posX, posY))

func output_name(input_name: String) -> String:
	var n = input_name.rsplit(".",false)
	return n[0]+"_pb.gd"
