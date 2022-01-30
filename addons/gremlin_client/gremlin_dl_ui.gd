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

tool
extends VBoxContainer

var http_request

var gdunzip = preload('res://addons/gremlin_client/vendor/gdunzip/gdunzip.gd').new()
var godobuf_parser = preload('res://addons/gremlin_client/vendor/godobuf/parser.gd').new()

# Called when the node enters the scene tree for the first time.
func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_download")

func _on_CompileButton_pressed():
	# Pre-flight checks
	var dir = Directory.new()
	var outdir = $HBoxContainer2/OutputEdit.text
	if dir.open(outdir) != OK:
		show_dialog("Error", "Cannot write to output directory! Does it exist and have the correct permissions?")
		return
	elif !"http" in $HBoxContainer/ServerEdit.text: 
		show_dialog("Error", "You must specify the full URI! e.g., http:// or https://")
		return
	elif !$HBoxContainer2/OutputEdit.text:
		show_dialog("Error", "You must select a directory for output!")
		return
	var http_path = $HBoxContainer/ServerEdit.text
	download_zip(http_path)

func _on_OutputButton_pressed():
	var dialog = $FileDialog
	center_dialog(dialog)
	dialog.popup()

func _on_http_request_completed(result, response_code, headers, body):
	show_dialog("Success", "Connection established!")

func _on_FileDialog_dir_selected(dir):
	$"HBoxContainer2/OutputEdit".text = dir

func show_dialog(title: String, msg: String):
	var dialog = $ServerDialog
	center_dialog(dialog)
	dialog.window_title = title
	dialog.dialog_text = msg
	dialog.popup()
	
func center_dialog(dialog: Node):
	var posX
	var posY
	if get_viewport().size.x <= dialog.get_rect().size.x:
		posX = 0
	else:
		posX = (get_viewport().size.x - dialog.get_rect().size.x) / 2
	if get_viewport().size.y <= dialog.get_rect().size.y:
		posY = 0
	else:
		posY = (get_viewport().size.y - dialog.get_rect().size.y) / 2
	dialog.set_position(Vector2(posX, posY))
	
func compile_protos(directory: String, devmode: bool):
	# Search a given directory for protobuf files
	# compile them into GDScript and delete them
	var protofiles = get_protofiles_in_dir(directory)
	var godobuf_core = "res://addons/gremlin_client/vendor/godobuf/protobuf_core.gd"
	for input_file in protofiles:
		var output_dir = $HBoxContainer2/OutputEdit.text
		var output_file = output_dir + "/" + output_name(input_file)
		print("Output dir is " + output_dir)
		print("Input file is " + input_file)
		print("Output file is " + output_file)
		godobuf_parser.work(output_dir + "/", input_file, output_file, godobuf_core)
		# Delete the proto files unless we're in dev mode
		if !devmode:
			# delete the proto file
			var dir = Directory.new()
			dir.remove(output_dir + "/" + input_file)
	show_dialog("Success", "Successfully compiled library!")

func output_name(input_name: String) -> String:
	var n = input_name.rsplit(".",false)
	return n[0]+"_pb.gd"

func get_protofiles_in_dir(directory: String) -> Array:
	var protos = []
	var dir = Directory.new()
	if dir.open(directory) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if ".proto" in file_name:
				protos.append(file_name)
			file_name = dir.get_next()
	return protos

func download_zip(address: String):
	var error = http_request.request(address)
	if error != OK:
		http_request.cancel_request()
		show_dialog("Error", "Connection could not be established")

func _on_download(result, response_code, headers, body):
	if response_code == 200:	
		gdunzip.buffer = body
		gdunzip.buffer_size = body.size() 
		gdunzip._get_files()
		var count = 0
		for file in gdunzip.files:
			print("Extracting " + file)
			var outdir = $HBoxContainer2/OutputEdit.text
			var outfile = File.new()
			var error = outfile.open(outdir + "/" + file, File.WRITE)
			var b = gdunzip.uncompress(file)
			outfile.store_buffer(b)
			outfile.close()
			count += 1
		print("Successfully extracted " + str(count) + " files!")
	else:
		show_dialog("Error", "Couldn't download file! HTTP Response code: " + str(response_code))
	compile_protos($HBoxContainer2/OutputEdit.text, $HBoxContainer4/DevMode.pressed)
