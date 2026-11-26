#include <AudioToolbox/AudioToolbox.h>
#include <chrono>
#include <filesystem>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <sys/resource.h>
#include <vector>
#include <whisper.h>

using Clock = std::chrono::steady_clock;

double ms(Clock::time_point start) {
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

std::string json(const std::string &value) {
    std::ostringstream out;
    out << '"';
    for (unsigned char ch : value) {
        switch (ch) {
            case '"': out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (ch >= 0x20) out << ch;
        }
    }
    out << '"';
    return out.str();
}

std::vector<float> fixture(const std::string &path) {
    auto url = CFURLCreateFromFileSystemRepresentation(
        nullptr, reinterpret_cast<const UInt8 *>(path.data()), path.size(), false);
    if (!url) throw std::runtime_error("Invalid fixture URL");
    ExtAudioFileRef raw = nullptr;
    auto status = ExtAudioFileOpenURL(url, &raw);
    CFRelease(url);
    if (status || !raw) throw std::runtime_error("Cannot open fixture");
    std::unique_ptr<std::remove_pointer_t<ExtAudioFileRef>, decltype(&ExtAudioFileDispose)> file(raw, ExtAudioFileDispose);
    SInt64 length = 0;
    UInt32 size = sizeof(length);
    AudioStreamBasicDescription source{};
    UInt32 sourceSize = sizeof(source);
    if (ExtAudioFileGetProperty(raw, kExtAudioFileProperty_FileLengthFrames, &size, &length) ||
        ExtAudioFileGetProperty(raw, kExtAudioFileProperty_FileDataFormat, &sourceSize, &source) ||
        length <= 0 || length > 16000 * 120 || source.mSampleRate != 16000 ||
        source.mChannelsPerFrame != 1) {
        throw std::runtime_error("Use mono 16 kHz synthetic fixtures <= 120 seconds");
    }
    AudioStreamBasicDescription format{
        16000, kAudioFormatLinearPCM,
        kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 4, 1, 4, 1, 32, 0
    };
    if (ExtAudioFileSetProperty(raw, kExtAudioFileProperty_ClientDataFormat, sizeof(format), &format)) {
        throw std::runtime_error("Cannot configure PCM reader");
    }
    std::vector<float> samples(length);
    AudioBufferList buffers{1, {{1, UInt32(samples.size() * sizeof(float)), samples.data()}}};
    UInt32 frames = static_cast<UInt32>(samples.size());
    if (ExtAudioFileRead(raw, &frames, &buffers) || frames != samples.size()) {
        throw std::runtime_error("Cannot read complete fixture");
    }
    return samples;
}

int main(int argc, char **argv) {
    try {
        if (argc < 4) throw std::runtime_error("Usage: WhisperProbe MODEL LANGUAGE FILE...");
        auto initialization = Clock::now();
        auto contextParams = whisper_context_default_params();
        std::unique_ptr<whisper_context, decltype(&whisper_free)> context(
            whisper_init_from_file_with_params(argv[1], contextParams), whisper_free);
        if (!context) throw std::runtime_error("Cannot initialize Whisper");
        std::cout << "{\"event\":\"setup\",\"engine\":\"whisper-turbo\",\"prepare_ms\":"
                  << ms(initialization) << "}" << std::endl;
        for (int i = 3; i < argc; ++i) {
            const std::string path = argv[i];
            auto start = Clock::now();
            const auto samples = fixture(path);
            auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
            params.language = argv[2];
            params.no_context = true;
            params.print_progress = false;
            params.print_realtime = false;
            params.print_timestamps = false;
            params.n_threads = 4;
            int status = whisper_full(context.get(), params, samples.data(), static_cast<int>(samples.size()));
            if (status != 0) throw std::runtime_error("Decode failed: " + std::to_string(status));
            std::string transcript;
            for (int segment = 0; segment < whisper_full_n_segments(context.get()); ++segment) {
                transcript += whisper_full_get_segment_text(context.get(), segment);
            }
            const auto language = whisper_lang_str(whisper_full_lang_id(context.get()));
            struct rusage usage{};
            getrusage(RUSAGE_SELF, &usage);
            std::cout << "{\"event\":\"result\",\"engine\":\"whisper-turbo\",\"mode\":\"batch\",\"fixture\":"
                      << json(std::filesystem::path(path).filename().string())
                      << ",\"locale\":" << json(language ? language : "unknown")
                      << ",\"requested_language\":" << json(argv[2])
                      << ",\"process_peak_bytes\":" << usage.ru_maxrss
                      << ",\"finish_ms\":" << ms(start) << ",\"transcript\":" << json(transcript)
                      << "}" << std::endl;
        }
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
