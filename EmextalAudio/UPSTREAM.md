# EmextalAudio — Upstream Provenance & Sync Guide

This package is a **hand-extracted subset** of the Swift sources we actually use from
[`mlx-audio-swift`](https://github.com/Blaizzy/mlx-audio-swift) (branch `main`). It exists so the
app doesn't pull the entire upstream package (and its large transitive dependency graph). The
files here are copies — lightly edited (see *Intentional divergences* below) — not a submodule.

Periodically we do a **sync pass**: diff upstream `main` since the last synced commit, and fold any
changes that touch the files we extracted back into this package. This document records everything
needed to do that quickly.

## Last synced

| | |
|---|---|
| Upstream repo | `https://github.com/Blaizzy/mlx-audio-swift` |
| Upstream branch | `main` |
| **Last synced upstream commit** | `3f6b0553188a921f635df54b5e20442001037336` |

> When you finish a sync pass, **update the commit hash above** to the upstream `main` HEAD you
> reconciled against. That hash is the `<baseline>` for the next pass.

## File → upstream mapping

Several files were renamed during extraction, so you can't match by filename alone. The original
upstream path for each file is also recorded in its header comment (`// MLXAudio…` module name).
Mapping (paths relative to the upstream repo root):

| Local file | Upstream path |
|---|---|
| `AdaLayerNorm.swift` | `Sources/MLXAudioCodecs/Vocos/Vocos.swift` *(subset: `AdaLayerNorm` only)* |
| `DSP.swift` | `Sources/MLXAudioCore/DSP.swift` *(upstream header still reads `MelSpectrogram.swift`)* |
| `GLMASR.swift` | `Sources/MLXAudioSTT/Models/GLMASR/GLMASR.swift` |
| `GLMASRConfig.swift` | `Sources/MLXAudioSTT/Models/GLMASR/GLMASRConfig.swift` |
| `GLMASRLayers.swift` | `Sources/MLXAudioSTT/Models/GLMASR/GLMASRLayers.swift` |
| `GenerationTypes.swift` | `Sources/MLXAudioCore/Generation/GenerationTypes.swift` |
| `STTGeneration.swift` | `Sources/MLXAudioSTT/Generation.swift` *(subset; match by `STTGenerateParameters`)* |
| `STTOutput.swift` | `Sources/MLXAudioSTT/Models/GLMASR/STTOutput.swift` |
| `SileroVAD.swift` | `Sources/MLXAudioVAD/Models/SileroVAD/SileroVAD.swift` |
| `SileroVADConfig.swift` | `Sources/MLXAudioVAD/Models/SileroVAD/SileroVADConfig.swift` |
| `Soprano.swift` | `Sources/MLXAudioTTS/Models/Soprano/Soprano.swift` |
| `SopranoConfig.swift` | `Sources/MLXAudioTTS/Models/Soprano/SopranoConfig.swift` |
| `SopranoDecoder.swift` | `Sources/MLXAudioTTS/Models/Soprano/SopranoDecoder.swift` |
| `TTSGeneration.swift` | `Sources/MLXAudioTTS/Generation.swift` *(subset; match by `SpeechGenerationModel`)* |
| `TextProcessor.swift` | `Sources/MLXAudioTTS/TextProcessor.swift` |
| `TextUtils.swift` | `Sources/MLXAudioTTS/Models/Soprano/TextUtils.swift` |
| `VADOutput.swift` | `Sources/MLXAudioVAD/VADOutput.swift` |
| `VocosBackbone.swift` | `Sources/MLXAudioCodecs/Vocos/VocosBackbone.swift` |
| `TokenizerLoader.swift` | **Local only — no upstream equivalent.** Bridges `swift-tokenizers` to `MLXLMCommon`; replaces the `swift-tokenizers-mlx` integration package. Do not look for it upstream. |

The models we extract span these upstream targets only: **MLXAudioSTT** (GLM-ASR), **MLXAudioTTS**
(Soprano), **MLXAudioVAD** (SileroVAD), **MLXAudioCore**, **MLXAudioCodecs** (Vocos). Upstream
changes to any *other* model/target (Whisper, Nemo/Nemotron, Parakeet, Voxtral, Irodori, Qwen3-TTS,
Kokoro, Sortformer, …) are irrelevant to us and can be ignored.

## Intentional divergences from upstream

These are deliberate and should be preserved when folding in upstream changes — don't "fix" them
back:

- **Visibility:** types/members are widened to `public` so the app can use them across the package
  boundary.
- **Dependencies trimmed:** the package depends only on `mlx-swift`, `mlx-swift-lm`, and
  `swift-tokenizers`. Notably the direct dependency on `swift-transformers` was removed (see
  `TokenizerLoader.swift`). If an upstream change introduces a new import, prefer re-implementing
  the small piece locally over re-adding a heavy dependency.
- **Original headers retained:** the `// MLXAudio…` header comments are kept on purpose — they are
  our provenance breadcrumbs for this mapping.
- **Symbol renames to avoid collisions:** because we flatten multiple upstream targets into one
  module, upstream namespacing sometimes has to be applied locally too. Example (sync of
  2026-06: upstream `0c71eba`): GLM-ASR's `WhisperConfig` / `WhisperAttention` /
  `WhisperEncoderLayer` / `WhisperEncoder` were renamed to `GLMASRWhisper…`. Upstream did this to
  avoid clashing with its new Whisper model family; we don't extract that family, but we mirror the
  rename to keep diffs clean.

## Sync procedure

```sh
# 1. Clone upstream (blobless clone is fast and enough for diffing).
git clone --filter=blob:none https://github.com/Blaizzy/mlx-audio-swift.git /tmp/mlx-audio-swift
cd /tmp/mlx-audio-swift

BASELINE=3f6b0553188a921f635df54b5e20442001037336   # <-- "Last synced" commit above
HEAD=$(git rev-parse HEAD)

# 2. See which upstream files changed, then intersect with the mapping table above.
git diff --name-only $BASELINE..$HEAD

# 3. For each affected mapped file, read the actual diff and fold relevant changes in,
#    preserving the intentional divergences listed above.
git diff $BASELINE..$HEAD -- Sources/MLXAudioSTT/Models/GLMASR/GLMASRLayers.swift   # etc.
```

Then, back in this package:
- Apply the changes to the corresponding local files.
- Sanity-check with Xcode (`XcodeRefreshCodeIssuesInFile` on edited files, or a full `BuildProject`).
- **Update the "Last synced" commit hash** in this document to `$HEAD`.
- Commit with a message noting the upstream range synced.

## History

| Date | Synced to upstream | Notes |
|---|---|---|
| 2026-06-14 | `856e04afb3c6eb931d92bb0d6ae7bbfbdfa89b15` | Initial extraction (`dfd3df4` in this repo). |
| 2026-06-20 | `3f6b0553188a921f635df54b5e20442001037336` | First maintenance pass. Only GLM-ASR `Whisper*` → `GLMASRWhisper*` rename affected us; everything else upstream was in non-extracted models. |
