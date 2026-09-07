#!/usr/bin/env python3
"""Textos das cenas do Inkarnate → tokens de TEXTO do Lafiga.

O import original trouxe terreno e objetos e deixou os TEXTOS para trás (604
nas 32 cenas). Este gerador lê o censo cru (textos_por_cena.json, produzido a
partir do `commandsPaginated`) e escreve `inkarnate_textos.json` no modelo do
nosso `MapToken` — o rake `inkarnate:texts_import` só anexa.

ÂNCORA (medida contra os previews renderizados, recortes `ancora*.png` 06/09):
x da entidade = CENTRO horizontal do texto; y = BASELINE da ÚLTIMA linha — o
bloco cresce para CIMA da âncora ("Casa dos/Lenkins": a linha corta a baseline
de "Lenkins"; "Pedreira", 1 linha, assenta na própria). O nosso token guarda o
canto sup-esq: topLeft = (x − w/2, y − (n−1)·lineHeight·tam − 0.8·tam).
Com alinhamento central (todos os 604), o CENTRO independe da largura estimada
— o erro da estimativa não desloca o texto.

Estilo esparso = padrões do app deles: IM Fell English SC, branco, contorno
preto 75% de largura 0.1, central, lineHeight 1.

Uso: python3 gerar_inkarnate_textos.py <textos_por_cena.json> <destino.json>
"""
import json
import sys

ASCENT = 0.8            # baseline → topo da caixa (fração do tamanho)


def cor_hex(c):
    if not c:
        return '#ffffff'
    return '#%02x%02x%02x' % (int(c.get('r', 255)), int(c.get('g', 255)), int(c.get('b', 255)))


def cor_rgba(c):
    if not c:
        return 'rgba(0,0,0,0.75)'
    return f"rgba({int(c.get('r', 0))},{int(c.get('g', 0))},{int(c.get('b', 0))},{c.get('a', 1)})"


def largura_estimada(texto, tamanho, espaco):
    linhas = texto.split('\n')
    maior = max((len(l) for l in linhas), default=1)
    return max(0.2, maior * tamanho * 0.55 * (1 + espaco))


def converte(sid, cena):
    cel = float(cena['celula_u'])
    saida = []
    avisos = []
    for e in cena['textos']:
        st = e.get('textStyle') or {}
        texto = (e.get('text') or '').rstrip()
        if not texto:
            continue
        tamanho = float(st.get('fontSize', 72)) / cel
        linhas = texto.split('\n')
        lh = float(st.get('lineHeight', 1))
        h = tamanho * 0.95 + lh * tamanho * (len(linhas) - 1)
        espaco = float(st.get('letterSpacing', 0)) / max(st.get('fontSize', 72), 1)
        w = largura_estimada(texto, tamanho, espaco)
        cx = float(e['x']) / cel
        y_base = float(e['y']) / cel
        contorno = st.get('outline') or {}
        alinh = st.get('horizontalAlignment', 'center')
        # ⚠️ A âncora é o CENTRO mesmo com align left/right (medido no preview:
        # a cruz corta o meio de "Fosterville", que é left). O alinhamento só
        # rege as linhas DENTRO do bloco — em linha única é invisível, e forçar
        # centro imuniza contra o erro da largura estimada.
        if len(linhas) == 1:
            alinh = 'center'
        elif alinh != 'center':
            avisos.append(f'{sid}: "{texto[:20]}" multilinha {alinh} — leve desvio pela largura estimada')
        if st.get('curve'):
            avisos.append(f'{sid}: "{texto[:20]}" tem curve={st["curve"]} (não renderizamos curva)')
        tok = {
            'id': f'ink-text-{sid}-{e["entityId"]}',
            'name': linhas[0][:40],
            'color': cor_hex(st.get('color')),
            'x': round(cx - w / 2, 4),
            # baseline da ÚLTIMA linha → topo: sobe as (n−1) linhas e o ascent
            'y': round(y_base - (len(linhas) - 1) * lh * tamanho - ASCENT * tamanho, 4),
            'size': 1,
            'isObject': True,
            'objectWidth': round(w, 4),
            'objectHeight': round(h, 4),
            'sublayer': min(int(e.get('z', 3) or 3), 9),
            'textContent': texto,
            'textFont': st.get('fontFamily') or 'IM Fell English SC',
            'textSizeCells': round(tamanho, 4),
            'textColor': cor_hex(st.get('color')),
            'textAlign': alinh,
        }
        if e.get('angle'):
            tok['rotation'] = float(e['angle'])
        if st.get('isBold'):
            tok['textBold'] = True
        if st.get('isItalic'):
            tok['textItalic'] = True
        if contorno.get('enabled', True):
            tok['textOutlineWidth'] = float(contorno.get('size', 0.1))
            tok['textOutlineColor'] = cor_rgba(contorno.get('color'))
        if lh != 1:
            tok['textLineHeight'] = lh
        if espaco:
            tok['textSpacing'] = round(espaco, 4)
        op = float(e.get('opacity', 1))
        if op < 1:
            tok['textOpacity'] = op
        saida.append(tok)
    return saida, avisos


def main():
    origem, destino = sys.argv[1], sys.argv[2]
    censo = json.load(open(origem))
    cenas = {}
    todos_avisos = []
    total = 0
    for sid, cena in censo.items():
        toks, avisos = converte(sid, cena)
        todos_avisos += avisos
        if toks:
            cenas[sid] = {'titulo': cena['titulo'], 'tokens': toks}
            total += len(toks)
    json.dump({'gerado_em': __import__('datetime').date.today().isoformat(),
               'total': total, 'cenas': cenas},
              open(destino, 'w'), ensure_ascii=False, indent=1)
    print(f'== {total} textos em {len(cenas)} cenas → {destino}')
    for a in todos_avisos:
        print('  ⚠️', a)


if __name__ == '__main__':
    main()
