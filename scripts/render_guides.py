#!/usr/bin/env python3
import json,pathlib,html
from reportlab.platypus import SimpleDocTemplate,Paragraph,Spacer,PageBreak
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
ROOT=pathlib.Path(__file__).resolve().parents[1]
out=ROOT/'output/pdf/ARANK_Planner_Manuals.pdf';out.parent.mkdir(parents=True,exist_ok=True)
d=json.loads((ROOT/'docs/Help.json').read_text())
for n,f in [('D','DejaVuSans.ttf'),('DB','DejaVuSans-Bold.ttf')]:pdfmetrics.registerFont(TTFont(n,'/usr/share/fonts/truetype/dejavu/'+f))
pdfmetrics.registerFontFamily('D',normal='D',bold='DB',italic='D',boldItalic='DB')
body=ParagraphStyle('body',fontName='D',fontSize=10.4,leading=16,spaceAfter=12,textColor=colors.HexColor('#26384b'))
h=ParagraphStyle('h',parent=body,fontName='DB',fontSize=22,leading=27,spaceAfter=22)
small=ParagraphStyle('small',parent=body,fontSize=9,leading=14,textColor=colors.HexColor('#52718b'))
story=[Spacer(1,85),Paragraph('ARANK<br/>PLANNER',ParagraphStyle('cover',parent=h,fontSize=39,leading=46)),Paragraph('Три руководства',h),Paragraph('Пользователь · Администратор · Разработчик',body),Spacer(1,30),Paragraph('Версия приложения 0.10.6<br/>Формат OpenSchedule 0.6<br/>Редакция справки: ноябрь 2026',body),Spacer(1,30),Paragraph('Подготовлено по исходному коду. Новая встроенная справка требует принятия изменений и пересборки приложения. Сборка и запуск на macOS в этой среде не проверены.',small),PageBreak(),Paragraph('Содержание',h)]
for i,s in enumerate(d['sections']):story.append(Paragraph(f'{i+3:02} · {html.escape(s["group"])} / {html.escape(s["title"])}',small))
for s in d['sections']:
 story += [PageBreak(),Paragraph(s['group'].upper(),small),Paragraph(html.escape(s['title']),h)]
 for p in s['paragraphs']:story.append(Paragraph(html.escape(p),body))
def footer(c,doc):
 c.setStrokeColor(colors.HexColor('#c6d8e7'));c.line(45,43,550,43);c.setFont('D',8);c.setFillColor(colors.HexColor('#52718b'));c.drawString(45,29,'ARANK Planner · Руководства 0.10.6');c.drawRightString(550,29,str(doc.page))
SimpleDocTemplate(str(out),pagesize=(595.28,841.89),rightMargin=45,leftMargin=45,topMargin=46,bottomMargin=61,title='ARANK Planner — три руководства',author='Руслан').build(story,onFirstPage=footer,onLaterPages=footer)
print(out)
