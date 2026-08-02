"""Pure helpers for the prediction-embed PNGs: no web framework involved."""

import functools
import io
from pathlib import Path
import re
from typing import Tuple

from attr import dataclass
from PIL import Image, ImageDraw, ImageFont  # type: ignore

_HERE = Path(__file__).parent

ARIAL_PATH = _HERE / 'arial.ttf'
WARNOCK_PRO_PATH = _HERE / 'warnock-pro.otf'

COLOR_NAME_TO_COLOR = {
    'red'      : (255, 0  , 0  ),
    'darkgreen': (0  , 128, 0  ),
    'darkblue' : (0  , 0  , 128),
    'black'    : (0  , 0  , 0  ),
    'white'    : (255, 255, 255),
    'plainlink' : (0x0a, 0x58, 0xca),
    'lwlinkgreen': (0x5f, 0x9b, 0x65),
}


@dataclass(frozen=True)
class Style:
    color: Tuple[int, int, int]
    fontpath: Path
    fontsize: int
    underline: bool

    @staticmethod
    def parse(s: str) -> 'Style':
        s = s.lstrip('-')
        m = re.search(r'(?:-|^)([0-9]{1,2})pt\b', s)
        if m:
            fontsize = min(30, int(m.group(1)))
            s = s.replace(m.group(), '', 1)
        else:
            fontsize = 12

        if s == 'lesswrong':
            return Style(color=(0x5f, 0x9b, 0x65), fontpath=WARNOCK_PRO_PATH, fontsize=fontsize, underline=False)

        m = re.search('(?:-|^)(' + '|'.join(COLOR_NAME_TO_COLOR.keys()) + r')\b', s)
        if m:
            color = COLOR_NAME_TO_COLOR[m.group(1)]
            s = s.replace(m.group(), '', 1)
        else:
            color = COLOR_NAME_TO_COLOR['darkgreen']

        return Style(color=color, fontpath=ARIAL_PATH, fontsize=fontsize, underline=True)


@functools.lru_cache(maxsize=256)
def render_text(text: str, style: Style, file_format: str = 'png') -> bytes:
    font = ImageFont.truetype(str(style.fontpath.resolve()), style.fontsize)
    _,_,w, h = font.getbbox(text)
    if style.underline:
        h += 2
    img = Image.new('RGBA', (w, h), color=(255,255,255,0))
    draw = ImageDraw.Draw(img)
    draw.text((0,0), text, fill=style.color, font=font)
    if style.underline:
        draw.line([(0, h-1), (w, h-1)], fill=style.color)
    buf = io.BytesIO()
    img.save(buf, format=file_format)
    return buf.getvalue()
