# -*- coding: utf-8 -*-
"""Gera o índice `inkarnate_objects.json` — a ponte entre os MapAssets já
importados (miniaturas de 160px) e o catálogo do Inkarnate.

Casamento: MD5 exato da miniatura, e quando o import re-codificou (webp),
semelhança de COSSENO sobre um vetor visual 32x32 (alfa + cinza).

Cada item traz o checksum ATUAL do blob: o rake em produção só mexe no
MapAsset se o que está lá é exatamente o que foi casado aqui.
"""
import json, os, sys, hashlib, base64, collections

SP = os.path.dirname(os.path.abspath(__file__))
ALVO_PX = 512  # menor variante cujo lado maior alcança isso (x8 = nativo)

D = json.load(open(SP + '/stamp-groups.json'))
AS = {a['id']: a for a in D['assets']}
GR = {g['id']: g for g in D['assetGroups']}
packs = json.load(open(SP + '/packs2.json')); packs = packs.get('items') or packs
P = {p['id']: p for p in packs}
styles = json.load(open(SP + '/styles.json')); styles = styles.get('items') or styles
S = {s['id']: s for s in styles}
# catálogo do marketplace (metadados de packs NÃO comprados: organizam, mas não
# rendem imagem HD — arte paga não se baixa)
MKT = {}
if os.path.exists(SP + '/mkt-assets.json'):
    MKT = {int(k): v for k, v in json.load(open(SP + '/mkt-assets.json')).items()}

chks = {}
for r in open(SP + '/obj-checksums.txt'):
    p = r.rstrip('\n').split('|')
    if len(p) >= 2: chks[int(p[0])] = p[1]

def variante(a):
    """URLs da MENOR variante com lado maior >= ALVO_PX (nativo é x8), seguida
    das menores — o rake cai pra próxima se a escolhida passar do teto de 5 MB."""
    sz = (a.get('data') or {}).get('size') or {}
    L = max(sz.get('w') or 0, sz.get('h') or 0)
    imgs = a.get('images') or {}
    escala = (('x1', 8), ('x2', 4), ('x4', 2), ('x8', 1))
    i = next((k for k, (v, d) in enumerate(escala) if (L / d >= ALVO_PX or v == 'x8') and imgs.get(v)), None)
    if i is None:
        return [], 0
    urls = [imgs[v] for v, _ in escala[i::-1] if imgs.get(v)]
    return urls, round(L / escala[i][1])

def metadados(a):
    pk = P.get(a.get('packId')) or {}
    st = S.get(pk.get('sceneStyleId')) or {}
    gid = (a.get('assetGroupIds') or [None])[0]
    g = GR.get(gid) or {}
    cat = (st.get('title') or '').strip()
    grp = (pk.get('title') or '').strip()[:60]
    if not cat or not grp:
        return None
    return {
        'n': (a.get('title') or '').strip()[:80] or None,
        'c': cat, 'g': grp,
        'vg': f'ink-{gid}' if gid else None,
        'vo': a.get('order') if isinstance(a.get('order'), int) else 0,
        'gn': (g.get('title') or '').strip() or None,
    }

itens = []; resumo = collections.Counter()
for m in json.load(open(SP + '/match-owned.json')):
    a = AS.get(m['aid'])
    if not a: continue
    urls, px = variante(a)
    meta = metadados(a)
    it = {'id': m['id'], 'chk': chks.get(m['id']), 'aid': a['id'], 'via': m['via']}
    if urls: it['us'] = urls; it['px'] = px
    if meta: it.update({k: v for k, v in meta.items() if v is not None})
    if not it.get('us') and not meta: continue
    resumo['com-imagem' if urls else 'só-metadado'] += 1
    resumo['com-metadado' if meta else 'sem-metadado'] += 1
    itens.append(it)

for m in json.load(open(SP + '/match-mkt.json')) if os.path.exists(SP + '/match-mkt.json') else []:
    a = MKT.get(m['aid'])
    if not a: continue
    meta = metadados(a)          # organiza; a imagem paga NÃO é baixada
    if not meta: continue
    itens.append({'id': m['id'], 'chk': chks.get(m['id']), 'aid': a['id'], 'via': m['via'],
                  **{k: v for k, v in meta.items() if v is not None}})
    resumo['marketplace-só-metadado'] += 1

# Cluster de variantes com UM item só é ruído na biblioteca: o agrupamento
# vale quando pelo menos dois dos NOSSOS objetos caem no mesmo grupo.
conta = collections.Counter(x['vg'] for x in itens if x.get('vg'))
for x in itens:
    if x.get('vg') and conta[x['vg']] < 2:
        x.pop('vg')
        resumo['grupo-de-um-desfeito'] += 1
resumo['em-grupo-de-variantes'] = sum(1 for x in itens if x.get('vg'))

itens.sort(key=lambda x: x['id'])
saida = {
    'gerado_em': '2026-09-04',
    'fonte': 'catálogo Inkarnate (api2.inkarnate.com) casado por MD5 + semelhança visual',
    'alvo_px': ALVO_PX,
    'total': len(itens),
    'itens': itens,
}
dest = sys.argv[1] if len(sys.argv) > 1 else SP + '/inkarnate_objects.json'
json.dump(saida, open(dest, 'w'), ensure_ascii=False, separators=(',', ':'))
print(f'{len(itens)} itens -> {dest} ({os.path.getsize(dest)/1024:.0f} KB)')
for k, v in resumo.most_common(): print(f'  {k}: {v}')
