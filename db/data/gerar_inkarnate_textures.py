# -*- coding: utf-8 -*-
"""Gera `inkarnate_textures.json` — a biblioteca de TEXTURAS de terreno que
existe só no banco de desenvolvimento, pronta p/ nascer em produção.

Produção não tem nenhuma textura: o que o pincel usa por padrão (`tx-grass`,
`tx-water`) são constantes do front, não registros. Este índice manda criar.

Cada item traz a URL do CDN de onde a imagem local VEIO (casada por MD5 do
blob), então produção recebe exatamente o arquivo que foi testado aqui — e o
metadado do catálogo (pack, grupo de variantes, ordem) organiza a biblioteca.
"""
import json, os, sys, collections

SP = os.path.dirname(os.path.abspath(__file__))
CDN = 'https://cdn2.inkarnate.com/'

md5 = json.load(open(SP + '/cdn-md5.json'))            # checksum do blob -> chave do CDN
cat = json.load(open(SP + '/cat2-tex.json'))
A = cat.get('assets') or cat.get('items') or cat
GR = {g['id']: g for g in (cat.get('assetGroups') or [])}
packs = json.load(open(SP + '/packs2.json')); packs = packs.get('items') or packs
P = {p['id']: p for p in packs}

chave2asset = {}
for a in A:
    for u in [a.get('thumbnail')] + list((a.get('images') or {}).values()):
        if isinstance(u, str) and u.startswith(CDN):
            chave2asset[u[len(CDN):]] = a

# A miniatura cuja versão HD já existe é redundante: produção nasce sem
# textura nenhuma, então não há A/B p/ manter — fica só a melhor de cada.
redundantes = set(json.load(open(SP + '/tex-redundantes.json')))

itens = []; resumo = collections.Counter(); usados = set()
for l in open(SP + '/tex-rows.txt'):
    p = l.rstrip('\n').split('|')
    if len(p) < 10: continue
    rid, nome, categoria, _grp, _vg, ordem, _key, ct, tam, chk = p[:10]
    if rid in redundantes:
        resumo['miniatura-redundante'] += 1
        continue
    chave = md5.get(chk)
    if not chave:
        resumo['sem-origem'] += 1
        continue
    hd = categoria == 'Terrenos HD'
    a = chave2asset.get(chave)
    titulo = (a.get('title') or '').strip() if a else ''
    pack = (P.get(a.get('packId')) or {}).get('title') if a else None
    gid = ((a.get('assetGroupIds') or [None])[0] if a else None)

    base = (titulo or nome).strip()[:80] or nome
    final = base; n = 2
    while final.lower() in usados:
        final = f'{base} {n}'[:80]; n += 1
    usados.add(final.lower())

    it = {'n': final, 'u': CDN + chave, 'ct': ct, 'vo': int(ordem or 0)}
    if pack: it['g'] = pack.strip()[:60]
    if gid: it['vg'] = f'ink-{gid}'
    itens.append(it)
    resumo['hd' if hd else 'miniatura'] += 1
    resumo['com-metadado' if a else 'sem-metadado'] += 1

conta = collections.Counter(x['vg'] for x in itens if x.get('vg'))
for x in itens:
    if x.get('vg') and conta[x['vg']] < 2:
        x.pop('vg')
resumo['em-grupo-de-variantes'] = sum(1 for x in itens if x.get('vg'))

saida = {'gerado_em': '2026-09-04', 'categoria': 'Terrenos',
         'fonte': 'biblioteca de textura do banco de dev, origem casada por MD5 no CDN do Inkarnate',
         'total': len(itens), 'itens': itens}
dest = sys.argv[1] if len(sys.argv) > 1 else SP + '/inkarnate_textures.json'
json.dump(saida, open(dest, 'w'), ensure_ascii=False, separators=(',', ':'))
print(f'{len(itens)} texturas -> {dest} ({os.path.getsize(dest)/1024:.0f} KB)')
for k, v in resumo.most_common(): print(f'  {k}: {v}')
