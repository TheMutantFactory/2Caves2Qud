"""Caves of Qud's 18-colour palette, keyed by the game's one-letter colour code
(the letters in a blueprint's TileColor="&r" / DetailColor="w"). Transcribed
from the official wiki's Visual Style page; the same values the game paints.

Tiles are 2-colour masks: BLACK pixels take the object's TileColor (main),
WHITE pixels take its DetailColor (detail), transparent is the background.
"""

COLORS = {
    "r": (0xa6, 0x4a, 0x2e), "R": (0xd7, 0x42, 0x00),   # dark red / red
    "o": (0xf1, 0x5f, 0x22), "O": (0xe9, 0x9f, 0x10),   # dark orange / orange
    "w": (0x98, 0x87, 0x5f), "W": (0xcf, 0xc0, 0x41),   # brown / gold
    "g": (0x00, 0x94, 0x03), "G": (0x00, 0xc4, 0x20),   # dark green / green
    "b": (0x00, 0x48, 0xbd), "B": (0x00, 0x96, 0xff),   # dark blue / azure
    "c": (0x40, 0xa4, 0xb9), "C": (0x77, 0xbf, 0xcf),   # dark cyan / cyan
    "m": (0xb1, 0x54, 0xcf), "M": (0xda, 0x5b, 0xd6),   # dark magenta / magenta
    "k": (0x0f, 0x3b, 0x3a), "K": (0x15, 0x53, 0x52),   # viridian bg / dark grey
    "y": (0xb1, 0xc9, 0xc3), "Y": (0xff, 0xff, 0xff),   # grey / white
}


def rgb(letter, default=(0xb1, 0xc9, 0xc3)):
    return COLORS.get(letter, default)


def fg_letter(color_string):
    """The foreground letter of a Qud colour string: the char after the LAST
    '&' anywhere in it ('&r^w' -> 'r', '&Y^y&b' -> 'b'); None if there is none."""
    if not color_string:
        return None
    i = color_string.rfind("&")
    if i < 0 or i + 1 >= len(color_string):
        return None
    return color_string[i + 1]
