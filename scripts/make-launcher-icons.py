#!/usr/bin/env python3
"""从 assets/logo.png 生成 Android 启动图标。

为什么自己写而不用 flutter_launcher_icons：那个包要进 dev_dependencies，
还要跑一次 build_runner 才出图，而这件事一共就做一次。自己生成还能精确
控制安全区——自适应图标会被各家启动器裁成圆形、方形、水滴形，图形超出
66% 安全区就会被切掉一块。

两套图标用的是**同一张原图的不同裁法**，原因见 main() 里的注释。

用法：python3 scripts/make-launcher-icons.py
需要 Pillow：pip install Pillow
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'assets', 'logo.png')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')

# 传统图标的边长（图标资源按密度分目录，这里的数值就是像素）
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
# 自适应图标固定 108dp 画布
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

# 自适应图标的安全区是 108dp 里居中的 66dp。留一点余量，取 62%。
SAFE_RATIO = 0.62

# 原图里那块圆角卡片的范围（量出来的，原图 1254×1254）
CARD_BOX = (120, 115, 1136, 1131)

# 抠图时判定「这片算背景」的阈值。
#
# 原图自带一块近乎纯白的圆角卡片当底（像素值 254，和画布外的白几乎没差），
# 阈值低了它会留下一圈锯齿边。地图最浅的蓝是 (191,216,246)、与白差 63，
# 所以 55 能吃掉卡片又不会啃到图形本身。
BACKDROP_THRESHOLD = 55

# 自适应图标的背景色。
#
# 用纯白而不是卡片那种淡蓝：图形底部那块淡蓝的「地面」是 logo 自带的，
# 背景只要不是纯白，就会和它透出一圈色差，看着像图标里还嵌了张卡片。
BG_SOLID = '#FFFFFF'


def cutout(im):
    """抠出图形本身，外围透明，内部的白色（地图上的路）保留。

    不能简单地把白色全部变透明——地图中间那条白色的路会被一起抠掉，
    图案就破了。所以从四个角 flood fill，只吃掉与画布边界连通的那片白。
    """
    w, h = im.size
    # flood fill 要在 RGB 上做，填一个画面里不存在的洋红当标记色
    rgb = im.convert('RGB')
    marker = (255, 0, 255)
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        ImageDraw.floodfill(rgb, corner, marker, thresh=BACKDROP_THRESHOLD)

    out = im.copy()
    src = rgb.load()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y] == marker:
                dst[x, y] = (0, 0, 0, 0)
    return out.crop(out.getbbox())


def fitted(art, canvas, ratio):
    """把图形等比缩放进 canvas×canvas 的透明画布，占边长的 ratio。"""
    box = int(canvas * ratio)
    scaled = art.copy()
    scaled.thumbnail((box, box), Image.LANCZOS)
    layer = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    layer.paste(
        scaled,
        ((canvas - scaled.width) // 2, (canvas - scaled.height) // 2),
        scaled,
    )
    return layer


def write(img, density, name):
    folder = os.path.join(RES, 'mipmap-%s' % density)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name)
    img.save(path, 'PNG')
    print('  %s (%dx%d)' % (os.path.relpath(path, ROOT), img.width, img.height))


def main():
    im = Image.open(SOURCE).convert('RGBA')

    # 传统图标：原图那块圆角卡片本身就是一个做好的图标，整块裁出来用。
    # 不要另画底板再把图形贴上去——图形底部那块淡蓝的「地面」是卡片的一
    # 部分，分不开，套两层就成了「卡片里再套一张卡片」。
    card = im.crop(CARD_BOX)
    print('卡片 %dx%d' % card.size)
    print('传统图标：')
    for density, size in LEGACY.items():
        write(card.resize((size, size), Image.LANCZOS), density, 'ic_launcher.png')

    # 自适应图标反过来：启动器会自己把图标裁成圆/方/水滴，外框由它提供，
    # 所以前景只放图形、不要卡片，否则就是圆里套个方。
    art = cutout(im)
    print('图形 %dx%d' % art.size)
    print('自适应图标前景：')
    for density, size in ADAPTIVE.items():
        write(fitted(art, size, SAFE_RATIO), density, 'ic_launcher_foreground.png')

    # 没有 <monochrome>：主题图标要的是单色剪影，直接把这张彩图塞进去
    # 会被系统统一上色、糊成一团。等有正经的单色稿再补。
    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon '
            'xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n'
        )
    values = os.path.join(RES, 'values')
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, 'ic_launcher_background.xml'), 'w') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            '    <color name="ic_launcher_background">%s</color>\n'
            '</resources>\n' % BG_SOLID
        )
    print('自适应图标描述文件与背景色已写入')


if __name__ == '__main__':
    main()
