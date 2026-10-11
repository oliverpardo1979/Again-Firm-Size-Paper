"""Render the editorial audit and a complete source diff against its recorded base."""

import difflib
import html
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, KeepTogether, PageBreak, Table, TableStyle

ROOT = Path(__file__).resolve().parents[1]
SPEC = json.loads((ROOT / "editorial/audit_2026-10-10.json").read_text(encoding="utf-8"))
OUT = ROOT / "build"
OUT.mkdir(exist_ok=True)
BASE = SPEC["base_commit"]


def original(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT).decode("utf-8")


def normalized(text):
    return re.sub(r"\s+", " ", text.replace("\\\\ref", "\\ref").replace("\\\\exp", "\\exp")
                  .replace("\\\\hat", "\\hat").replace("\\\\widehat", "\\widehat")).strip()


def plain(text):
    text = normalized(text)
    text = re.sub(r"\\ref\{([^}]+)\}", lambda m: m[1], text)
    text = text.replace("``", '"').replace("''", '"').replace("--", "-")
    return html.escape(text)


for change in SPEC["corrections"]:
    before = normalized(original(change["file"]))
    after = normalized((ROOT / change["file"]).read_text(encoding="utf-8"))
    assert normalized(change["before"]) in before, ("Original excerpt not found", change)
    assert normalized(change["after"]) in after, ("Revised excerpt not found", change)


def inputs(path="main.tex", seen=None):
    seen = set() if seen is None else seen
    if path in seen:
        return []
    seen.add(path)
    text = (ROOT / path).read_text(encoding="utf-8")
    paths = [path]
    for child in re.findall(r"\\input\{([^}]+)\}", text):
        paths.extend(inputs(child if child.endswith(".tex") else child + ".tex", seen))
    return paths


paths = inputs()
diff = []
for path in paths + ["manuscript_no_author_details.tex", "Paper/references.bib", "replication/build_counterfactual_tables.py"]:
    old = original(path)
    new = (ROOT / path).read_text(encoding="utf-8")
    diff.extend(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile=f"{BASE[:7]}/{path}", tofile=path))
(OUT / "editorial-audit-2026-10-10.patch").write_text("".join(diff), encoding="utf-8")

font_root = Path("C:/Windows/Fonts")
pdfmetrics.registerFont(TTFont("Audit", str(font_root / "arial.ttf")))
pdfmetrics.registerFont(TTFont("AuditBold", str(font_root / "arialbd.ttf")))
pdfmetrics.registerFontFamily("Audit", normal="Audit", bold="AuditBold", italic="Audit", boldItalic="AuditBold")
styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="BodyAudit", fontName="Audit", fontSize=10, leading=14, spaceAfter=7))
styles.add(ParagraphStyle(name="SmallAudit", fontName="Audit", fontSize=8.3, leading=11, spaceAfter=5))
styles.add(ParagraphStyle(name="HeadingAudit", fontName="AuditBold", fontSize=13, leading=17, spaceBefore=12, spaceAfter=8, keepWithNext=True))
styles.add(ParagraphStyle(name="CaseAudit", fontName="AuditBold", fontSize=10.3, leading=14, spaceBefore=9, spaceAfter=6, keepWithNext=True))
styles.add(ParagraphStyle(name="TitleAudit", fontName="AuditBold", fontSize=23, leading=28, spaceAfter=16))


def p(text, style="BodyAudit"):
    return Paragraph(text, styles[style])


story = [p("Auditoría editorial del manuscrito", "TitleAudit"),
         p("Beyond Formality: The Firm-Size Wage Premium in Colombia"),
         p("10 de octubre de 2026 · Base revisada: " + BASE[:7], "SmallAudit"),
         p("Alcance y criterio", "HeadingAudit"),
         p("Lectura secuencial del abstract, las siete secciones, el apéndice, las leyendas y notas de las tablas y figuras, y la declaración de disponibilidad. La evaluación se hizo con cuatro preguntas. Las frases que ya cumplían el criterio se conservaron."),
         p("<b>S. Sentido:</b> ¿la frase formula una afirmación concreta y defendible?<br/>"
           "<b>T. Terminología:</b> ¿cada término aporta un significado claro?<br/>"
           "<b>R. Retrospectiva:</b> ¿el lector dispone de los antecedentes necesarios?<br/>"
           "<b>P. Prospectiva:</b> ¿la afirmación coincide con las ecuaciones, tablas e interpretaciones posteriores?"),
         p(f"Este reporte agrupa {len(SPEC['corrections'])} correcciones o conjuntos de correcciones. Los extractos permiten localizar el cambio sin reproducir párrafos completos. Cuando se añadió una definición, el extracto anterior identifica el lugar donde faltaba. El archivo de diferencias que acompaña al reporte contiene todos los cambios de fuente."),
         p("No se cambiaron los coeficientes, las muestras de estimación, las hipótesis econométricas ni los resultados numéricos principales. La última frase del abstract se preservó literalmente. Las modificaciones de prosa se comparten entre el manuscrito con autores y la versión anónima."),
         p("Hallazgo pendiente de reconciliación numérica", "HeadingAudit"),
         p("<b>Confianza: High sobre la discrepancia, no sobre su origen.</b> La tabla de interacciones simplificada y la primera columna de las tablas nuevas describen los mismos controles y reportan el mismo tamaño muestral. Sus coeficientes, sin embargo, no coinciden exactamente. Por ejemplo, el coeficiente informal de 11–19 es 0.409 en la tabla simplificada y 0.408 en la nueva. Para 51–100 es 0.410 frente a 0.409. Cambiar la agrupación de errores estándar no explica una diferencia en coeficientes."),
         p("Una reestimación de control con la base disponible reprodujo los ocho coeficientes informales de la columna (1) de las tablas nuevas. No reprodujo exactamente los valores antiguos, con una discrepancia máxima de alrededor de 0.0015 puntos logarítmicos. No se determinó en esta auditoría si el origen es una versión anterior de los datos o de la ejecución. No se sustituyeron las cifras de manera aislada. Conviene regenerar conjuntamente las tablas y figuras de comparación antes de cerrar otra versión para envío."),
         p("Esta revisión editorial, por tanto, no equivale a certificar una reproducción integral de todas las regresiones. Tampoco convierte en evidencia causal las asociaciones que ya reportaba el documento."),
         PageBreak(), p("Registro de correcciones", "HeadingAudit")]

for i, c in enumerate(SPEC["corrections"], 1):
    block = [p(f"{i:02d}. {html.escape(c['section'])} · Criterios {c['criteria']}", "CaseAudit"),
             p("<b>Antes:</b> “" + plain(c["before"]) + "”", "SmallAudit"),
             p("<b>Ahora:</b> “" + plain(c["after"]) + "”", "SmallAudit"),
             p(html.escape(c["reason"].replace("retrans formacion", "retransformacion"))),
             p(html.escape(c["file"]), "SmallAudit")]
    story.append(KeepTogether(block))

story.extend([PageBreak(), p("Comprobaciones y límites", "HeadingAudit"),
 p("<b>Contenido numérico contrastado.</b> Se contrastaron los coeficientes, errores estándar y estrellas de las tres tablas del modelo preferido con sus archivos agregados. Se reconstruyeron 24 cambios contrafactuales a partir de los 18 grupos tamaño-formalidad. Se verificaron las razones sectoriales 101+/Solo, las razones por sexo y los porcentajes educativos y ocupacionales citados en los cambios."),
 p("<b>Reestimación selectiva.</b> Se reestimó el modelo de interacciones con efectos sector-año para investigar el desfase descrito al comienzo. La revisión de la base confirmó 437 observaciones en la categoría educativa residual y 139 celdas sector-departamento-año con una sola observación. No se reestimó en este turno toda la batería dinámica, polinómica o de elasticidades."),
 p("<b>Fuentes consultadas.</b> Se comprobó el cambio de recolección de 2020 en el comunicado de DANE, la distinción entre firmas y establecimientos en Diegmann et al., el objeto metodológico de Terza, el papel de empresas grandes en Chen, y los ejercicios de reasignación en las páginas 43–47 y 73–74 del ESPE 108. Se mantuvo Ecuador para El Badaoui et al. (2010): la versión publicada utiliza Ecuador, aunque una versión de trabajo anterior usa Sudáfrica. La nueva frase especifica salarios netos de impuestos. Esta es una comprobación focalizada de las afirmaciones intervenidas, no una nueva auditoría bibliográfica completa."),
 p("<b>Una etiqueta gráfica heredada.</b> La imagen de kernels conserva el rótulo interno ‘statutory hourly minimum’. El texto, la leyenda externa y la nota de la tabla aclaran que se trata de una conversión aproximada del mínimo mensual mediante 45 horas semanales. No se cambiaron las densidades ni se regeneró su suavizamiento. Para reutilizar la imagen fuera del paper conviene actualizar también el rótulo interno."),
 p("<b>Protecciones.</b> Se preservaron los cambios del autor, la última frase del abstract y la estructura principal del documento. No se modificó el repositorio de datos con trabajo ajeno pendiente. No se alteraron las presentaciones."),
 p("Fuentes primarias", "HeadingAudit")])
sources = [
 ("DANE: continuidad de la GEIH, 30 de abril de 2020", "https://www.dane.gov.co/files/investigaciones/boletines/ech/ech/CP_ajustesmetodologicos_covid19_mar_20.pdf"),
 ("Diegmann, Müller y Schoefer (2026)", "https://www.nber.org/papers/w35265"),
 ("Chen (2026)", "https://onlinelibrary.wiley.com/doi/10.3982/ECTA22110"),
 ("Terza (1987)", "https://doi.org/10.1016/0304-4076(87)90013-3"),
 ("El Badaoui, Strobl y Walsh (2010): versión aceptada", "https://researchrepository.ucd.ie/bitstreams/9fc92c71-5d0f-4fb3-b8ec-5d4b757f4ffc/download"),
 ("Otero-Cortés et al.: ESPE 108", "https://repositorio.banrep.gov.co/bitstream/handle/20.500.12134/11110/Espe108.pdf")]
for title, url in sources:
    story.append(p(f'<link href="{html.escape(url)}" color="#185B78">{html.escape(title)}</link>', "SmallAudit"))
story.extend([p("Cobertura del manuscrito", "HeadingAudit"),
 p("Se revisaron los siguientes archivos activos, en el orden en que se incorporan al documento. Los cambios de leyendas y notas no requieren modificar las tablas numéricas.")])
for path in paths:
    story.append(p(html.escape(path), "SmallAudit"))


def footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#C6CDD0"))
    canvas.line(42, 36, doc.pagesize[0]-42, 36)
    canvas.setFont("Audit", 8)
    canvas.setFillColor(colors.HexColor("#47545C"))
    canvas.drawString(42, 23, "Auditoría editorial · 10 octubre 2026")
    canvas.drawRightString(doc.pagesize[0]-42, 23, str(doc.page))
    canvas.restoreState()


doc = SimpleDocTemplate(str(OUT / "editorial-audit-2026-10-10.pdf"),
                        pagesize=(8.5*inch,11*inch), rightMargin=46, leftMargin=46,
                        topMargin=42,bottomMargin=48,
                        title="Auditoria editorial - Beyond Formality", author="Editorial audit")
doc.build(story,onFirstPage=footer,onLaterPages=footer)
print(f"Verified {len(SPEC['corrections'])} before/after excerpt pairs and rendered audit report.")
print(f"Coverage: {len(paths)} active LaTeX files. Complete patch saved alongside PDF.")
