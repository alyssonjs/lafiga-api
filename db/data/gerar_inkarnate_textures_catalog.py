# -*- coding: utf-8 -*-
"""Gera `inkarnate_textures_catalog.json` — TODAS as texturas que a conta acessa.

Mesma história dos objetos: a biblioteca tinha o recorte que foi importado à
mão (243) contra 707 no catálogo. E a CATEGORIA passa a ser o estilo de cena,
não "Terrenos": com 54 packs numa categoria só, o "Core" de Fantasy World e o
"Core" de Watercolor Cities colidiriam na mesma subcategoria.
"""
import json, os, sys, collections

SP = os.path.dirname(os.path.abspath(__file__))
ALVO_PX = 512

d = json.load(open(SP + '/cat2-tex.json'))
A = d.get('assets') or d.get('items') or d
GR = {g['id']: g for g in (d.get('assetGroups') or [])}
packs = json.load(open(SP + '/packs2.json')); packs = packs.get('items') or packs
P = {p['id']: p for p in packs}
styles = json.load(open(SP + '/styles.json')); styles = styles.get('items') or styles
S = {s['id']: s for s in styles}

def variante(a):
    sz = (a.get('data') or {}).get('size') or {}
    L = max(sz.get('w') or 0, sz.get('h') or 0)
    imgs = a.get('images') or {}
    escala = (('x1', 8), ('x2', 4), ('x4', 2), ('x8', 1))
    i = next((k for k, (v, dv) in enumerate(escala) if (L / dv >= ALVO_PX or v == 'x8') and imgs.get(v)), None)
    if i is None:
        # sem `data.size` utilizável: cai na maior que existir
        for v, _ in reversed(escala):
            if imgs.get(v): return [imgs[v]]
        return []
    return [imgs[v] for v, _ in escala[i::-1] if imgs.get(v)][:2]

itens = []; resumo = collections.Counter(); usados = collections.Counter()
for a in A:
    pk = P.get(a.get('packId')) or {}
    st = S.get(pk.get('sceneStyleId')) or {}
    cat = (st.get('title') or '').strip()
    grp = (pk.get('title') or '').strip()[:60]
    if not cat or not grp:
        resumo['sem estilo/pack'] += 1; continue
    if not pk.get('official'):
        resumo['pack não-oficial'] += 1; continue
    urls = variante(a)
    if not urls:
        resumo['sem imagem'] += 1; continue
    base = (a.get('title') or '').strip()[:70] or 'Textura'
    chave = (cat, grp, base.lower())
    usados[chave] += 1
    nome = base if usados[chave] == 1 else f'{base} {usados[chave]}'
    gid = (a.get('assetGroupIds') or [None])[0]
    it = {'aid': a['id'], 'n': nome[:80], 'c': cat, 'g': grp, 'us': urls,
          'vo': a.get('order') if isinstance(a.get('order'), int) else 0}
    if gid: it['vg'] = f'ink-{gid}'
    itens.append(it); resumo['itens'] += 1

conta = collections.Counter(x['vg'] for x in itens if x.get('vg'))
for x in itens:
    if x.get('vg') and conta[x['vg']] < 2: x.pop('vg')
resumo['em grupo de variantes'] = sum(1 for x in itens if x.get('vg'))

itens.sort(key=lambda x: (x['c'], x['g'], x['vo'], x['aid']))
dest = sys.argv[1] if len(sys.argv) > 1 else SP + '/inkarnate_textures_catalog.json'
json.dump({'gerado_em': '2026-09-04', 'alvo_px': ALVO_PX, 'total': len(itens), 'itens': itens},
          open(dest, 'w'), ensure_ascii=False, separators=(',', ':'))
print(f'{len(itens)} itens -> {dest} ({os.path.getsize(dest)/1024:.0f} KB)')
for k, v in resumo.most_common(): print(f'  {k}: {v}')
print('  categorias:', len({x['c'] for x in itens}), '| packs:', len({(x['c'], x['g']) for x in itens}))
