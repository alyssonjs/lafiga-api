# -*- coding: utf-8 -*-
"""Gera `inkarnate_catalog.json` — o catálogo INTEIRO que esta conta acessa,
pronto p/ virar biblioteca de objetos.

A conversão anterior só melhorava o que já tínhamos importado (2.783 registros,
~18% do catálogo). O que faltava não era qualidade: eram os itens. "Core" de
Fantasy Battlemaps tem 353 assets; a nossa tinha 24.

Um item por asset do catálogo, com o metadado que organiza a biblioteca:
estilo de cena → pack → grupo de variantes → ordem.
"""
import json, os, sys, collections

SP = os.path.dirname(os.path.abspath(__file__))
ALVO_PX = 512

D = json.load(open(SP + '/stamp-groups.json'))
packs = json.load(open(SP + '/packs2.json')); packs = packs.get('items') or packs
P = {p['id']: p for p in packs}
styles = json.load(open(SP + '/styles.json')); styles = styles.get('items') or styles
S = {s['id']: s for s in styles}

def variante(a):
    sz = (a.get('data') or {}).get('size') or {}
    L = max(sz.get('w') or 0, sz.get('h') or 0)
    imgs = a.get('images') or {}
    escala = (('x1', 8), ('x2', 4), ('x4', 2), ('x8', 1))
    i = next((k for k, (v, d) in enumerate(escala) if (L / d >= ALVO_PX or v == 'x8') and imgs.get(v)), None)
    if i is None: return []
    # escolhida + UM degrau de recuo (teto de 5 MB do model)
    return [imgs[v] for v, _ in escala[i::-1] if imgs.get(v)][:2]

itens = []; resumo = collections.Counter(); usados = collections.Counter()
for a in D['assets']:
    pk = P.get(a.get('packId')) or {}
    st = S.get(pk.get('sceneStyleId')) or {}
    cat = (st.get('title') or '').strip()
    grp = (pk.get('title') or '').strip()[:60]
    if not cat or not grp:
        resumo['sem estilo/pack'] += 1; continue
    if not pk.get('official'):
        resumo['pack não-oficial (fora)'] += 1; continue
    urls = variante(a)
    if not urls:
        resumo['sem imagem'] += 1; continue
    gid = (a.get('assetGroupIds') or [None])[0]
    # Nome ÚNICO por (categoria, pack): a idempotência do rake é por nome, e o
    # catálogo repete título entre variantes ("Palm Tree" cinco vezes).
    base = (a.get('title') or '').strip()[:70] or 'Objeto'
    chave = (cat, grp, base.lower())
    usados[chave] += 1
    nome = base if usados[chave] == 1 else f'{base} {usados[chave]}'
    it = {'aid': a['id'], 'n': nome[:80], 'c': cat, 'g': grp, 'us': urls,
          'vo': a.get('order') if isinstance(a.get('order'), int) else 0}
    if gid: it['vg'] = f'ink-{gid}'
    # SOMBRA por stamp (regra do editor deles): 'none' = arte com sombra já
    # pintada (morros, penhascos, árvores grandes) — o mapa NÃO põe outra;
    # 'custom' = receita própria (blur/offset/intensidade em UNIDADES de cena,
    # 200 por célula); o resto cai no padrão do estilo e fica FORA do item.
    data = a.get('data') or {}
    if data.get('shadow') == 'none':
        it['sh'] = 'none'
    elif data.get('shadow') == 'custom' and (data.get('customShadow') or {}).get('enabled'):
        cs = data['customShadow']
        it['sh'] = {'b': cs.get('blurRadius') or 0, 'x': cs.get('offsetX') or 0,
                    'y': cs.get('offsetY') or 0, 'i': cs.get('intensity') or 0}
    itens.append(it); resumo['itens'] += 1

conta = collections.Counter(x['vg'] for x in itens if x.get('vg'))
for x in itens:
    if x.get('vg') and conta[x['vg']] < 2: x.pop('vg')
resumo['em grupo de variantes'] = sum(1 for x in itens if x.get('vg'))
resumo['sombra none'] = sum(1 for x in itens if x.get('sh') == 'none')
resumo['sombra custom'] = sum(1 for x in itens if isinstance(x.get('sh'), dict))

itens.sort(key=lambda x: (x['c'], x['g'], x['vo'], x['aid']))
dest = sys.argv[1] if len(sys.argv) > 1 else SP + '/inkarnate_catalog.json'
json.dump({'gerado_em': '2026-09-04', 'alvo_px': ALVO_PX, 'total': len(itens), 'itens': itens},
          open(dest, 'w'), ensure_ascii=False, separators=(',', ':'))
print(f'{len(itens)} itens -> {dest} ({os.path.getsize(dest)/1024/1024:.1f} MB)')
for k, v in resumo.most_common(): print(f'  {k}: {v}')
print('  packs:', len({(x['c'], x['g']) for x in itens}), '| categorias:', len({x['c'] for x in itens}))
