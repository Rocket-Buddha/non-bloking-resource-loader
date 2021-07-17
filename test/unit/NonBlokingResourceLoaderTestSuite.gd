extends "res://addons/gut/test.gd"

const LOADER_SCENE = preload("res://src/resorces/scenes/non_bloking_resource_loader.tscn")

func before_all():
	gut.p("Runs once before all tests")

func before_each():
	gut.p("Runs before each test.")

func after_each():
	gut.p("Runs after each test.")

func after_all():
	gut.p("Runs once after all tests")

func test_assert_eq_number_not_equal():
	var loader = LOADER_SCENE.instance()
	#partial.add_resources_to_interactive_loading(["res://src/resorces/scenes/non_bloking_resource_loader.tscn"])
	#OS.delay_msec(10000)
	#gut.p("ACA!")
	#partial.shutdown()
	
	assert_eq(1, 1, "Should fail.  1 != 2")

func test_assert_eq_number_equal():
	assert_eq('asdf', 'asdf', "Should pass")
