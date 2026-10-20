# local_dictation

Private, on-device dictation primitives extracted from the AudioFlow implementation in `mobile_transcribe` (worker, model metadata and verifier, capture adapter, and PCM segmenter). The package has no dependency on that checkout or its application storage, project, recording, Vault, or search features.

The model descriptors pin the Hugging Face repository revision, expected file size, and SHA-256 for SenseVoice Small and Cohere Transcribe. Respect each upstream model repository's license and use terms when distributing installed model files. The original source checkout did not include a repository-level license file to carry over; this package does not claim ownership or grant rights to the upstream models.

Audio enters only through `DictationCapture` as PCM bytes and stays in bounded in-memory buffers. Models are downloaded only by an explicit `ModelManager.prepareModel` call. `LocalDictationController.start` requires a fully verified installed model, and each final phrase is sent once to the injected `onText` callback without a replay queue.
