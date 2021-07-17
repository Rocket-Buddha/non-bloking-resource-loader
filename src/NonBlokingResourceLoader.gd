extends Node

# warning-ignore:unused_signal
signal background_resource_loaded (resource_path)
# warning-ignore:unused_signal
signal background_resource_load_failed (resource_path)
# warning-ignore:unused_signal
signal interactive_stage_updated (completeness)
# warning-ignore:unused_signal
signal interactive_load_finished
signal shotdown
# warning-ignore:unused_signal
signal error (error_message)

const BACKGROUND_RESOURCE_LOADED_SIGNAL: String = "background_resource_loaded"
const BACKGROUND_RESOURCE_LOAD_FAILED_SIGNAL: String = "background_resource_load_failed"
const INTERACTIVE_STAGE_UPDATE_SIGNAL: String = "interactive_stage_updated"
const INTERACTIVE_LOAD_FINISHED_SIGNAL: String = "interactive_load_finished"
const LOADER_SHOTDOWN_SIGNAL: String = "shotdown"
const ERROR_SIGNAL: String = "error"

export (int, 1, 32) var thread_pool_max_size = 4

var background_scheduler_thread: Thread
var background_queue_mutex: Mutex
var background_adding_threads_references_mutex: Mutex
var background_scheduler_thread_semaphore: Semaphore
var background_queue: Array
var background_thread_pool: Array
var background_adding_threads_references: Array
var interactive_loader_thread: Thread
var interactive_loader_queue_mutex: Mutex
var interactive_loader_thread_semaphore: Semaphore
var interactive_loader_queue: Array
var interactive_loader_active_loaders: Array
var interactive_loader_current_total_stages: int
var interactive_loader_current_loaded_stages: int
var interactive_loader_current_min_stage_time: int
var ready_resources: Dictionary

var running_flag

func _init() -> void:
	running_flag = true
	interactive_loader_queue = []
	interactive_loader_active_loaders = []
	interactive_loader_current_total_stages = 0
	interactive_loader_current_loaded_stages = 0
	interactive_loader_current_min_stage_time = 100
	interactive_loader_queue_mutex = Mutex.new()
	interactive_loader_thread_semaphore = Semaphore.new()
	interactive_loader_thread = Thread.new()
	_check_return(interactive_loader_thread.start(self,
												  "_interactive_thread_process",
												  [],
												  0),
				  "There was a problem trying to start interactive_loader_thread.")
	background_thread_pool = []
	background_queue = []
	background_queue_mutex = Mutex.new()
	background_adding_threads_references_mutex = Mutex.new()
	background_scheduler_thread_semaphore = Semaphore.new()
	background_scheduler_thread = Thread.new()
	background_adding_threads_references = []
	_check_return(background_scheduler_thread.start(self,
													"_scheduler_background_thread_process",
													[],
													0),
				  "There was a problem trying to start background_scheduler_thread.")
	ready_resources = {}
# warning-ignore:unused_variable
	for i in range(thread_pool_max_size):
		background_thread_pool.append(Thread.new())

func load_resources_in_background(p_path_array: Array = []) -> int:
	var resources_to_be_added: Array = []
	for path in p_path_array:
		if path in background_queue:
			pass
		elif path in ready_resources:
			emit_signal(BACKGROUND_RESOURCE_LOADED_SIGNAL, path)
		elif ResourceLoader.has_cached(path):
			ready_resources[path] = load(path)
			emit_signal(BACKGROUND_RESOURCE_LOADED_SIGNAL, path)
		else:
			resources_to_be_added.push_back(path)
	if resources_to_be_added.size() > 0:
		var adding_thread: Thread = Thread.new()
		# Add the resource to be loaded.
		_check_return(Thread.new().start(self,
										 "_adding_thread_process",
										 [resources_to_be_added, adding_thread],
										 0),
					 "There was a problem trying to start background_adding_thread.")
	return OK

func _adding_thread_process(p_array_path: Array = [], p_thread_ref: Thread = null) -> void:
	background_adding_threads_references_mutex.lock()
	background_adding_threads_references_mutex.push_back(p_thread_ref)
	background_adding_threads_references_mutex.unlock()
	background_queue_mutex.lock()
	background_queue.append_array(p_array_path)
	background_queue_mutex.unlock()
	_check_return(background_scheduler_thread_semaphore.post(),
				  "There was a problem trying to post background_scheduler_thread_semaphore.")
	background_adding_threads_references_mutex.lock()
	background_adding_threads_references_mutex.erase(p_thread_ref)
	background_adding_threads_references_mutex.unlock()

# warning-ignore:unused_argument
func _scheduler_background_thread_process(p_data: Array = []) -> void:
	var pool_thread: Thread
	while running_flag:
		_check_return(background_scheduler_thread_semaphore.wait(),
					  "There was a problem trying to wait for background_scheduler_thread_semaphore.")
		if running_flag:
			if(background_queue.size() > 0):
				pool_thread = _get_an_inactive_thread()
				if pool_thread != null:
					background_queue_mutex.lock()
					var next: String = background_queue.pop_front()
					background_queue_mutex.unlock()
					_check_return(pool_thread.start(self,
									  "_pool_thread_process",
									  next,
									  0), "There was a problem trying to star pool_thread.")
				else:
					break

func _pool_thread_process(p_path: String = "") -> void:
	if(p_path != ""):
		ready_resources[p_path] = load(p_path)
		if (ready_resources[p_path] != null):
			emit_signal(BACKGROUND_RESOURCE_LOADED_SIGNAL, p_path)
		else:
			emit_signal(BACKGROUND_RESOURCE_LOAD_FAILED_SIGNAL, p_path)
		_check_return(background_scheduler_thread_semaphore.post(),
					  "There was a problem trying to post background_scheduler_thread_semaphore.")

func get_resource(p_path: String = "") -> Resource:
	if(ready_resources.has(p_path)):
		var resource: Resource = ready_resources[p_path]
		_check_return(ready_resources.erase(p_path),
					  "There was a problem trying to remove the path: " + p_path + "from ready resources collection.")
		return resource
	return null

func _get_an_inactive_thread() -> Thread:
	for thread in background_thread_pool:
		if not thread.is_active():
			return thread
	return null

# warning-ignore:unused_argument
func _interactive_thread_process(p_data: Array = []) -> void:
	_check_return(interactive_loader_thread_semaphore.wait(),
				  "There was a problem trying to wait for interactive_loader_thread_semaphore.")
	if running_flag:
		emit_signal(INTERACTIVE_STAGE_UPDATE_SIGNAL, 0.0)
		while running_flag:
			if interactive_loader_active_loaders.size() > 0:
				for interactive_loader in interactive_loader_active_loaders:
	# warning-ignore:unused_variable
					for poll_number in range(interactive_loader.get_stage_count()):
						var ret: int = interactive_loader.poll()
						if (ret == ERR_FILE_EOF || ret != OK):
								ready_resources[interactive_loader.get_meta("path")] = interactive_loader.get_resource()
								interactive_loader_active_loaders.erase(interactive_loader)
						_interactive_update_stage()
			else:
				emit_signal(INTERACTIVE_LOAD_FINISHED_SIGNAL)
				interactive_loader_current_loaded_stages = 0
				interactive_loader_current_total_stages = 0
				_check_return(interactive_loader_thread_semaphore.wait(),
							  "There was a problem trying to wait for interactive_loader_thread_semaphore.")

func _interactive_update_stage() -> void:
	interactive_loader_current_loaded_stages += 1
	OS.delay_msec(interactive_loader_current_min_stage_time)
	emit_signal(INTERACTIVE_STAGE_UPDATE_SIGNAL, _get_total_progress())

func add_resources_to_interactive_loading(p_path_array: Array = []) -> int:
	# Take the mutex yo avoid concurrent adds.
	# Or adds until loading. 
	interactive_loader_queue_mutex.lock()
	for path in p_path_array:
		# Check If the current resource is in:
		#   - The list to load.
		#   - Ready.
		if (path in interactive_loader_queue
			or path in ready_resources):
			pass
		elif ResourceLoader.has_cached(path):
			ready_resources[path] = load(path)
		else:
			# Add the resource to be loaded.
			interactive_loader_queue.push_back(path)
			# Release the Mutex.
	interactive_loader_queue_mutex.unlock()
	return OK

func start_interactive_loading(p_min_stage_time: int = 100) -> void:
	interactive_loader_current_min_stage_time = p_min_stage_time
	interactive_loader_queue_mutex.lock()
	if interactive_loader_queue.size() > 0:
		for path in interactive_loader_queue:
			var irl: ResourceInteractiveLoader = ResourceLoader.load_interactive(path)
			irl.set_meta("path", path)
			interactive_loader_current_total_stages += irl.get_stage_count()
			interactive_loader_active_loaders.push_back(irl)
		_check_return(interactive_loader_thread_semaphore.post(),
					  "There was a problem trying to post interactive_loader_thread_semaphore.")
		interactive_loader_queue = []
	else:
		emit_signal(INTERACTIVE_STAGE_UPDATE_SIGNAL, 1.0)
		emit_signal(INTERACTIVE_LOAD_FINISHED_SIGNAL)
	interactive_loader_queue_mutex.unlock()

func _get_total_progress() -> float:
	if (interactive_loader_current_total_stages != 0):
		return float(interactive_loader_current_loaded_stages) / float(interactive_loader_current_total_stages)
	return 0.0

func _check_return(p_return: int = OK, p_error_message: String = "") -> void:
	if (p_return != OK):
		var error_message: String = p_error_message + " ERROR CODE: " + str(p_return)
		emit_signal(ERROR_SIGNAL, error_message)
		push_error(error_message)

func shutdown():
	running_flag = false
	background_scheduler_thread_semaphore.post()
	background_scheduler_thread.wait_to_finish()
	interactive_loader_thread_semaphore.post()
	interactive_loader_thread.wait_to_finish()
	for t in background_thread_pool:
		if(t.is_active()):
			t.wait_to_finish()
	background_adding_threads_references_mutex.lock()
	for t in background_adding_threads_references:
		if(t.is_active()):
			t.wait_to_finish()
	background_adding_threads_references_mutex.unlock()
	emit_signal(LOADER_SHOTDOWN_SIGNAL)

