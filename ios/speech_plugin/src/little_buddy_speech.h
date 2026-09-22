// LittleBuddySpeech — Godot 4 GDExtension singleton bridging on-device
// SFSpeechRecognizer + AVAudioEngine to the game's SpeechService.
//
// PRIVACY / OFFLINE GUARANTEES (do not weaken these when editing):
//   - requiresOnDeviceRecognition is forced to YES. If the current locale's
//     recognizer does not support on-device recognition, this class reports
//     itself unavailable rather than silently falling back to Apple's
//     server-based recognition.
//   - Audio is streamed directly from AVAudioEngine's tap buffer into the
//     SFSpeechAudioBufferRecognitionRequest in memory only. No audio buffer
//     is ever written to disk, cached, or transmitted anywhere.
//   - No network client of any kind is created by this class.
//
// STATUS: compiled and link-verified for iOS arm64 (device) and macOS
// arm64 (editor-load only, so the GDExtension resolves inside the macOS
// Godot editor -- see ios/speech_plugin/README.md "Why a macOS build").
#ifndef LITTLE_BUDDY_SPEECH_H
#define LITTLE_BUDDY_SPEECH_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/binder_common.hpp>

#ifdef __OBJC__
@class LBSpeechController;
#else
typedef void LBSpeechController;
#endif

namespace little_buddy {

class LittleBuddySpeech : public godot::Object {
	GDCLASS(LittleBuddySpeech, godot::Object)

public:
	LittleBuddySpeech();
	~LittleBuddySpeech();

	bool is_available() const;
	bool has_permission() const;
	void request_permission();
	void start_listening(const godot::String &locale);
	void stop_listening();

	// Aliz Tutor Mode (hands-free, Agent E patch 2026-09-20):
	//  * set_voice_processing(true) while a tutor session is active switches
	//    the shared AVAudioSession to the voice-chat mode (acoustic echo
	//    cancellation on the input node, DefaultToSpeaker, Bluetooth HFP) so
	//    the child can interrupt Aliz without her own voice being transcribed;
	//    set_voice_processing(false) restores the default mode. Applied to the
	//    live session at once when the microphone is open, else on the next
	//    start_listening().
	//  * get_input_level() is the smoothed RMS (0..1) of the last microphone
	//    buffers while listening, 0 otherwise -- the TutorVoiceSession's level
	//    source for its VAD and the on-screen mic indicator. A number, never
	//    audio; nothing is stored.
	void set_voice_processing(bool enabled);
	bool is_voice_processing() const;
	float get_input_level() const;
	godot::String get_audio_session_diagnostics_json() const;

	// Called by the Objective-C controller (LBSpeechController) to forward
	// results back into the Godot/GDExtension signal system. Not part of
	// the GDScript-facing API.
	void _emit_permission_result(bool granted);
	void _emit_recognized(const godot::String &text);
	void _emit_partial_result(const godot::String &text);
	void _emit_recognition_failed(const godot::String &reason);
	void _emit_listening_started();
	void _emit_listening_stopped();
	void _emit_audio_session_event(const godot::String &json);

protected:
	static void _bind_methods();

private:
	LBSpeechController *controller; // Objective-C object, opaque here.
};

} // namespace little_buddy

#endif // LITTLE_BUDDY_SPEECH_H
