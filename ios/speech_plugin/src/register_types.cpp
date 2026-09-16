// GDExtension entry point. Registers the LittleBuddySpeech class and
// exposes a single instance as an Engine singleton named "LittleBuddySpeech"
// so game/scripts/speech/ios_speech_backend.gd can find it via
// Engine.has_singleton("LittleBuddySpeech").
//
// STATUS: compiled and link-verified for iOS arm64 (device) and macOS arm64
// (editor-load only) — see ios/speech_plugin/README.md for the full history
// and this round's runtime fixes.

#include "register_types.h"
#include "little_buddy_speech.h"

#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/engine.hpp>

using namespace godot;
using namespace little_buddy;

static LittleBuddySpeech *little_buddy_speech_singleton = nullptr;

void initialize_little_buddy_speech_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	ClassDB::register_class<LittleBuddySpeech>();

	little_buddy_speech_singleton = memnew(LittleBuddySpeech);
	Engine::get_singleton()->register_singleton("LittleBuddySpeech", little_buddy_speech_singleton);
}

void uninitialize_little_buddy_speech_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	if (little_buddy_speech_singleton != nullptr) {
		Engine::get_singleton()->unregister_singleton("LittleBuddySpeech");
		memdelete(little_buddy_speech_singleton);
		little_buddy_speech_singleton = nullptr;
	}
}

extern "C" {
// GDExtension C entry symbol referenced by littlebuddyspeech.gdextension's
// `entry_symbol`.
GDExtensionBool GDE_EXPORT little_buddy_speech_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_little_buddy_speech_module);
	init_obj.register_terminator(uninitialize_little_buddy_speech_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
