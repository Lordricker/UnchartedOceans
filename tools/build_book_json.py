"""Bundles the book chapters (uncharted-oceans/data/book/*.md) into data/book/chapters.json.

Godot leaves .md files out of an exported game unless the export preset's include filter lists them, but .json
files do get exported. The book reader reads the .md directly when it can (the editor) and falls back to this
bundle (an exported game). Run this after editing a chapter:   python tools/build_book_json.py
"""
import glob, json, os
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "uncharted-oceans")
book = os.path.join(root, "data", "book")
out = {}
for p in sorted(glob.glob(os.path.join(book, "*.md"))):
    name = "res://data/book/" + os.path.basename(p)
    out[name] = open(p, encoding="utf-8").read()
json.dump(out, open(os.path.join(book, "chapters.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("bundled", len(out), "chapters ->", os.path.join(book, "chapters.json"))
