# Third-party weights and runtime

- Fluid Speech Pro by FluidVoice, CC BY 4.0. This application bundles the original INT8 Core ML components from the pinned FluidVoice conversion. Repackaging leaves weight bytes intact. [Model card](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro) · [Model files](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro-coreml/tree/3b9d38a93d606f84011e5a0a669b7ea146375a22)
- Parakeet Ultra by Moondream, CC BY 4.0. FluidInference provided the 8-bit Core ML conversion. The wrapper adds a file-name alias for the joint component to support the test runtime. [Model card](https://huggingface.co/moondream/parakeet-ultra) · [Core ML conversion](https://huggingface.co/FluidInference/parakeet-ultra-coreml/tree/95eaa59a39d4394f047a4dc5cce480388a60d1b6)
- Both derive from NVIDIA Parakeet TDT 0.6B v3, CC BY 4.0. [Original model](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) · [License](https://creativecommons.org/licenses/by/4.0/)
- FluidAudio, Apache 2.0, at the FluidVoice maintainer fork and pinned revision. [Source and license](https://github.com/altic-dev/FluidAudio/tree/386f7195670b77f2954c7ee143ec63fcb50b6c3b)
- Rasc reused source, KeyboardShortcuts and GRDB.swift use MIT. See the [Rasc third-party notices](../../../../docs/THIRD_PARTY_NOTICES.md).
