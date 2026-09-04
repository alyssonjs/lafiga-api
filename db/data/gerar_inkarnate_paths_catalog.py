# -*- coding: utf-8 -*-
"""Gera `inkarnate_paths_catalog.json` — os caminhos/muros do catálogo.

⚠️ Um `path-asset` do Inkarnate não tem imagem própria: é uma RECEITA que
aponta para outros assets — `stampStroke.strokeAssetId` é o tile que se repete
ao longo da linha e `capAssetId` é a ponta. Por isso o índice resolve a receita
e guarda a URL do TILE (que é o que a ferramenta desenha), mais a da ponta.

366 dos 408 resolvem: 20 são traço de COR (sem tile) e 22 apontam para um stamp
que a API não serve p/ esta conta.
"""
import json, os, sys, collections

SP = os.path.dirname(os.path.abspath(__file__))
ALVO_PX = 1024   # tiles de caminho são LONGOS (3054x464): pede mais que um objeto

paths = json.load(open(SP + '/cat2-path-asset.json'))['assets']
ST = {a['id']: a for a in json.load(open(SP + '/stamp-groups.json'))['assets']}
packs = json.load(open(SP + '/packs2.json')); packs = packs.get('items') or packs
P = {p['id']: p for p in packs}
styles = json.load(open(SP + '/styles.json')); styles = styles.get('items') or styles
S = {s['id']: s for s in styles}

def urls(a):
    sz = (a.get('data') or {}).get('size') or {}
    L = max(sz.get('w') or 0, sz.get('h') or 0)
    imgs = a.get('images') or {}
    escala = (('x1', 8), ('x2', 4), ('x4', 2), ('x8', 1))
    i = next((k for k, (v, d) in enumerate(escala) if (L / d >= ALVO_PX or v == 'x8') and imgs.get(v)), None)
    if i is None:
        for v, _ in reversed(escala):
            if imgs.get(v): return [imgs[v]], sz
        return [], sz
    return [imgs[v] for v, _ in escala[i::-1] if imgs.get(v)][:2], sz

itens = []; resumo = collections.Counter(); usados = collections.Counter()
for a in paths:
    dt = a.get('data') or {}
    ss = dt.get('stampStroke') or {}
    if dt.get('strokeType') != 'texture':
        resumo['traço de COR (sem tile)'] += 1; continue
    tile = ST.get(ss.get('strokeAssetId'))
    if not tile:
        resumo['tile fora do catálogo servido'] += 1; continue
    pk = P.get(a.get('packId')) or {}
    st = S.get(pk.get('sceneStyleId')) or {}
    cat = (st.get('title') or '').strip(); grp = (pk.get('title') or '').strip()[:60]
    if not cat or not grp:
        resumo['sem estilo/pack'] += 1; continue
    us, sz = urls(tile)
    if not us:
        resumo['tile sem imagem'] += 1; continue

    base = (a.get('title') or '').strip()[:70] or 'Caminho'
    chave = (cat, grp, base.lower())
    usados[chave] += 1
    nome = base if usados[chave] == 1 else f'{base} {usados[chave]}'
    it = {'aid': a['id'], 'n': nome[:80], 'c': cat, 'g': grp, 'us': us,
          'vo': a.get('order') if isinstance(a.get('order'), int) else 0,
          # proporção do tile: a ferramenta repete na horizontal e a altura
          # define a largura natural do traço
          'w': sz.get('w') or 0, 'h': sz.get('h') or 0}
    cap = ST.get(ss.get('capAssetId'))
    if cap:
        cu, csz = urls(cap)
        if cu:
            it['cap'] = cu[0]
            it['cw'] = csz.get('w') or 0
            it['ch'] = csz.get('h') or 0
            resumo['com ponta'] += 1
    itens.append(it); resumo['itens'] += 1

itens.sort(key=lambda x: (x['c'], x['g'], x['vo'], x['aid']))
dest = sys.argv[1] if len(sys.argv) > 1 else SP + '/inkarnate_paths_catalog.json'
json.dump({'gerado_em': '2026-09-04', 'alvo_px': ALVO_PX, 'total': len(itens), 'itens': itens},
          open(dest, 'w'), ensure_ascii=False, separators=(',', ':'))
print(f'{len(itens)} itens -> {dest} ({os.path.getsize(dest)/1024:.0f} KB)')
for k, v in resumo.most_common(): print(f'  {k}: {v}')
print('  categorias:', len({x['c'] for x in itens}), '| packs:', len({(x['c'], x['g']) for x in itens}))
