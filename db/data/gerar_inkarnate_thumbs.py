#!/usr/bin/env python3
"""Índice de MINIATURAS do catálogo do Inkarnate.

A biblioteca de itens não tinha miniatura nenhuma: cada quadradinho de ~100 px
baixava a ARTE (medido em prod: 254 KB, ~300 px). Uma busca de 400 cards = 68 MB.

Prod NÃO converte imagem (sem ImageMagick/vips) e não há CDN com resize à
frente, então a miniatura nasce AQUI e vai pronta para lá — o mesmo contrato dos
fundos de cena (`gerar_inkarnate_scenes.py`).

Fonte: o nível `x1` da API (o MENOR que o Inkarnate serve, ~238 px / 50 KB).
Baixamos esse e reduzimos a `ALVO_PX` em webp — 50 KB viram ~4 KB.

Fases (retomáveis; cada uma salta o que já fez):
  1. `niveis`  — pede os `images` de cada aid (lotes de 25) → thumbs_urls.json
  2. `baixar`  — baixa o x1 de cada aid                     → x1/<aid>.<ext>
  3. `reduzir` — PIL → webp de ALVO_PX                      → thumbs/<aid>.webp

Uso:
  INK_TOKEN_FILE=~/…/token python3 gerar_inkarnate_thumbs.py niveis
  python3 gerar_inkarnate_thumbs.py baixar
  python3 gerar_inkarnate_thumbs.py reduzir
"""
import collections
import io
import json
import os
import subprocess
import sys
import time

ALVO_PX = 160          # card da grelha é ~100 px; 160 cobre telas 1.5x
# ⚠️ `version=2` é o padrão, mas os assets "mortos" (arquivados) só aparecem no
# `version=3` — a mesma armadilha que escondeu 417 objetos no import das cenas.
# Rodar a fase `niveis` uma segunda vez com INK_VERSION=3 recolhe o resto.
VERSAO = os.environ.get('INK_VERSION', '2')
LOTE = 25              # ⚠️ acima disto a API TRUNCA em silêncio (missingAssetIds vazio)
QUALIDADE = 78

SAIDA = os.environ.get('INK_THUMBS_DIR') or '/tmp/ink_thumbs'
BASE = os.path.dirname(os.path.abspath(__file__))
UA = ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122 Safari/537.36')


def token():
    p = os.environ.get('INK_TOKEN_FILE')
    if not p:
        sys.exit('defina INK_TOKEN_FILE com o caminho do ficheiro do token')
    return open(os.path.expanduser(p)).read().strip()


def aids_do_catalogo():
    """Todo aid que a biblioteca tem — objetos, texturas e caminhos."""
    vistos = {}
    for arq, pref in (('inkarnate_catalog.json', 'ink'),
                      ('inkarnate_textures_catalog.json', 'inktex'),
                      ('inkarnate_paths_catalog.json', 'inkpath')):
        caminho = os.path.join(BASE, arq)
        if not os.path.exists(caminho):
            print(f'  (sem {arq})')
            continue
        d = json.load(open(caminho))
        for i in d['itens']:
            vistos.setdefault(int(i['aid']), pref)
        print(f'  {arq}: {len(d["itens"])} itens')
    return vistos


def fase_niveis():
    aids_pref = aids_do_catalogo()
    alvo = os.path.join(SAIDA, 'thumbs_urls.json')
    os.makedirs(SAIDA, exist_ok=True)
    urls = json.load(open(alvo)) if os.path.exists(alvo) else {}
    # re-pede também quem foi resolvido ANTES de guardarmos todos os níveis
    faltam = [a for a in aids_pref
              if str(a) not in urls or not (urls[str(a)] or {}).get('n')]
    print(f'== aids: {len(aids_pref)}; já resolvidos: {len(urls)}; a pedir: {len(faltam)}')
    tok = token()
    c = collections.Counter()
    for k in range(0, len(faltam), LOTE):
        lote = faltam[k:k + LOTE]
        cmd = ['curl', '-sS', '-X', 'POST',
               f'https://api2.inkarnate.com/api/assets?version={VERSAO}',
               '-H', f'Authorization: {tok}',
               '-H', 'X-HTTP-Method-Override: GET',
               '-H', f'User-Agent: {UA}',
               '--max-time', '90']
        for a in lote:
            cmd += ['-F', f'ids[]={a}']
        for flag in ('includeArchived', 'includeOfficial', 'includeMarketplace',
                     'includePurchased', 'includeCustomAuthored', 'includeChildAssets',
                     'includePacks', 'includeAssetGroups'):
            cmd += ['-F', f'{flag}=true']
        try:
            saida = subprocess.run(cmd, capture_output=True, timeout=120).stdout
            d = json.loads(saida)
        except Exception as e:                       # noqa: BLE001
            c['erro_lote'] += 1
            print(f'  ! lote {k}: {type(e).__name__}')
            time.sleep(2)
            continue
        recebidos = d.get('assets') or []
        # ⚠️ a API trunca CALADA: conferir recebidos vs pedidos (lição de 05/09)
        if len(recebidos) < len(lote):
            c['truncado'] += len(lote) - len(recebidos)
        for a in recebidos:
            imgs = a.get('images') or {}
            # o MENOR nível com URL — é o que vira miniatura
            # ⚠️ TODOS os níveis, não só o menor: o x1 de um asset pequeno dá
            # 14x31 px, e o card tem ~100 px — 57% sairiam DESFOCADOS. A fase
            # `promover` mede o x1 baixado e sobe de nível quando não chega.
            niveis = {v: imgs[v] for v in ('x1', 'x2', 'x4', 'x8') if imgs.get(v)}
            if niveis:
                urls[str(a['id'])] = {
                    'u': niveis[next(iter(niveis))],
                    'n': niveis,
                    'p': aids_pref.get(a['id'], 'ink'),
                }
                c['ok'] += 1
            else:
                c['sem_imagem'] += 1
        if (k // LOTE) % 40 == 0:
            json.dump(urls, open(alvo, 'w'))
            print(f'  … {len(urls)} resolvidos ({k}/{len(faltam)})')
    json.dump(urls, open(alvo, 'w'))
    print(f'== níveis: {dict(c)}; total no índice: {len(urls)} → {alvo}')


def fase_baixar():
    urls = json.load(open(os.path.join(SAIDA, 'thumbs_urls.json')))
    dest = os.path.join(SAIDA, 'x1')
    os.makedirs(dest, exist_ok=True)
    tem = {f.split('.')[0] for f in os.listdir(dest)}
    faltam = [(a, v['u']) for a, v in urls.items() if a not in tem]
    print(f'== a baixar: {len(faltam)} de {len(urls)}')
    c = collections.Counter()
    # curl em paralelo: uma conexão por ficheiro seria lento demais p/ 18 mil
    lista = os.path.join(SAIDA, '_baixar.txt')
    for k in range(0, len(faltam), 500):
        pedaco = faltam[k:k + 500]
        with open(lista, 'w') as f:
            for a, u in pedaco:
                f.write(f'url = "{u}"\noutput = "{dest}/{a}.img"\n')
        subprocess.run(['curl', '-sS', '--parallel', '--parallel-max', '12',
                        '-H', f'User-Agent: {UA}',
                        '-H', 'Accept: image/webp,image/png,image/*',
                        '--max-time', '120', '-K', lista],
                       capture_output=True, timeout=1800)
        c['lotes'] += 1
        print(f'  … {min(k + 500, len(faltam))}/{len(faltam)}')
    if os.path.exists(lista):
        os.remove(lista)
    n = len([f for f in os.listdir(dest) if f.endswith('.img')])
    tam = sum(os.path.getsize(os.path.join(dest, f)) for f in os.listdir(dest))
    print(f'== baixados: {n} ficheiros, {tam / 1048576:.0f} MB')


def fase_promover():
    """Sobe de nível o que ficou menor que o card.

    O `x1` é o menor que o CDN serve — ótimo para um carimbo grande, minúsculo
    para um pequeno (medido: 57% abaixo de 100 px, e o card tem ~100). Aqui
    MEDIMOS o ficheiro já baixado e, quando não alcança ALVO_PX, baixamos o
    nível seguinte. Empírico de propósito: a razão entre nível e píxeis não é
    a mesma para todo asset, então deduzi-la erraria.
    """
    from PIL import Image
    urls = json.load(open(os.path.join(SAIDA, 'thumbs_urls.json')))
    orig = os.path.join(SAIDA, 'x1')
    c = collections.Counter()
    fila = []
    for arq in sorted(os.listdir(orig)):
        if not arq.endswith('.img'):
            continue
        aid = arq[:-4]
        ent = urls.get(aid) or {}
        niveis = ent.get('n') or {}
        if not niveis:
            c['sem_niveis'] += 1
            continue
        try:
            with Image.open(os.path.join(orig, arq)) as im:
                lado = max(im.size)
        except Exception:                            # noqa: BLE001
            c['ilegivel'] += 1
            continue
        if lado >= ALVO_PX:
            c['ja_serve'] += 1
            continue
        ordem = [v for v in ('x1', 'x2', 'x4', 'x8') if v in niveis]
        atual = ent.get('nivel', ordem[0] if ordem else None)
        i = ordem.index(atual) if atual in ordem else 0
        # quantos degraus faltam: cada degrau DOBRA o lado
        passos = 0
        while lado * (2 ** passos) < ALVO_PX and i + passos + 1 < len(ordem):
            passos += 1
        if passos == 0:
            c['no_maior'] += 1     # nem o maior nível chega: fica como está
            continue
        fila.append((aid, niveis[ordem[i + passos]], ordem[i + passos]))
    print(f'== a promover: {len(fila)}; {dict(c)}')
    lista = os.path.join(SAIDA, '_promover.txt')
    for k in range(0, len(fila), 500):
        pedaco = fila[k:k + 500]
        with open(lista, 'w') as f:
            for aid, u, _v in pedaco:
                f.write(f'url = "{u}"\noutput = "{orig}/{aid}.img"\n')
        subprocess.run(['curl', '-sS', '--parallel', '--parallel-max', '12',
                        '-H', f'User-Agent: {UA}',
                        '-H', 'Accept: image/webp,image/png,image/*',
                        '--max-time', '120', '-K', lista],
                       capture_output=True, timeout=1800)
        for aid, _u, v in pedaco:
            urls[aid]['nivel'] = v
        json.dump(urls, open(os.path.join(SAIDA, 'thumbs_urls.json'), 'w'))
        print(f'  … {min(k + 500, len(fila))}/{len(fila)}')
    if os.path.exists(lista):
        os.remove(lista)
    print('== promoção terminada; correr `reduzir` de novo (apaga thumbs/ antes)')


def fase_reduzir():
    from PIL import Image
    urls = json.load(open(os.path.join(SAIDA, 'thumbs_urls.json')))
    orig = os.path.join(SAIDA, 'x1')
    dest = os.path.join(SAIDA, 'thumbs')
    os.makedirs(dest, exist_ok=True)
    c = collections.Counter()
    bytes_tot = 0
    for arq in sorted(os.listdir(orig)):
        if not arq.endswith('.img'):
            continue
        aid = arq[:-4]
        pref = (urls.get(aid) or {}).get('p', 'ink')
        saida = os.path.join(dest, f'{pref}-{aid}.webp')
        if os.path.exists(saida):
            c['ja_tinha'] += 1
            bytes_tot += os.path.getsize(saida)
            continue
        try:
            im = Image.open(os.path.join(orig, arq))
            # ⚠️ RGBA sempre: o carimbo tem alfa e o objeto de cenário é
            # recortado — achatar em RGB punha fundo preto no card.
            im = im.convert('RGBA')
            im.thumbnail((ALVO_PX, ALVO_PX), Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, 'WEBP', quality=QUALIDADE, method=4)
            open(saida, 'wb').write(buf.getvalue())
            bytes_tot += buf.tell()
            c['criado'] += 1
        except Exception as e:                       # noqa: BLE001
            c[f'falha_{type(e).__name__}'] += 1
    print(f'== miniaturas: {dict(c)}; total {bytes_tot / 1048576:.1f} MB em {dest}')


if __name__ == '__main__':
    fase = sys.argv[1] if len(sys.argv) > 1 else ''
    {'niveis': fase_niveis, 'baixar': fase_baixar, 'promover': fase_promover,
     'reduzir': fase_reduzir}.get(
        fase, lambda: sys.exit(__doc__))()
