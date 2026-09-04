# -*- coding: utf-8 -*-
"""Regenera `inkarnate_objects.json` contra o estado ATUAL de produção.

O índice anterior nasceu de um dump com 1.962 objetos; produção tem 3.836 —
quase metade da biblioteca entrou depois e nunca passou pelo casamento. Aqui os
blobs vêm do próprio prod (leitura por SSH), então o checksum de cada item é o
que está lá agora e a trava de identidade do rake volta a valer.
"""
import json, os, sys, collections

SP = os.path.dirname(os.path.abspath(__file__))
ALVO_PX = 512

D = json.load(open(SP + '/stamp-groups.json'))
AS = {a['id']: a for a in D['assets']}
GR = {g['id']: g for g in D['assetGroups']}
packs = json.load(open(SP + '/packs2.json')); packs = packs.get('items') or packs
P = {p['id']: p for p in packs}
styles = json.load(open(SP + '/styles.json')); styles = styles.get('items') or styles
S = {s['id']: s for s in styles}
casado = {c: tuple(v) for c, v in json.load(open(SP + '/casado-prod.json')).items()}
# grupos de variantes que JÁ existem em prod (dos 843 convertidos antes) — um
# cluster partido entre as duas levas não pode perder a metade nova.
jaEmProd = collections.Counter()
for l in open(SP + '/prod-vg.txt'):
    p = l.rstrip('\n').split('|')
    if len(p) == 2 and p[0]: jaEmProd[p[0]] = int(p[1])

def variante(a):
    sz = (a.get('data') or {}).get('size') or {}
    L = max(sz.get('w') or 0, sz.get('h') or 0)
    imgs = a.get('images') or {}
    escala = (('x1', 8), ('x2', 4), ('x4', 2), ('x8', 1))
    i = next((k for k, (v, d) in enumerate(escala) if (L / d >= ALVO_PX or v == 'x8') and imgs.get(v)), None)
    if i is None: return [], 0
    return [imgs[v] for v, _ in escala[i::-1] if imgs.get(v)], round(L / escala[i][1])

def metadados(a):
    pk = P.get(a.get('packId')) or {}
    st = S.get(pk.get('sceneStyleId')) or {}
    gid = (a.get('assetGroupIds') or [None])[0]
    cat = (st.get('title') or '').strip(); grp = (pk.get('title') or '').strip()[:60]
    if not cat or not grp: return None
    return {'n': (a.get('title') or '').strip()[:80] or None, 'c': cat, 'g': grp,
            'vg': f'ink-{gid}' if gid else None,
            'vo': a.get('order') if isinstance(a.get('order'), int) else 0}

itens = []; resumo = collections.Counter()
for l in open(SP + '/prod-objs.txt'):
    p = l.rstrip('\n').split('|')
    if len(p) < 7: continue
    rid, _key, chk, filename = int(p[0]), p[1], p[2], p[3]
    if filename.startswith('ink-'):
        resumo['já em alta'] += 1; continue
    m = casado.get(chk)
    if not m:
        resumo['sem casamento'] += 1; continue
    a = AS.get(m[0])
    if not a: continue
    urls, px = variante(a)
    meta = metadados(a)
    it = {'id': rid, 'chk': chk, 'aid': a['id'], 'via': m[1]}
    if urls: it['us'] = urls; it['px'] = px
    if meta: it.update({k: v for k, v in meta.items() if v is not None})
    if not it.get('us') and not meta: continue
    resumo['com-imagem' if urls else 'só-metadado'] += 1
    resumo['com-metadado' if meta else 'sem-metadado'] += 1
    itens.append(it)

# Cluster de variantes com UM membro só é ruído — mas conta junto o que já está
# em prod, senão um grupo partido entre as duas levas perde a metade nova.
conta = collections.Counter(x['vg'] for x in itens if x.get('vg'))
for x in itens:
    vg = x.get('vg')
    if vg and conta[vg] + jaEmProd.get(vg, 0) < 2:
        x.pop('vg'); resumo['grupo-de-um-desfeito'] += 1
resumo['em-grupo-de-variantes'] = sum(1 for x in itens if x.get('vg'))

itens.sort(key=lambda x: x['id'])
dest = sys.argv[1] if len(sys.argv) > 1 else SP + '/inkarnate_objects.json'
json.dump({'gerado_em': '2026-09-04', 'fonte': 'blobs ATUAIS de produção casados no catálogo Inkarnate (MD5 + semelhança visual)',
           'alvo_px': ALVO_PX, 'total': len(itens), 'itens': itens},
          open(dest, 'w'), ensure_ascii=False, separators=(',', ':'))
print(f'{len(itens)} itens -> {dest} ({os.path.getsize(dest)/1024:.0f} KB)')
for k, v in resumo.most_common(): print(f'  {k}: {v}')
