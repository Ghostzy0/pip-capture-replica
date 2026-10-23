# Third-party notices

Pip edition: original Swift code, MIT (Ghostzy0, 2026). Native Apple frameworks and SF Symbols are used through system APIs; no system font or symbol files are redistributed. The original geometric Pip drawing and state mapping do not import the reserved Pip-motion engine.

Local subprocess integration is informed by WhisperNotes WhisperService, MIT, Copyright (c) 2024 Silvio Pavanetto. Its full licence is preserved at baseline/LICENSE in source and WhisperNotes-LICENSE in the Pip package. No proprietary reference source, branding, media, or screenshots are distributed as product assets.

## Declared baseline edition

`baseline/` is a source snapshot of https://github.com/reidemeister94/whisper-notes at `05d12535863757943a7e243edd2df7cea1d86f84`, MIT, Copyright (c) 2024 Silvio Pavanetto. Included source/tests retain upstream names for provenance, without implying upstream endorsement. No original app icon is copied. Changes: app identity/data paths isolated under Pip Capture Baseline; default Markdown directory stays inside its app storage; packaging handles nested SwiftPM resource layout. Baseline retains upstream optional Cohere/Voxtral implementations; their models are not bundled, configured or downloaded by building. Those paths are not qualified as part of the Pip edition.

Vendored baseline `Sources/Cvoxtral/`: MIT, Copyright (c) 2026 Salvatore Sanfilippo; complete notice at baseline/Sources/Cvoxtral/LICENSE. This code is not linked by the Pip edition. Optional backend dependencies listed in baseline/Sources/WhisperNotes/Resources/CohereBackend/requirements.txt are upstream instructions, not installed by the app build. Model licences are separate; assess before use. Weights are excluded from source and packages.

## Font

Geist Regular from https://github.com/vercel/geist-font (`fonts/Geist/ttf/Geist-Regular.ttf`); Copyright 2024 The Geist Project Authors; SIL Open Font License 1.1, full notice at Resources/Geist-OFL.txt. Unmodified font self-hosted locally. Exact downloaded file SHA256 is recorded in UPSTREAM.md.

## Optional local speech runtime

Pip accepts an explicitly chosen trusted whisper.cpp executable and compatible weights. Neither is silently installed, downloaded, or bundled. whisper.cpp source: https://github.com/ggml-org/whisper.cpp (MIT). OpenAI Whisper weights: https://github.com/openai/whisper (MIT). Other converted/custom weights may differ and require separate review.

Mem and Voicenotes are independent proprietary workflow references. No affiliation is claimed.
