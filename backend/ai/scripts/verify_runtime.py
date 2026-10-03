from pathlib import Path
import importlib.metadata
import sys


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_FILES = [
    ROOT / "models" / "guardian_context_model" / "model.int8.onnx",
    ROOT / "models" / "guardian_context_model" / "tokenizer.json",
    ROOT / "models" / "guardian_context_model" / "labels.json",
    ROOT / "models" / "guardian_context_model" / "thresholds.json",
    ROOT / "models" / "yamnet" / "yamnet.onnx",
    ROOT / "models" / "yamnet" / "yamnet_class_map.csv",
]
REQUIRED_PACKAGES = [
    "faster-whisper",
    "ctranslate2",
    "numpy",
    "rapidfuzz",
    "onnxruntime",
    "tokenizers",
    "google-genai",
    "openai",
    "pypdf",
]


def main() -> int:
    missing_files = [str(path.relative_to(ROOT)) for path in REQUIRED_FILES if not path.is_file()]
    missing_packages = []
    for package in REQUIRED_PACKAGES:
        try:
            importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            missing_packages.append(package)

    for path in REQUIRED_FILES:
        state = "OK" if path.is_file() else "MISSING"
        print(f"[{state}] {path.relative_to(ROOT)}")
    for package in REQUIRED_PACKAGES:
        state = "MISSING" if package in missing_packages else importlib.metadata.version(package)
        print(f"[{state}] package:{package}")

    if missing_files or missing_packages:
        print("Runtime verification failed.")
        return 1
    print("Runtime verification passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
