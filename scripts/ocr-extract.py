import argparse
import json
import re
from pathlib import Path


def _normalize_lines(values):
    lines = []
    for value in values:
        if value is None:
            continue
        for part in str(value).splitlines():
            text = part.strip()
            if text:
                lines.append(text)
    return lines


def _normalize_chapter(value):
    token = str(value).strip().upper().replace(" ", "")
    token = token.replace("O", "0").replace("I", "1").replace("L", "1")
    digits = re.sub(r"[^0-9]", "", token)
    if not digits:
        return ""
    try:
        return str(int(digits))
    except ValueError:
        return digits


def _extract_fields(lines):
    chapter = ""
    chapter_title = ""
    concepts = []

    chapter_pattern = re.compile(r"\bCH\s*([0-9OIl]{1,3})\s*(?:[:\-]\s*|\s+)(.+)$", re.IGNORECASE)
    lesson_pattern = re.compile(r"^\s*\d+\s*[:\-]\s*(.+)$")

    for line in lines:
        match = chapter_pattern.search(line)
        if match and not chapter:
            chapter = _normalize_chapter(match.group(1))
            chapter_title = match.group(2).strip()

    for line in lines:
        match = lesson_pattern.match(line)
        if not match:
            continue
        lesson = match.group(1).strip()
        if lesson and lesson not in concepts:
            concepts.append(lesson)

    return {
        "chapter": chapter,
        "chapterTitle": chapter_title,
        "concept": ", ".join(concepts),
        "lines": lines,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshot", action="append", dest="screenshots", default=[])
    args = parser.parse_args()

    screenshots = [Path(item) for item in args.screenshots if item]
    valid_screenshots = [item for item in screenshots if item.exists() and item.is_file()]

    result = {
        "chapter": "",
        "chapterTitle": "",
        "concept": "",
        "lines": [],
        "error": "",
    }

    if not valid_screenshots:
        result["error"] = "no_screenshots"
        print(json.dumps(result))
        return

    try:
        import easyocr
    except Exception:
        result["error"] = "easyocr_not_installed"
        print(json.dumps(result))
        return

    try:
        reader = easyocr.Reader(["en"], gpu=False, verbose=False)
    except TypeError:
        reader = easyocr.Reader(["en"], gpu=False)
    except Exception:
        result["error"] = "easyocr_init_failed"
        print(json.dumps(result))
        return

    collected_lines = []
    for screenshot in valid_screenshots:
        try:
            text_items = reader.readtext(str(screenshot), detail=0, paragraph=False)
            collected_lines.extend(_normalize_lines(text_items))
        except Exception:
            continue

    unique_lines = []
    seen = set()
    for line in collected_lines:
        if line in seen:
            continue
        seen.add(line)
        unique_lines.append(line)

    extracted = _extract_fields(unique_lines)
    result.update(extracted)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
