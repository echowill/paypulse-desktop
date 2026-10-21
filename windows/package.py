"""Create a Windows-friendly ZIP with ASCII names and no macOS metadata."""
import argparse
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--input", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--license", type=Path)
args = parser.parse_args()
source = Path(__file__).resolve().parent
license_path = args.license or source.parent / "LICENSE"
entries = {
    "PayPulse.exe": (args.input / "PayPulse.exe").read_bytes(),
    "EngineChecks.exe": (args.input / "EngineChecks.exe").read_bytes(),
    "README.txt": source.joinpath("README.md").read_text(encoding="utf-8").replace("\n", "\r\n").encode("utf-8-sig"),
    "LICENSE": license_path.read_bytes(),
}
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name, content in entries.items():
        info = zipfile.ZipInfo("PayPulse-Windows11-x64/" + name)
        info.create_system = 0
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, content)
print(args.output)
