import argparse
import json
import os
import shutil
import subprocess
import sys

# Godot's WAV importer only accepts 16-bit PCM or IEEE float; 24-bit sources
# (often tagged WAVE_FORMAT_EXTENSIBLE) are rejected, so every output is written
# as plain 16-bit PCM.
OUTPUT_CODEC = "pcm_s16le"

# Sliding-window length (seconds) for astats' RMS-peak measurement.
WINDOW_SECONDS = 0.05


def measure_levels(path, channels=None):
    command = ["ffmpeg", "-hide_banner", "-i", path]
    if channels is not None:
        command.extend(["-ac", str(channels)])
    command.extend([
        "-af", f"astats=metadata=1:length={WINDOW_SECONDS}",
        "-f", "null", "-",
    ])
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: ffmpeg failed to analyse {path} (exit {result.returncode}).")
        print(result.stderr.strip())
        sys.exit(1)

    rms_peaks = _collect(result.stderr, "RMS peak dB:")
    sample_peaks = _collect(result.stderr, "Peak level dB:")
    if not rms_peaks or not sample_peaks:
        print(f"Error: could not read astats output for {path}.")
        sys.exit(1)
    return max(rms_peaks), max(sample_peaks)


def _collect(text, label):
    values = []
    for line in text.splitlines():
        marker = line.find(label)
        if marker == -1:
            continue
        token = line[marker + len(label):].strip()
        try:
            values.append(float(token))
        except ValueError:
            continue
    return values


def normalise(entry, tiers, peak_ceiling, default_channels=1, default_sample_rate=22050, default_bit_depth=8):
    tier_name = entry["tier"]
    if tier_name not in tiers:
        print(f"Error: sound {entry['input']} uses unknown tier '{tier_name}'.")
        sys.exit(1)
    target_level = tiers[tier_name]["target_level"]

    channels = entry.get("channels", default_channels)
    sample_rate = entry.get("sample_rate", default_sample_rate)
    bit_depth = entry.get("bit_depth", default_bit_depth)

    input_path = entry["input"]
    output_path = entry["output"]

    output_path = os.path.splitext(output_path)[0] + ".wav"

    loudest, sample_peak = measure_levels(input_path, channels=channels)

    gain = target_level - loudest
    filters = f"volume={gain:.2f}dB"
    if bit_depth and bit_depth < 16:
        filters += f",acrusher=bits={bit_depth}:mix=1.0:mode=lin:aa=0.5"
    limited = sample_peak + gain > peak_ceiling
    if limited:
        limit_lin = 10.0 ** (peak_ceiling / 20.0)
        filters += f",alimiter=limit={limit_lin:.6f}:level=disabled"

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", input_path,
        "-ac", str(channels),
        "-ar", str(sample_rate),
        "-af", filters,
        "-c:a", OUTPUT_CODEC,
        output_path,
    ]

    result = subprocess.run(command)
    if result.returncode != 0:
        print(f"Error: ffmpeg failed to write {output_path} (exit {result.returncode}).")
        sys.exit(1)

    achieved_loudest, achieved_peak = measure_levels(output_path)
    note = "  [limited]" if limited else ""
    channel_desc = "mono" if channels == 1 else f"{channels}ch"
    bit_desc = f"{bit_depth}-bit" if bit_depth and bit_depth < 16 else "16-bit"
    print(f"{os.path.basename(output_path):<22} {tier_name:<10} {channel_desc:<5} {sample_rate}Hz {bit_desc:<6} "
          f"loudest {loudest:6.1f} -> {achieved_loudest:6.1f} dB "
          f"(target {target_level}), peak {achieved_peak:5.1f} dB{note}")


def main():
    parser = argparse.ArgumentParser(
        description="Normalise each sound (WAV, OGG, etc.) and output as bitcrushed mono 16-bit PCM WAV."
    )
    parser.add_argument("--manifest", default=os.path.join("scripts", "config", "sounds.json"),
                        help="Sound manifest (default: scripts/config/sounds.json)")
    parser.add_argument("--sample-rate", type=int, default=None,
                        help="Global sample rate override (e.g. 22050, 16000, 11025)")
    parser.add_argument("--channels", type=int, default=None,
                        help="Global channels override (e.g. 1 for mono, 2 for stereo)")
    parser.add_argument("--bits", type=int, default=None,
                        help="Global bit depth override (e.g. 8 for 8-bit crunch, 16 for clean)")
    args = parser.parse_args()

    if shutil.which("ffmpeg") is None:
        print("Error: ffmpeg not found on PATH.")
        sys.exit(1)

    if not os.path.exists(args.manifest):
        print(f"Error: manifest not found: {args.manifest}")
        sys.exit(1)

    with open(args.manifest, encoding="utf-8") as handle:
        manifest = json.load(handle)

    peak_ceiling = manifest.get("peak_ceiling", -1.0)
    tiers = manifest["tiers"]
    default_channels = args.channels if args.channels is not None else manifest.get("channels", 1)
    default_sample_rate = args.sample_rate if args.sample_rate is not None else manifest.get("sample_rate", 22050)
    default_bit_depth = args.bits if args.bits is not None else manifest.get("bit_depth", 8)

    for entry in manifest["sounds"]:
        if not os.path.exists(entry["input"]):
            print(f"Error: input not found: {entry['input']}")
            sys.exit(1)

    for entry in manifest["sounds"]:
        normalise(
            entry,
            tiers,
            peak_ceiling,
            default_channels=default_channels,
            default_sample_rate=default_sample_rate,
            default_bit_depth=default_bit_depth,
        )


if __name__ == "__main__":
    main()
