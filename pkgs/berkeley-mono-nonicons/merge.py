"""Copy the nonicons glyphs into a Berkeley Mono face, at nonicons' own em size.

Rex has no font-codepoint-map, so the icons must live in the terminal font.
Only glyphs, hmtx and cmap entries are added; Berkeley Mono's own glyphs,
metrics and OpenType features are left untouched.
"""
import logging
import sys

from fontTools.ttLib import TTFont
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

logging.getLogger("fontTools").setLevel(logging.ERROR)

base_path, icons_path, out_path, family, postscript = sys.argv[1:]
font = TTFont(base_path, recalcTimestamp=False)
icons = TTFont(icons_path)

cff = font["CFF "].cff
top = cff[cff.fontNames[0]]
charstrings = top.CharStrings
private = top.Private
advance = font["hmtx"][font.getBestCmap()[ord("M")]][0]
scale = font["head"].unitsPerEm / icons["head"].unitsPerEm
default_width = getattr(private, "defaultWidthX", 0)
nominal_width = getattr(private, "nominalWidthX", 0)

order = font.getGlyphOrder()
icon_glyphs = icons.getGlyphSet()
mapping = {}
for codepoint, name in sorted(icons.getBestCmap().items()):
    if not 0xE000 <= codepoint <= 0xF8FF:
        continue
    glyph = f"nonicons.{name}"
    pen = T2CharStringPen(None if advance == default_width else advance - nominal_width, None)
    icon_glyphs[name].draw(TransformPen(pen, (scale, 0, 0, scale, 0, 0)))
    charstring = pen.getCharString(private=private, globalSubrs=cff.GlobalSubrs)
    charstrings.charStringsIndex.append(charstring)
    charstrings.charStrings[glyph] = len(charstrings.charStringsIndex) - 1
    bounds = BoundsPen(None)
    icon_glyphs[name].draw(TransformPen(bounds, (scale, 0, 0, scale, 0, 0)))
    font["hmtx"][glyph] = (advance, round(bounds.bounds[0]) if bounds.bounds else 0)
    order.append(glyph)
    mapping[codepoint] = glyph

font.setGlyphOrder(order)
top.charset = order
for table in font["cmap"].tables:
    if table.isUnicode():
        table.cmap.update(mapping)

style = font["name"].getDebugName(17) or font["name"].getDebugName(2)
full = family if style == "Regular" else f"{family} {style}"
names = font["name"]
for name_id in (1, 3, 4, 6, 16, 17):
    names.removeNames(nameID=name_id)
for name_id, value in ((1, family), (2, style), (3, postscript), (4, full), (6, postscript), (16, family), (17, style)):
    names.setName(value, name_id, 3, 1, 0x409)
    names.setName(value, name_id, 1, 0, 0)
top.FullName = full
top.FamilyName = family
cff.fontNames[0] = postscript
font.save(out_path)
