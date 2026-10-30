from PIL import Image, ImageDraw
import os, glob
files = sorted(glob.glob('audit/shots/theme_*.png'))
tw, th = 260, 563
cols, rows = 3, 3
sheet = Image.new('RGB', (cols*tw, rows*(th+22)), (18,18,20))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert('RGB').resize((tw, th))
    x, y = (i % cols)*tw, (i // cols)*(th+22)
    sheet.paste(im, (x, y+22))
    d.text((x+6, y+5), os.path.basename(f).replace('theme_','').replace('.png',''), fill=(230,230,235))
sheet.save('audit/shots/contact_sheet.png')
print('ok', sheet.size)
