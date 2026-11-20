#!/usr/bin/env python3
"""Extract question illustrations with their source PDF geometry.

Requires pdfplumber and Poppler pdfimages. Paths are relative to the working
folder when possible. A question number is included only when the image is
aligned with a numbered question in the source PDF.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import pdfplumber
from source_files import store_image


def extract_bank_images(pdf: Path, bank_id: str, output_root: Path, all_images: list | None = None) -> list[dict]:
    pdf = Path(pdf).resolve()
    output_root = Path(output_root).resolve()
    executable = shutil.which('pdfimages')
    if not executable:
        candidate = Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/poppler/bin/pdfimages'
        if candidate.is_file():
            executable = str(candidate)
        else:
            raise FileNotFoundError('Poppler pdfimages is required')
    # Illustrations recur across licence banks; their bytes define identity.
    output_dir = output_root / 'shared'
    output_dir.mkdir(parents=True, exist_ok=True)
    result = []
    with tempfile.TemporaryDirectory(prefix='pdf-bank-images-') as tmp:
        prefix = Path(tmp) / 'image'
        subprocess.run([executable, '-png', str(pdf), str(prefix)], check=True, stdout=subprocess.DEVNULL)
        files = sorted(Path(tmp).glob('image-*'), key=lambda p: int(p.stem.rsplit('-', 1)[1]))
        index = 0
        with pdfplumber.open(pdf) as doc:
            for page_no, page in enumerate(doc.pages):
                rows = sorted((w for w in page.extract_words() if w['x0'] < 50 and re.fullmatch(r'\d{4,6}', w['text'])), key=lambda w: w['top'])
                for image in page.images:
                    if index >= len(files):
                        raise ValueError(f'{pdf}: pdfimages/pdfplumber image count mismatch on page {page_no + 1}')
                    source = files[index]
                    index += 1
                    data = source.read_bytes()
                    sha = hashlib.sha256(data).hexdigest()
                    store_image(data, source.suffix)
                    dest = output_dir / (sha + source.suffix.lower())
                    if not dest.exists():
                        dest.write_bytes(data)
                    try:
                        path = str(dest.relative_to(Path.cwd()))
                    except ValueError:
                        path = str(dest)
                    placement={'page': page_no, 'top': image['top'], 'bottom': image['bottom'], 'x0': image['x0'], 'x1': image['x1'], 'path': path, 'sha256': sha}
                    # Retain logos and other embedded images as source artifacts too.
                    # Only images in the question-image column enter question_assets.
                    if image['x0'] >= page.width * 0.65:
                        candidates = [r for r in rows if abs(r['top'] - image['top']) <= 5]
                        if len(candidates) != 1:
                            raise ValueError(f'{pdf}: cannot unambiguously match image at page {page_no + 1}, top {image["top"]:.1f} to a question')
                        placement['question_number']=int(candidates[0]['text'])
                        result.append(placement)
                    if all_images is not None:
                        all_images.append(placement)
                page.close()
        if index != len(files):
            raise ValueError(f'{pdf}: pdfimages extracted {len(files)} images but pdfplumber found {index}; masks may require special handling')
    return result
