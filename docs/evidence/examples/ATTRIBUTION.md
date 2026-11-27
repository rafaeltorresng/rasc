# Example publication allowlist

## Audio and references

The five WAVs listed in [examples.json](examples.json) come from the **Google FLEURS test split** (en_us and pt_br), by Alexis Conneau and coauthors. Attribute each example to Google FLEURS and the original authors. Include its locale and source ID, the dataset and license links, and the note that the audio was staged as mono 16 kHz PCM. The reference uses the source transcript and the raw ASR hypothesis is a separate Rasc-generated text. Keep this distinction visible, including where the UI sanitizer removes `<unk>`. The five SHA-256 values identify the staged WAV bytes. [Google FLEURS](https://huggingface.co/datasets/google/fleurs), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)

## Refine text

[refine_examples.json](refine_examples.json) contains authored synthetic notes and one Google FLEURS derivative. Publish synthetic inputs with their model-generated outputs and preserve the evaluation labels for the historical and build 25 samples. For the FLEURS derivative, carry the same attribution and indicate the two transformations (ASR then Refine).

The CS-FLEURS card identifies **CC BY-NC 4.0**. The previous handoff incorrectly grouped `mix-r3-*` examples with Google FLEURS. They have been removed from the website example file. VoiceArena uses **CC BY-NC 4.0** as well. Use aggregate analysis in the handoff and obtain separate permission before using their audio, reference text or derivatives in commercial product materials. AMI and TARSILA examples also remain outside this allowlist. [CS-FLEURS](https://huggingface.co/datasets/byan/cs-fleurs), [VoiceArena dataset](https://huggingface.co/datasets/VoiceArena/Dictation_Dataset)
