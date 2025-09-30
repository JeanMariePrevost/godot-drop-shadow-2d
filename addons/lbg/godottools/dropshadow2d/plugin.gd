@tool
extends EditorPlugin

var node_icon


func _enter_tree():
    node_icon = load("res://addons/lbg/godottools/dropshadow2d/drop_shadow_2d_node_icon.svg")
    add_custom_type("DropShadow2D", "Node2D", preload("drop_shadow_2d.gd"), node_icon)


func _exit_tree():
    remove_custom_type("DropShadow2D")
