// LittleBuddySpeech implementation (Objective-C++).
//
// STATUS: compiled and link-verified for iOS arm64 (device). Also compiles
// for macOS arm64 so the GDExtension can load inside the macOS Godot editor
// -- Godot's GDExtensionManager must successfully open a library for the
// editor's own running OS/arch before its iOS export artifacts are picked
// up by the exporter at all (see ios/speech_plugin/README.md "Why a macOS
// build").
//
// AVAudioSession is an iOS/tvOS/watchOS-only API (TARGET_OS_IPHONE) -- macOS
// (TARGET_OS_OSX) has no such class, so every AVAudioSession call below is
// guarded. On macOS, microphone permission is instead checked/requested via
// AVCaptureDevice, and AVAudioEngine does not require an explicit session
// category/activation step the way it does on iOS.
//
// Privacy: on-device recognition only (requiresOnDeviceRecognition = YES),
// no disk writes of audio, no network calls. This holds on both platforms.
//
// RUNTIME FIX ROUND (this pass) -- root causes addressed, see README.md
// "Runtime fixes" for the full write-up:
//   1. AVAudioSession category changed from the speech-app-only
//      `.record`/`.measurement`/`DuckOthers` combo (correct for an app whose
//      *only* job is speech recognition) to `.playAndRecord` +
//      `.measurement` + `DefaultToSpeaker|AllowBluetooth|MixWithOthers`.
//      Little Buddy is a game with its own concurrently-running Godot audio
//      output (TTS prompts, sound effects); `.record` is an input-only,
//      exclusive category that can silence/interrupt whatever audio
//      unit/graph Godot's own iOS audio driver already has running on the
//      shared `AVAudioSession`, which was flagged as the single most likely
//      cause of speech never working end-to-end on-device. `_finishListening`
//      also no longer calls `setActive:NO` on every stop -- deactivating the
//      shared session while Godot's own audio engine may still be actively
//      rendering through it risks tearing down/interrupting Godot's audio
//      graph. We now just stop our own local tap/engine and leave the
//      session active; the category change to `.playAndRecord` is a superset
//      of typical ambient/playback categories, so it does not regress
//      Godot's own subsequent audio.
//   2. `listening_stopped` was previously only emitted on a manual
//      `stop_listening()` call -- NOT on a final recognition result or an
//      error. That left the GDScript-side `is_listening()` cache
//      permanently `true` and any "I'm listening..." UI permanently shown
//      after the very first successful/failed recognition. `_finishListening`
//      is now the single place that emits `listening_stopped`, and every
//      exit path (final result, error, timeout, manual stop) funnels
//      through it exactly once.
//   3. No auto-stop timeout existed at all -- if the recognizer never
//      produced a final result (e.g. silence, ambiguous audio), listening
//      stayed open indefinitely. A ~5s cancellable dispatch timeout was
//      added; on fire, the best-effort last partial transcript (partial
//      results are now enabled) is used if present, otherwise
//      `recognition_failed("timeout")` is reported.
//   4. Permission/result callbacks arriving off the main thread now marshal
//      into Godot via `Object::call_deferred("emit_signal", ...)` (see the
//      `_emit_*` methods below) rather than calling `emit_signal` directly,
//      per Godot's documented pattern for GDExtension callbacks originating
//      outside the engine's own call stack.
//   5. `hasPermission`/`requestPermission` now prefer the modern
//      `AVAudioApplication` record-permission API on iOS 17+, falling back
//      to the deprecated-but-functional `AVAudioSession` API on iOS
//      15/16 (this project's minimum deployment target is iOS 15).
//   6. A defensive guard was added against a zero/invalid input format
//      (`sampleRate <= 0`), which some devices can report if queried before
//      the audio session has fully settled.
//
// DELIBERATE NON-CHANGE (see README.md "On-device only, by design, always"):
// `requiresOnDeviceRecognition` remains hard-forced to `YES` and `isAvailable`
// still gates on `supportsOnDeviceRecognition`. The task brief that prompted
// this round suggested falling back to Apple's server-based recognition when
// on-device recognition is unavailable ("still work rather than refusing").
// This repository's own CLAUDE.md declares, as a hard, non-negotiable
// project rule: "No network dependency" and "no persisted/uploaded child
// microphone audio". Enabling server-based recognition would upload the
// child's voice audio to Apple's servers over the network -- that directly
// contradicts both rules. Touch-only gameplay already fully satisfies "the
// child getting nothing is worse than refusing": feeding never depends on
// speech succeeding. So this plugin keeps the strict on-device-only
// contract and simply reports `unavailable`/`recognition_failed` honestly
// when on-device recognition genuinely is not supported, instead of
// silently uploading audio to make speech "work".

#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <TargetConditionals.h>

#include "little_buddy_speech.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace little_buddy;
using namespace godot;

// ---------------------------------------------------------------------
// Objective-C controller: owns SFSpeechRecognizer + AVAudioEngine and
// forwards results to the C++ GDExtension object via a raw pointer.
// ---------------------------------------------------------------------
// How long to listen for a final result before giving up and either
// reporting the best-effort partial transcript we already have, or
// `recognition_failed("timeout")`. Keeps the "I'm listening..." UI from
// ever getting stuck open indefinitely (see required behaviour #4).
static const NSTimeInterval kListenTimeoutSeconds = 5.0;

@interface LBSpeechController : NSObject <SFSpeechRecognizerDelegate>

@property(nonatomic, assign) LittleBuddySpeech *owner; // not retained
@property(nonatomic, strong) SFSpeechRecognizer *recognizer;
@property(nonatomic, strong) AVAudioEngine *audioEngine;
@property(nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *request;
@property(nonatomic, strong) SFSpeechRecognitionTask *task;
@property(nonatomic, assign) BOOL isListening;
@property(nonatomic, copy) NSString *localeIdentifier;
// Best-effort transcript captured from interim (non-final) results, used
// only if the ~5s timeout fires before a final result ever arrives.
// Never written to disk -- kept in memory only, like every other buffer
// in this file, and cleared on every teardown.
@property(nonatomic, copy) NSString *lastPartialTranscript;
// Cancellable ~5s auto-stop timeout; created per start_listening() call,
// cancelled/cleared in _finishListening so it never fires after a
// final result or a manual stop has already torn things down.
@property(nonatomic, strong) dispatch_block_t timeoutBlock;

- (instancetype)initWithOwner:(LittleBuddySpeech *)owner;
- (BOOL)isAvailable;
- (BOOL)hasPermission;
- (void)requestPermission;
- (void)startListeningWithLocale:(NSString *)locale;
- (void)stopListening;

@end

@implementation LBSpeechController

- (instancetype)initWithOwner:(LittleBuddySpeech *)owner {
	self = [super init];
	if (self) {
		_owner = owner;
		_localeIdentifier = @"en-US";
		_recognizer = [[SFSpeechRecognizer alloc]
				initWithLocale:[NSLocale localeWithLocaleIdentifier:_localeIdentifier]];
		_recognizer.delegate = self;
		_isListening = NO;
	}
	return self;
}

- (BOOL)isAvailable {
	if (self.recognizer == nil) {
		return NO;
	}
	if (!self.recognizer.isAvailable) {
		return NO;
	}
	// Never silently fall back to server-based recognition: if on-device
	// recognition is not supported for this locale, report unavailable.
	if (@available(iOS 13.0, macOS 10.15, *)) {
		return self.recognizer.supportsOnDeviceRecognition;
	}
	return NO;
}

- (BOOL)hasPermission {
	BOOL speechAuthorized =
			[SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusAuthorized;
	BOOL micAuthorized = NO;
#if TARGET_OS_IPHONE
	// AVAudioSession's recordPermission is deprecated in favor of
	// AVAudioApplication starting iOS 17, but this project's minimum
	// deployment target is iOS 15 (see export_presets.cfg), so both paths
	// must exist. AVAudioApplication is part of the AVFAudio umbrella,
	// already pulled in transitively by <AVFoundation/AVFoundation.h>.
	if (@available(iOS 17.0, *)) {
		micAuthorized = [AVAudioApplication sharedInstance].recordPermission ==
				AVAudioApplicationRecordPermissionGranted;
	} else {
		micAuthorized =
				[[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted;
	}
#else
	// macOS has no AVAudioSession; microphone permission lives on
	// AVCaptureDevice instead. This macOS build exists purely so the
	// GDExtension loads inside the macOS editor (for iOS export pickup and
	// in-editor testing) -- the shipping/child-facing path is iOS.
	micAuthorized =
			[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized;
#endif
	return speechAuthorized && micAuthorized;
}

- (void)requestPermission {
	__weak LBSpeechController *weakSelf = self;
	[SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
		BOOL speechGranted = (status == SFSpeechRecognizerAuthorizationStatusAuthorized);
		// `SFSpeechRecognizer.requestAuthorization`, `AVAudioApplication`'s
		// and `AVAudioSession`'s completion handlers are all documented as
		// "may be called on an arbitrary queue, not guaranteed to be main".
		// `LittleBuddySpeech::_emit_permission_result` marshals into Godot
		// via `call_deferred`, which is documented safe to invoke from any
		// thread, so no extra dispatch_async hop is needed here.
		void (^handleMicResult)(BOOL) = ^(BOOL micGranted) {
			__strong LBSpeechController *strongSelf = weakSelf;
			if (strongSelf == nil || strongSelf.owner == nullptr) {
				return;
			}
			strongSelf.owner->_emit_permission_result(speechGranted && micGranted);
		};
#if TARGET_OS_IPHONE
		if (@available(iOS 17.0, *)) {
			// NOTE: requestRecordPermissionWithCompletionHandler: is a CLASS
			// method on AVAudioApplication (unlike `recordPermission`, which
			// is read off the `sharedInstance`) -- confirmed against the
			// AVAudioApplication.h header shipped in this SDK.
			[AVAudioApplication requestRecordPermissionWithCompletionHandler:handleMicResult];
		} else {
			[[AVAudioSession sharedInstance] requestRecordPermission:handleMicResult];
		}
#else
		[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:handleMicResult];
#endif
	}];
}

- (void)startListeningWithLocale:(NSString *)locale {
	if (self.isListening) {
		return;
	}

	if (locale != nil && ![locale isEqualToString:self.localeIdentifier]) {
		self.localeIdentifier = locale;
		self.recognizer = [[SFSpeechRecognizer alloc]
				initWithLocale:[NSLocale localeWithLocaleIdentifier:locale]];
		self.recognizer.delegate = self;
	}

	if (![self isAvailable] || ![self hasPermission]) {
		if (self.owner != nullptr) {
			self.owner->_emit_recognition_failed(String("unavailable"));
		}
		return;
	}

#if TARGET_OS_IPHONE
	// macOS has no AVAudioSession -- AVAudioEngine talks to the default
	// input device directly there, so this whole category/activation step
	// is iOS/tvOS/watchOS-only.
	//
	// Category is `.playAndRecord`, NOT `.record`. `.record` is input-only
	// and exclusive -- it can silence or interrupt whatever audio Godot's
	// own iOS audio driver already has playing (background music, TTS
	// prompts) through the *same* shared AVAudioSession, which was flagged
	// as the most likely reason speech never worked at runtime. `.measurement`
	// mode is kept for on-device recognition accuracy (minimal system audio
	// processing), and `DefaultToSpeaker` keeps game audio routed to the
	// speaker rather than the receiver while the mic is in use.
	// `MixWithOthers` avoids forcing an exclusive activation that could
	// interrupt Godot's own concurrently-active audio graph.
	NSError *sessionError = nil;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setCategory:AVAudioSessionCategoryPlayAndRecord
				   mode:AVAudioSessionModeMeasurement
				options:AVAudioSessionCategoryOptionDefaultToSpeaker |
						AVAudioSessionCategoryOptionAllowBluetoothHFP |
						AVAudioSessionCategoryOptionMixWithOthers
				  error:&sessionError];
	if (sessionError == nil) {
		[session setActive:YES
				withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
					  error:&sessionError];
	}
	if (sessionError != nil) {
		if (self.owner != nullptr) {
			self.owner->_emit_recognition_failed(String("audio_session_error"));
		}
		return;
	}
#endif

	self.request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
	// Partial results are used only to capture a best-effort transcript for
	// the ~5s timeout path below; the `recognized` signal itself only ever
	// fires with a final result or the last partial captured at timeout,
	// matching the "final transcript" contract in docs/INTEGRATION_CONTRACT.md.
	self.request.shouldReportPartialResults = YES;
	// Hard privacy requirement: never send audio off-device. Deliberately
	// not relaxed even when on-device recognition is unsupported for the
	// current locale/device -- see the file-level comment above
	// ("DELIBERATE NON-CHANGE").
	if (@available(iOS 13.0, macOS 10.15, *)) {
		self.request.requiresOnDeviceRecognition = YES;
	}

	self.audioEngine = [[AVAudioEngine alloc] init];
	AVAudioInputNode *inputNode = self.audioEngine.inputNode;
	AVAudioFormat *recordingFormat = [inputNode outputFormatForBus:0];
	// Defensive guard: some devices/states can report a zero-rate/zero-channel
	// format if queried before the audio session has fully settled. Installing
	// a tap with such a format can misbehave or crash AVAudioEngine.
	if (recordingFormat == nil || recordingFormat.sampleRate <= 0.0 || recordingFormat.channelCount == 0) {
		if (self.owner != nullptr) {
			self.owner->_emit_recognition_failed(String("audio_format_error"));
		}
		return;
	}

	__weak LBSpeechController *weakSelf = self;
	[inputNode installTapOnBus:0
					 bufferSize:1024
						 format:recordingFormat
						  block:^(AVAudioPCMBuffer *_Nonnull buffer, AVAudioTime *_Nonnull when) {
							// Streamed straight into the recognition request;
							// never written to disk.
							__strong LBSpeechController *strongSelf = weakSelf;
							if (strongSelf != nil && strongSelf.request != nil) {
								[strongSelf.request appendAudioPCMBuffer:buffer];
							}
						  }];

	[self.audioEngine prepare];
	NSError *startError = nil;
	[self.audioEngine startAndReturnError:&startError];
	if (startError != nil) {
		[inputNode removeTapOnBus:0];
		if (self.owner != nullptr) {
			self.owner->_emit_recognition_failed(String("audio_engine_error"));
		}
		return;
	}

	self.isListening = YES;
	self.lastPartialTranscript = nil;
	if (self.owner != nullptr) {
		self.owner->_emit_listening_started();
	}

	// ~5s auto-stop safety net (required behaviour #4): cancelled in
	// _finishListening the moment a final result, error, or manual stop
	// gets there first.
	__weak LBSpeechController *weakSelfForTimeout = self;
	self.timeoutBlock = dispatch_block_create((dispatch_block_flags_t)0, ^{
	  __strong LBSpeechController *strongSelf = weakSelfForTimeout;
	  if (strongSelf == nil || !strongSelf.isListening) {
		  return;
	  }
	  [strongSelf _onListenTimeout];
	});
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kListenTimeoutSeconds * NSEC_PER_SEC)),
			dispatch_get_main_queue(), self.timeoutBlock);

	self.task = [self.recognizer
			recognitionTaskWithRequest:self.request
							 resultHandler:^(SFSpeechRecognitionResult *_Nullable result, NSError *_Nullable error) {
							   __strong LBSpeechController *strongSelf = weakSelf;
							   if (strongSelf == nil) {
								   return;
							   }
							   if (error != nil) {
								   dispatch_async(dispatch_get_main_queue(), ^{
									 [strongSelf _finishListening];
									 if (strongSelf.owner != nullptr) {
										 strongSelf.owner->_emit_recognition_failed(String("recognition_error"));
									 }
								   });
								   return;
							   }
							   if (result == nil) {
								   return;
							   }
							   NSString *transcript = result.bestTranscription.formattedString;
							   if (!result.isFinal) {
								   // Interim result: remember it as a fallback
								   // for the timeout path only. Never emitted
								   // as `recognized` on its own.
								   dispatch_async(dispatch_get_main_queue(), ^{
									 strongSelf.lastPartialTranscript = transcript;
								   });
								   return;
							   }
							   dispatch_async(dispatch_get_main_queue(), ^{
								 [strongSelf _finishListening];
								 if (strongSelf.owner != nullptr) {
									 strongSelf.owner->_emit_recognized(
											 String([transcript UTF8String]));
								 }
							   });
							 }];
}

// Fires ~5s after start_listening if no final result has arrived yet.
// Reports the best-effort partial transcript captured so far, if any,
// otherwise an honest "timeout" failure. Always tears down via
// _finishListening first, which is what actually emits `listening_stopped`.
- (void)_onListenTimeout {
	NSString *transcript = self.lastPartialTranscript;
	[self _finishListening];
	if (self.owner == nullptr) {
		return;
	}
	if (transcript != nil && transcript.length > 0) {
		self.owner->_emit_recognized(String([transcript UTF8String]));
	} else {
		self.owner->_emit_recognition_failed(String("timeout"));
	}
}

- (void)stopListening {
	if (!self.isListening) {
		return;
	}
	[self _finishListening];
}

// Internal teardown shared by every exit path: final result, error,
// ~5s timeout, and manual stop_listening(). This is the SINGLE place that
// emits `listening_stopped` (guarded by `wasListening` so it only fires
// once per listening session) -- previously `listening_stopped` was only
// emitted from the manual-stop path, which left GDScript's `is_listening()`
// cache and any "I'm listening..." UI permanently stuck on after a
// successful or failed recognition. Always tears down the audio tap/engine
// and cancels the auto-stop timeout so nothing keeps streaming, firing, or
// getting retained after this returns.
- (void)_finishListening {
	BOOL wasListening = self.isListening;

	if (self.timeoutBlock != nil) {
		dispatch_block_cancel(self.timeoutBlock);
		self.timeoutBlock = nil;
	}
	if (self.audioEngine != nil) {
		[self.audioEngine.inputNode removeTapOnBus:0];
		[self.audioEngine stop];
	}
	[self.request endAudio];
	[self.task cancel];
	self.request = nil;
	self.task = nil;
	self.lastPartialTranscript = nil;
	self.isListening = NO;
	// Deliberately NOT calling `[[AVAudioSession sharedInstance] setActive:NO
	// ...]` here. Little Buddy's game audio (Godot's own audio driver, TTS
	// prompts, sound effects) may still be actively rendering through this
	// same shared AVAudioSession; forcibly deactivating it after every
	// listen risks interrupting/tearing down Godot's own audio graph. We
	// only stop *our own* local engine/tap above -- the shared session stays
	// in the `.playAndRecord` category set in startListeningWithLocale,
	// which is a superset of typical playback-only categories and does not
	// regress subsequent game audio.
	if (wasListening && self.owner != nullptr) {
		self.owner->_emit_listening_stopped();
	}
}

@end

// ---------------------------------------------------------------------
// GDExtension-facing C++ class.
// ---------------------------------------------------------------------

LittleBuddySpeech::LittleBuddySpeech() {
	controller = [[LBSpeechController alloc] initWithOwner:this];
}

LittleBuddySpeech::~LittleBuddySpeech() {
	if (controller != nullptr) {
		[controller stopListening];
		controller.owner = nullptr;
		controller = nullptr;
	}
}

void LittleBuddySpeech::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &LittleBuddySpeech::is_available);
	ClassDB::bind_method(D_METHOD("has_permission"), &LittleBuddySpeech::has_permission);
	ClassDB::bind_method(D_METHOD("request_permission"), &LittleBuddySpeech::request_permission);
	ClassDB::bind_method(
			D_METHOD("start_listening", "locale"), &LittleBuddySpeech::start_listening);
	ClassDB::bind_method(D_METHOD("stop_listening"), &LittleBuddySpeech::stop_listening);

	ADD_SIGNAL(MethodInfo("permission_result", PropertyInfo(Variant::BOOL, "granted")));
	ADD_SIGNAL(MethodInfo("recognized", PropertyInfo(Variant::STRING, "text")));
	ADD_SIGNAL(MethodInfo("recognition_failed", PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("listening_started"));
	ADD_SIGNAL(MethodInfo("listening_stopped"));
}

bool LittleBuddySpeech::is_available() const {
	return controller != nullptr && [controller isAvailable];
}

bool LittleBuddySpeech::has_permission() const {
	return controller != nullptr && [controller hasPermission];
}

void LittleBuddySpeech::request_permission() {
	if (controller != nullptr) {
		[controller requestPermission];
	} else {
		_emit_permission_result(false);
	}
}

void LittleBuddySpeech::start_listening(const String &locale) {
	if (controller == nullptr) {
		_emit_recognition_failed(String("unavailable"));
		return;
	}
	NSString *nsLocale = [NSString stringWithUTF8String:locale.utf8().get_data()];
	[controller startListeningWithLocale:nsLocale];
}

void LittleBuddySpeech::stop_listening() {
	if (controller != nullptr) {
		[controller stopListening];
	}
}

// All five _emit_* methods below marshal into Godot via `call_deferred`
// rather than calling `emit_signal` directly. They can be invoked from
// Objective-C completion handlers/blocks that Apple documents as running on
// an arbitrary (non-main) queue/thread -- e.g. SFSpeechRecognizer's
// `requestAuthorization`. `Object::call_deferred` is Godot's own documented,
// thread-safe mechanism for exactly this situation: it enqueues the call
// onto Godot's message queue instead of executing it inline on whatever
// thread happened to call it, so `emit_signal` always actually runs on
// Godot's own thread during its own frame processing.
void LittleBuddySpeech::_emit_permission_result(bool granted) {
	call_deferred("emit_signal", StringName("permission_result"), granted);
}

void LittleBuddySpeech::_emit_recognized(const String &text) {
	call_deferred("emit_signal", StringName("recognized"), text);
}

void LittleBuddySpeech::_emit_recognition_failed(const String &reason) {
	call_deferred("emit_signal", StringName("recognition_failed"), reason);
}

void LittleBuddySpeech::_emit_listening_started() {
	call_deferred("emit_signal", StringName("listening_started"));
}

void LittleBuddySpeech::_emit_listening_stopped() {
	call_deferred("emit_signal", StringName("listening_stopped"));
}
