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
// DEVICE-VERIFIED FIX ROUND (this pass) -- first real hardware run
// (iPhone 14 Pro Max) surfaced two concrete, confirmed-on-device bugs:
//   7. `listenCount: 3` but `recognizedCount: 5` / `failedCount: 3` in
//      on-device diagnostics: SFSpeechRecognitionTask routinely reports a
//      trailing NSError (e.g. kAFAssistantErrorDomain 216/1110, "no speech
//      detected") immediately AFTER delivering a perfectly good final
//      result, as the audio session/tap tears down. That trailing error was
//      overwriting a successful recognition with `recognition_failed`,
//      showing "Try again!" to a child who had just been understood. Fixed
//      via `hasReportedResult`: the instant a session emits `recognized`
//      (final result, or a best-effort partial used at the ~5s timeout), it
//      is latched, and the error branch of the result handler becomes a
//      no-op for the rest of that session -- teardown (`_finishListening`)
//      still runs exactly the same, and `listening_stopped` still fires
//      exactly once (it is idempotent/guarded by `wasListening` already).
//      The failure reason string was also upgraded from the bare
//      "recognition_error" to "recognition_error:<domain>:<code>" (e.g.
//      "recognition_error:kAFAssistantErrorDomain:216") for any *genuine*
//      failure, since on-device this string is the only telemetry
//      available -- still just a short code, never a transcript.
//   8. TTS/game audio was reported audibly quieter every time the mic
//      opened ("เสียงพูดเบาลง"). Root cause: `AVAudioSessionModeMeasurement`
//      disables system audio signal processing and can route output to the
//      receiver/earpiece instead of the speaker. Changed to
//      `AVAudioSessionModeDefault` and added an explicit
//      `overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker` call
//      right after session activation to force the active route back to
//      the speaker (in addition to the pre-existing `DefaultToSpeaker`
//      category option, which only sets the *default*, not the *active*,
//      route).
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
// Set the moment this session has already emitted a `recognized` signal
// (final result, or a best-effort partial used at timeout). SFSpeechRecognitionTask
// commonly reports a trailing NSError (e.g. kAFAssistantErrorDomain 216/1110,
// "no speech detected") immediately AFTER delivering a perfectly usable final
// result, as the audio session/tap tears down -- a known SFSpeechRecognizer
// quirk, not a real failure. Once a session has produced a transcript, that
// session is a success, full stop: this flag makes the error branch of the
// result handler a no-op instead of overwriting a good recognition with
// `recognition_failed`. Reset to NO at the top of every start_listening call.
@property(nonatomic, assign) BOOL hasReportedResult;
// Cancellable ~5s auto-stop timeout; created per start_listening() call,
// cancelled/cleared in _finishListening so it never fires after a
// final result or a manual stop has already torn things down.
@property(nonatomic, strong) dispatch_block_t timeoutBlock;
// Hands-free tutor (Agent E): voice-processing mode requested by GDScript
// while a TutorVoiceSession is active, and the smoothed input RMS (0..1) of
// the most recent tap buffers. `inputLevel` is written on the audio tap
// queue and read from Godot's thread: a single float, torn reads are
// harmless, so `atomic` is enough. Reset to 0 on every teardown.
@property(atomic, assign) BOOL voiceProcessing;
@property(atomic, assign) float inputLevel;

- (instancetype)initWithOwner:(LittleBuddySpeech *)owner;
- (void)setVoiceProcessingEnabled:(BOOL)enabled;
- (BOOL)isAvailable;
- (BOOL)hasPermission;
- (void)requestPermission;
- (void)startListeningWithLocale:(NSString *)locale;
- (void)stopListening;

@end

// Private notification handlers + shared "stop and report a reason" helper,
// used by both AVAudioSessionInterruptionNotification and
// AVAudioSessionMediaServicesWereResetNotification handling below. Declared
// in a class extension (rather than only relying on late-binding via
// @selector) so the compiler can see and check these declarations.
@interface LBSpeechController ()
#if TARGET_OS_IPHONE
- (void)_handleAudioSessionInterruption:(NSNotification *)notification;
- (void)_handleMediaServicesWereReset:(NSNotification *)notification;
#endif
- (void)_interruptListeningForReason:(NSString *)reason;
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
#if TARGET_OS_IPHONE
		// Siri, an incoming call, another app seizing the mic, CarPlay, etc.
		// all surface as AVAudioSessionInterruptionNotification, NOT as an
		// NSError delivered to the SFSpeechRecognitionTask result handler --
		// a running AVAudioEngine can simply be yanked out from under us.
		// AVAudioSessionMediaServicesWereResetNotification is the more severe
		// (rare) case where coreaudiod itself restarts and every audio object
		// tied to the old session/engine instance becomes invalid. Both are
		// only meaningful on iOS/tvOS/watchOS -- AVAudioSession does not exist
		// on macOS (see the file-level comment). Removed in `dealloc` below.
		[[NSNotificationCenter defaultCenter] addObserver:self
												  selector:@selector(_handleAudioSessionInterruption:)
													  name:AVAudioSessionInterruptionNotification
													object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												  selector:@selector(_handleMediaServicesWereReset:)
													  name:AVAudioSessionMediaServicesWereResetNotification
													object:nil];
#endif
	}
	return self;
}

- (void)dealloc {
#if TARGET_OS_IPHONE
	// Under ARC this must NOT call [super dealloc] explicitly -- ARC
	// synthesizes that call automatically. Without this removal, a
	// notification firing after this controller is freed (e.g. right after
	// -[LittleBuddySpeech dealloc] on scene teardown) would send a message to
	// a dangling `self`, which is exactly the kind of native crash this pass
	// exists to close off.
	[[NSNotificationCenter defaultCenter] removeObserver:self];
#endif
}

// Hands-free tutor: remembers the request and, when the microphone is open
// right now, re-applies the session mode in place (the input node's own
// voice processing follows on the next start, when the tap is rebuilt).
- (void)setVoiceProcessingEnabled:(BOOL)enabled {
	if (self.voiceProcessing == enabled) {
		return;
	}
	self.voiceProcessing = enabled;
#if TARGET_OS_IPHONE
	if (self.isListening) {
		NSError *modeError = nil;
		[[AVAudioSession sharedInstance] setMode:(enabled ? AVAudioSessionModeVoiceChat : AVAudioSessionModeDefault)
										   error:&modeError];
		if (modeError != nil) {
			NSLog(@"[LittleBuddySpeech] setMode(%@) failed: %@", enabled ? @"voiceChat" : @"default",
					modeError.localizedDescription);
		}
		NSError *overrideError = nil;
		[[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&overrideError];
	}
#endif
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

	// Reset the per-session "already produced a transcript" latch up front,
	// unconditionally, so a stale value from a previous session can never
	// leak into this one and (wrongly) suppress a genuine failure.
	self.hasReportedResult = NO;

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
	// as the most likely reason speech never worked at runtime.
	//
	// Mode is `.default`, NOT `.measurement`. `.measurement` disables system
	// audio signal processing AND routes output to the receiver/earpiece
	// instead of the speaker -- confirmed on-device as the cause of Little
	// Buddy's own TTS/SFX becoming noticeably quieter every time the mic
	// opened. `.default` (or `.spokenAudio`, for narration-style ducking)
	// keeps normal system processing/routing for a `.playAndRecord` session
	// while on-device recognition accuracy is unaffected in practice.
	// `DefaultToSpeaker` keeps game audio routed to the speaker rather than
	// the receiver while the mic is in use, and the explicit
	// `overrideOutputAudioPort:` call below additionally forces the *active*
	// route back to the speaker immediately after activation, since
	// `DefaultToSpeaker` alone only sets the *default* route and can still
	// be overridden by category/mode side effects. `MixWithOthers` avoids
	// forcing an exclusive activation that could interrupt Godot's own
	// concurrently-active audio graph.
	NSError *sessionError = nil;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	// Hands-free tutor: VoiceChat mode enables the platform's acoustic echo
	// canceller and voice-optimised gains, so Aliz's own line from the
	// speaker (inches from the mic) is removed before recognition sees it.
	// Off (the default) it is exactly the session the rest of the game has
	// been shipping with.
	[session setCategory:AVAudioSessionCategoryPlayAndRecord
				   mode:(self.voiceProcessing ? AVAudioSessionModeVoiceChat : AVAudioSessionModeDefault)
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
	// Belt-and-suspenders: force the active route to the speaker right after
	// activation. This is a routing hint, not a hard requirement for speech
	// recognition to function, so a failure here is logged-and-ignored rather
	// than treated as a fatal `audio_session_error` -- the child's mic input
	// still works either way, this only affects how loud the *output* (TTS/
	// SFX) is while/after the mic session is active.
	NSError *overrideError = nil;
	[session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&overrideError];
#endif

	self.request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
	// Interim hypotheses are surfaced as `partial_result` (see the result
	// handler below) and remembered as the best-effort transcript for the
	// ~5s timeout and manual-stop paths. `recognized` itself fires with a
	// final result, or with that best-effort partial when the session is
	// ended before Apple finalises -- never with an interim result on its own.
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
	// Hands-free tutor: the input node's own voice processing (AEC + AGC +
	// noise suppression) must be enabled BEFORE the tap is installed because
	// it can change the node's output format. Best effort: a failure keeps
	// the plain input and the client-side echo gate still applies.
	if (@available(iOS 13.0, macOS 10.15, *)) {
		NSError *vpError = nil;
		if (![inputNode setVoiceProcessingEnabled:self.voiceProcessing error:&vpError] && vpError != nil) {
			NSLog(@"[LittleBuddySpeech] voice processing %@ refused: %@",
					self.voiceProcessing ? @"on" : @"off", vpError.localizedDescription);
		}
	}
	self.inputLevel = 0.0f;
	AVAudioFormat *recordingFormat = [inputNode outputFormatForBus:0];
	// Defensive guard: some devices/states can report a zero-rate/zero-channel
	// format if queried before the audio session has fully settled. Installing
	// a tap with such a format can misbehave or crash AVAudioEngine.
	if (recordingFormat == nil || recordingFormat.sampleRate <= 0.0 || recordingFormat.channelCount == 0) {
		// Route through `_finishListening` (a no-op re: `listening_stopped`
		// here, since `isListening` is still NO) so the just-allocated
		// `self.request`/`self.audioEngine` are released the same single way
		// as every other exit path, instead of being silently leaked/left
		// dangling until the next start_listening() call overwrites them.
		[self _finishListening];
		if (self.owner != nullptr) {
			self.owner->_emit_recognition_failed(String("audio_format_error"));
		}
		return;
	}

	// AVAudioEngine/AVAudioInputNode do not always report trouble via
	// NSError -- installing a tap or starting the engine can raise a
	// synchronous Objective-C NSException instead, most plausibly when the
	// shared AVAudioSession/audio graph is mid-interruption or was just
	// invalidated by a media-services reset. Catch it here and funnel it
	// through the same single `_finishListening` + `recognition_failed` exit
	// path as every other failure so it cannot cross into Godot's C++/
	// GDScript call stack and crash the whole app on the child's iPad.
	__weak LBSpeechController *weakSelf = self;
	@try {
		[inputNode installTapOnBus:0
						 bufferSize:1024
							 format:recordingFormat
							  block:^(AVAudioPCMBuffer *_Nonnull buffer, AVAudioTime *_Nonnull when) {
								// Streamed straight into the recognition request;
								// never written to disk.
								__strong LBSpeechController *strongSelf = weakSelf;
								if (strongSelf != nil && strongSelf.request != nil) {
									[strongSelf.request appendAudioPCMBuffer:buffer];
									// Input meter for the VAD / indicator: RMS of channel 0,
									// smoothed 50/50 with the previous buffer. One float; the
									// samples are not kept.
									float *samples = buffer.floatChannelData != NULL ? buffer.floatChannelData[0] : NULL;
									AVAudioFrameCount frames = buffer.frameLength;
									if (samples != NULL && frames > 0) {
										double sum = 0.0;
										for (AVAudioFrameCount i = 0; i < frames; ++i) {
											sum += (double)samples[i] * (double)samples[i];
										}
										float rms = (float)sqrt(sum / (double)frames);
										if (rms > 1.0f) {
											rms = 1.0f;
										}
										strongSelf.inputLevel = 0.5f * strongSelf.inputLevel + 0.5f * rms;
									}
								}
							  }];

		[self.audioEngine prepare];
		NSError *startError = nil;
		[self.audioEngine startAndReturnError:&startError];
		if (startError != nil) {
			[self _finishListening];
			if (self.owner != nullptr) {
				self.owner->_emit_recognition_failed(String("audio_engine_error"));
			}
			return;
		}
	} @catch (NSException *exception) {
		[self _finishListening];
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
									 // A final result already reached GDScript for this
									 // session (see the property doc on hasReportedResult):
									 // SFSpeechRecognitionTask routinely reports a trailing
									 // NSError (e.g. kAFAssistantErrorDomain 216/1110, "no
									 // speech detected") right after a perfectly good final
									 // result, as the audio session/tap tears down. Treat
									 // that as teardown noise, not a failure: still run the
									 // normal teardown (idempotent -- isListening is already
									 // NO, so `listening_stopped` will not double-fire) but
									 // never let it overwrite a successful recognition with
									 // `recognition_failed`.
									 BOOL alreadySucceeded = strongSelf.hasReportedResult;
									 [strongSelf _finishListening];
									 if (strongSelf.owner != nullptr && !alreadySucceeded) {
										 // Log the real domain/code, not just a bare string --
										 // on-device this reason string is our only telemetry.
										 // Still just a short code: never the transcript/audio.
										 NSString *domain = error.domain != nil ? error.domain : @"unknown";
										 NSString *reason = [NSString
												 stringWithFormat:@"recognition_error:%@:%ld", domain,
																   (long)error.code];
										 strongSelf.owner->_emit_recognition_failed(
												 String([reason UTF8String]));
									 }
								   });
								   return;
							   }
							   if (result == nil) {
								   return;
							   }
							   NSString *transcript = result.bestTranscription.formattedString;
							   if (!result.isFinal) {
								   // Interim hypothesis. Remembered so the timeout
								   // and manual-stop paths can report what was heard,
								   // and surfaced to GDScript as `partial_result` so
								   // the game can (a) show the child the words as
								   // they land and (b) end the session the moment a
								   // hypothesis already satisfies the prompt instead
								   // of waiting for Apple's end-of-utterance
								   // detection, which on-device can take seconds.
								   // Never emitted as `recognized` on its own: the
								   // game decides what to do with it.
								   dispatch_async(dispatch_get_main_queue(), ^{
									 if (!strongSelf.isListening) {
										 return;
									 }
									 BOOL changed = strongSelf.lastPartialTranscript == nil ||
											 ![strongSelf.lastPartialTranscript isEqualToString:transcript];
									 strongSelf.lastPartialTranscript = transcript;
									 if (changed && transcript.length > 0 && strongSelf.owner != nullptr) {
										 strongSelf.owner->_emit_partial_result(
												 String([transcript UTF8String]));
									 }
								   });
								   return;
							   }
							   dispatch_async(dispatch_get_main_queue(), ^{
								 // Mark the session complete BEFORE tearing down: cancelling
								 // the task inside _finishListening can itself trigger one
								 // more asynchronous resultHandler invocation (typically a
								 // trailing cancellation/no-speech NSError) on this exact
								 // task, and that later invocation's error branch above must
								 // already see hasReportedResult == YES.
								 strongSelf.hasReportedResult = YES;
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
	BOOL hasTranscript = transcript != nil && transcript.length > 0;
	// Mark the session complete BEFORE tearing down: [self.task cancel] inside
	// _finishListening can itself trigger one more asynchronous resultHandler
	// invocation (typically a cancellation NSError) on this same task. If that
	// happens after we already have a usable transcript here, the error-branch
	// guard below (`self.hasReportedResult`) must already see this as YES.
	if (hasTranscript) {
		self.hasReportedResult = YES;
	}
	[self _finishListening];
	if (self.owner == nullptr) {
		return;
	}
	if (hasTranscript) {
		self.owner->_emit_recognized(String([transcript UTF8String]));
	} else {
		self.owner->_emit_recognition_failed(String("timeout"));
	}
}

// Manual stop (GDScript `stop_listening()`), which the game now calls the
// moment a `partial_result` already satisfies the prompt. `_finishListening`
// cancels the task, so no final result will ever follow -- previously that
// threw away a transcript the child had genuinely produced. Apply the same
// policy as the ~5s timeout: report the best-effort partial we already have
// as `recognized` (the game still runs it through its phrase matcher), and
// if nothing was heard just stop quietly. A child cancelling is not a failure.
- (void)stopListening {
	if (!self.isListening) {
		return;
	}
	NSString *transcript = self.lastPartialTranscript;
	BOOL hasTranscript = transcript != nil && transcript.length > 0;
	if (hasTranscript) {
		self.hasReportedResult = YES;
	}
	[self _finishListening];
	if (hasTranscript && self.owner != nullptr) {
		self.owner->_emit_recognized(String([transcript UTF8String]));
	}
}

// Shared by both notification handlers below. Tears down through the single
// `_finishListening` exit path (so `listening_stopped` fires exactly once,
// same as the timeout/error/manual-stop paths above) and then reports the
// interruption honestly via `recognition_failed` rather than leaving the
// caller's "I'm listening..." UI stuck open with no explanation. A no-op if
// nothing was actually listening (e.g. the interruption happened while idle).
- (void)_interruptListeningForReason:(NSString *)reason {
	if (!self.isListening) {
		return;
	}
	[self _finishListening];
	if (self.owner != nullptr) {
		self.owner->_emit_recognition_failed(String([reason UTF8String]));
	}
}

#if TARGET_OS_IPHONE
// A Siri invocation, an incoming call, another app seizing the mic, a
// CarPlay/AirPlay route change forcing an interruption, etc. all deliver
// this notification -- NOT an NSError to the recognition task's result
// handler -- so this is the only place that observes them. Per Apple's
// documentation this notification is posted on the main thread, but this
// dispatches through the main queue anyway to match the defensive pattern
// used for every other callback in this file that could conceivably arrive
// off-thread, and so touching `self` here is never racing `_finishListening`
// running from a different queue.
//
// `TypeEnded` is deliberately a no-op beyond returning: a child's microphone
// must only reopen from a deliberate Speak tap, never resume automatically
// just because e.g. a phone call ended.
- (void)_handleAudioSessionInterruption:(NSNotification *)notification {
	NSNumber *typeValue = notification.userInfo[AVAudioSessionInterruptionTypeKey];
	if (typeValue == nil ||
			(AVAudioSessionInterruptionType)typeValue.unsignedIntegerValue != AVAudioSessionInterruptionTypeBegan) {
		return;
	}
	__weak LBSpeechController *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
	  __strong LBSpeechController *strongSelf = weakSelf;
	  if (strongSelf == nil) {
		  return;
	  }
	  [strongSelf _interruptListeningForReason:@"interrupted"];
	});
}

// Rare, more severe than a plain interruption: coreaudiod itself restarted,
// so the AVAudioEngine/AVAudioSession instances currently in use may now be
// entirely invalid, and the OS resets the session's category/mode back to
// its own defaults. Stop cleanly (if listening) the same way as a plain
// interruption, then rebuild the SFSpeechRecognizer so a later, deliberate
// Speak tap gets a fresh instance instead of silently failing forever. The
// audio session category itself is re-applied unconditionally at the top of
// `startListeningWithLocale:` on every call, so no extra recovery is needed
// for that part here.
- (void)_handleMediaServicesWereReset:(NSNotification *)notification {
	__weak LBSpeechController *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
	  __strong LBSpeechController *strongSelf = weakSelf;
	  if (strongSelf == nil) {
		  return;
	  }
	  [strongSelf _interruptListeningForReason:@"interrupted"];
	  strongSelf.recognizer = [[SFSpeechRecognizer alloc]
			  initWithLocale:[NSLocale localeWithLocaleIdentifier:strongSelf.localeIdentifier]];
	  strongSelf.recognizer.delegate = strongSelf;
	});
}
#endif

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
	// AVAudioEngine/AVAudioInputNode do not always report trouble via NSError
	// -- e.g. removing a tap or stopping an engine whose underlying I/O unit
	// the OS has already torn down mid-interruption or mid-media-services-
	// reset can raise a synchronous Objective-C NSException instead. This is
	// the single shared teardown path for every exit (final result, error,
	// timeout, manual stop, interruption, media-services reset), so this
	// @try/@catch is what stands between any of those and an uncaught
	// exception crashing the whole app on the child's iPad. There is nothing
	// left to roll back if it fires -- we are already unconditionally
	// resetting all listening state below -- so it is safe to just swallow.
	@try {
		if (self.audioEngine != nil) {
			[self.audioEngine.inputNode removeTapOnBus:0];
			[self.audioEngine stop];
		}
		[self.request endAudio];
	} @catch (NSException *exception) {
	}
	[self.task cancel];
	self.request = nil;
	self.task = nil;
	self.lastPartialTranscript = nil;
	self.isListening = NO;
	self.inputLevel = 0.0f;
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
	ClassDB::bind_method(D_METHOD("set_voice_processing", "enabled"), &LittleBuddySpeech::set_voice_processing);
	ClassDB::bind_method(D_METHOD("is_voice_processing"), &LittleBuddySpeech::is_voice_processing);
	ClassDB::bind_method(D_METHOD("get_input_level"), &LittleBuddySpeech::get_input_level);

	ADD_SIGNAL(MethodInfo("permission_result", PropertyInfo(Variant::BOOL, "granted")));
	ADD_SIGNAL(MethodInfo("recognized", PropertyInfo(Variant::STRING, "text")));
	ADD_SIGNAL(MethodInfo("partial_result", PropertyInfo(Variant::STRING, "text")));
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

void LittleBuddySpeech::set_voice_processing(bool enabled) {
	if (controller != nullptr) {
		[controller setVoiceProcessingEnabled:(enabled ? YES : NO)];
	}
}

bool LittleBuddySpeech::is_voice_processing() const {
	return controller != nullptr && controller.voiceProcessing;
}

float LittleBuddySpeech::get_input_level() const {
	if (controller == nullptr || !controller.isListening) {
		return 0.0f;
	}
	return controller.inputLevel;
}

// All six _emit_* methods below marshal into Godot via `call_deferred`
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

void LittleBuddySpeech::_emit_partial_result(const String &text) {
	call_deferred("emit_signal", StringName("partial_result"), text);
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
