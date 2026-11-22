"""Build an installable release from the addon manifest."""
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "SocialCreditSystem.toc"


def main():
    manifest = MANIFEST.read_text(encoding="utf-8-sig")
    version = re.search(r"^## Version: (\d+\.\d+\.\d+)$", manifest, re.MULTILINE).group(1)
    runtime = [
        ROOT / line.strip()
        for line in manifest.splitlines()
        if line.strip() and not line.startswith("#")
    ]
    media = sorted(path for path in (ROOT / "Media").rglob("*") if path.is_file())
    files = [MANIFEST, *runtime, *media]
    if not runtime or not media or any(not path.is_file() for path in files):
        raise SystemExit("The manifest or runtime assets are incomplete.")

    destination = ROOT / "dist" / f"SocialCreditSystem-{version}.zip"
    destination.parent.mkdir(exist_ok=True)
    with ZipFile(destination, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            archive.write(path, Path("SocialCreditSystem") / path.relative_to(ROOT))
    print(destination)


if __name__ == "__main__":
    main()
