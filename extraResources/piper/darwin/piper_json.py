import argparse
import json
import os
import sys
import wave

import piper
from piper import PiperVoice, SynthesisConfig


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--speaker", type=int, default=0)
    args = parser.parse_args()

    base_dir = os.getcwd()
    model_path = os.path.abspath(args.model)

    # espeak-ng truncates data paths longer than ~160 characters: run from the
    # piper package directory so a short relative path is passed instead.
    os.chdir(os.path.dirname(piper.__file__))
    voice = PiperVoice.load(model_path, espeak_data_dir="espeak-ng-data")
    syn_config = SynthesisConfig(
        speaker_id=args.speaker if voice.config.num_speakers > 1 else None
    )

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        job = json.loads(line)
        output_path = os.path.join(base_dir, job["output_file"])
        with wave.open(output_path, "wb") as wav_file:
            voice.synthesize_wav(job["text"], wav_file, syn_config)


if __name__ == "__main__":
    main()
