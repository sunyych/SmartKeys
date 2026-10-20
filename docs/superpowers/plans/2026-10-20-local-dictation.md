# Local Dictation Implementation Plan

> Implementation uses Luna coder subagents. The primary agent reviews their changes and independently runs the full validation before committing and pushing.

**Goal:** Add private on-device microphone dictation on Android and desktop, insert final text at the computer cursor, and distinguish it from existing application dictation.

**Architecture:** Extract the reusable mobile_transcribe recognizer, model manager and PCM segmenter into a small local package. Android final text uses Bluetooth HID, with US ASCII and explicitly selected Windows Unicode profiles; Companion is optional for other features. Desktop native adapters inject Unicode and expose a global toggle shortcut.

**Tech Stack:** Flutter/Dart, sherpa_onnx 1.13.3-compatible pinned APIs, record PCM streams, Windows C++, macOS Swift.

**Spec:** `docs/superpowers/specs/2026-10-20-local-dictation-design.md`

## Global Constraints

- Audio stays in bounded memory on its capturing device, without audio files or network audio.
- Use downloaded local SenseVoice by default, plus independently selectable Cohere; retain source revision/hash verification.
- New feature must not depend on the original mobile_transcribe checkout.
- Android is the phone target. Windows and macOS are desktop targets; record unavailable native acceptance explicitly.
- Existing application dictation keeps its behavior and has a different icon/name from Local Dictation. First-use explanation requires explicit acknowledgement, then persists.
- Shared checkout: each coder owns only its assigned files; no agent commits or pushes. Root coordinates integration and delivery.
- All packages receive full test runs with LCOV coverage before commit/push. No claim of 100% coverage without evidence.

## Shared API contract

Export from `package:local_dictation/local_dictation.dart`:

```dart
enum DictationLanguage { chinese, english }
// Each language exposes String get code and String get label.
enum LocalAsrModel { senseVoice, cohere }
// Each model exposes String get label.
class LocalAsrModelFiles { /* preserve source fields */ }
class ModelDownloadProgress { /* preserve source fields and fraction */ }
class LocalAsrModelDescriptor { /* preserve pinned source metadata */ }
class ModelManager {
  Future<bool> areModelsAvailable({LocalAsrModel model = LocalAsrModel.senseVoice});
  Future<LocalAsrModelFiles> installedModel(LocalAsrModel model);
  Future<LocalAsrModelFiles> prepareModel(LocalAsrModel model,
      {void Function(ModelDownloadProgress)? onProgress});
  Future<LocalAsrModelFiles> importModel(LocalAsrModel model, Directory source);
  Future<void> deleteModel(LocalAsrModel model);
  void cancelDownload();
}
abstract interface class DictationRecognizer {
  Future<String> transcribe(Float32List samples, {DictationLanguage? language});
  Future<void> dispose({bool flush = true});
}
class LocalAsrWorker {
  static Future<DictationRecognizer> start({required LocalAsrModelFiles model,
    required DictationLanguage language, int numThreads = 2,
    String? nativeDirectory});
}
abstract interface class DictationCapture {
  Future<bool> hasPermission();
  Future<Stream<List<int>>> start();
  Future<void> stop();
  Future<void> dispose();
}
class RecordDictationCapture implements DictationCapture {}
class LocalDictationController extends ChangeNotifier {
  // Constructor accepts injected modelManager/capture/recognizerFactory/onText.
  // onText: Future<void> Function(String text); errors surfaced to UI, no replay.
  LocalAsrModel get model;
  DictationLanguage get language;
  bool get listening;
  bool get busy;
  String? get error;
  String get lastText;
  Future<void> configure({LocalAsrModel? model, DictationLanguage? language});
  Future<void> start(); // installedModel only, never implicitly downloads
  Future<void> stop(); // finishes the current utterance, then no more output
  Future<void> cancel(); // drops old-generation output
  Future<void> close(); // async teardown; dispose remains synchronous
}
```

Coder for shared package creates exact public declarations first and confirms details to the other coders. Core orchestration belongs in the shared package; each app owns settings persistence, awake lifecycle, connection gating and destination.

Phone wire contract (desktop coder owns server; Android coder owns client):

```text
Discovery capability: local-dictation-v1
POST /dictation (x-lumiakeys-token: existing token)
{"sessionId":"random per listening session","sequence":1,"text":"final phrase"}
HTTP 200 {"ok":true} only on complete insertion (or successful dedupe).
Non-200 on partial/rejected insertion. Never resend automatically.
Max encoded body 64 KiB; max text 8000 UTF-16 code units;
sessionId <= 128 ASCII-safe characters; sequence nonnegative integer.
```

## Task 1: Shared engine (Luna coder: shared_engine)

**Files:** Create `packages/local_dictation/pubspec.yaml`, `lib/local_dictation.dart`, focused `lib/src/*.dart`, `test/*.dart`, package provenance README.

**Sources:** `C:/Users/sunyy/Projects/mobile_transcribe/apps/audioflow_app/lib/dictation/local_asr_worker.dart`, `dictation_adapters.dart` (capture only), `packages/transcribe_engine/lib/domain/local_asr_model.dart`, `infrastructure/model_manager.dart`, `packages/dictation_engine/lib/src/segmenter.dart`.

- [x] Extract pinned model descriptors and manager, removing dependencies on core/project/vault and legacy app directory access. Test size/hash validation, corrupted cache, interrupted download and safe deletion/import using fixture descriptors, injected clients and temporary directories.
- [x] Extract worker and segmenter, preserve SenseVoice recognizer recreation on language changes and native library setup. Test segmentation, silence/odd byte boundaries and bounded maximum utterance.
- [x] Implement injected controller with serial decode/output, bounded pending audio, generation invalidation and safe async teardown. Test stop-flush, cancel-drop, language/model switch, initialization failure, capture failure, delivery failure followed by later success, and dispose during start.
- [x] Run `flutter pub get`, `flutter analyze`, `flutter test --coverage` in this package; report exact results and public API.

## Task 2: Desktop and text transport (Luna coder: desktop_dictation)

**Files:** Modify `desktop_companion/lib`, desktop pubspec, native Windows/macOS runners/permissions/CMake, desktop tests. No edits to root Android files or shared engine package.

- [x] Add desktop receiver service and `/dictation` endpoint behind existing token, exact wire contract above. Test token rejection, malformed/oversized input, control characters, bounded dedupe, serial delivery and sink errors. Never acknowledge partial insertion.
- [x] Port safe native Unicode insertion from source Windows/macOS adapters; use new `lumiakeys/dictation` channel. Check own/invalid foreground, modifiers and input insertion count; no transcript shell arguments. Implement native global toggle shortcut and unregister at shutdown.
- [x] Add desktop controller/UI for installed-model-only start, model download/import/delete/progress and language/model persistence. Local microphone works without phone; window hides on start. Resolve package contract with shared coder.
- [x] Add tray toggle and first-use explanation distinguishing existing Codex/application dictation (waveform) from local microphone (device/microphone). Preserve legacy shortcut semantics.
- [x] Test controller/UI and native-channel invocation with injected fakes; retain existing tests. Build/run full desktop suite with coverage and analysis. Ensure ONNX DLL correctly packaged in Windows Release.

## Task 3: Phone UI, client and repository checks (Luna coder: phone_dictation)

**Files:** Modify root `lib`, `pubspec.yaml`/lock, Android microphone permission, `test`; create repository verification/coverage script and update README. No edits to desktop or shared package.

- [x] Extend `CompanionService` with capability-gated `/dictation` text submission; errors surface, no automatic retries. Test host change, stale session, server rejection, timeout and correct token/body. New random session for each capture session.
- [x] Add persistent quick-output button separate from 15-key layouts and a compact panel, language/model selectors, explicit model download/import/delete, warm cache reuse and permission state. On disconnect/background close/cancel capture and release wakelock; start requires compatible desktop.
- [x] Distinct application waveform and local microphone/device icons, tooltips and accessibility labels. Explain difference before first use, persist acknowledgement, do not capture before acknowledgement. Cover both entry paths, portrait/landscape and stop/error states in widget tests.
- [x] Add PowerShell validation script for root, desktop, protocol and local engine full suites with LCOV, fail on nonzero exit, summarize per-package and merged coverage. Do not invent a coverage threshold; report measured percentages. Document hardware/native boundaries.
- [x] Run root full tests/coverage/analyze and Android build, report outcomes.

## Task 4: Integration review and delivery (primary agent)

- [x] Review changes against spec; request Luna corrections for discovered implementation gaps.
- [x] Independently run formatting checks, analysis and all tests with coverage for all four packages; inspect coverage report and meaningful uncovered boundaries.
- [x] Build Android APK and Windows Release; verify bundled native runtime, run available device checks without implying unavailable hardware success.
- [ ] Inspect final diff and stage only requested changes; `git commit`, `git push origin main`, compare local `HEAD` with `git ls-remote origin refs/heads/main`.
- [ ] Report artifacts, test counts, line coverage, commit and actual acceptance limits.

## Task 5: Software-wide screenshot tests and offline HTML Index (user addition)

**Files:** Create root and Desktop screenshot test/support files; create `scripts/generate_screenshot_index.ps1`; extend validation script and README. Generated artifacts stay under ignored `build/ui_screenshots/`.

- [x] Shared-engine Luna coder implements phone screenshot inventory for all public screens, dialogs and key dictation states, with portrait/landscape layouts, real widgets and injected external dependencies.
- [x] Desktop Luna coder implements all seven settings sections, editors/dialogs and important dictation states at standard and narrow desktop sizes.
- [x] Capture through Flutter `RepaintBoundary`, assert no layout/Flutter exceptions, expected contents and nonempty PNG dimensions. Use no real microphone or personal data in screenshot fixtures.
- [x] Emit per-image metadata and generate an offline HTML gallery with page names, platform, size, state notes and filters; never commit generated screenshots or HTML.
- [x] Integrate generation into full validation, inspect all results visually, correct actual layout defects, and return HTML plus an optional self-contained report ZIP to the user.
- [x] On Windows use a short NTFS staging directory when the checkout is exFAT; verify final staged source hashes equal the original checkout before committing. Preserve original source and copy requested reports/artifacts back to ignored outputs.
