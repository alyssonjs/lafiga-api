# -*- coding: utf-8 -*-
"""Gera `inkarnate_scenes.json` + os fundos de terreno das cenas do Inkarnate.

Import ESTRUTURADO: o terreno vai como imagem de fundo (as camadas `brush` já
vêm rasterizadas do CDN deles) e cada objeto vira um MapToken EDITÁVEL apontando
para o MapAsset do catálogo. As paredes rochosas, a mobília, tudo: são stamps.

Geometria MEDIDA no render (sobreposição das caixas calculadas sobre a arte):
  canto sup-esq = entidade.x + asset.data.offset.x * escala   [unidades de cena]
  tamanho       = asset.data.size * escala                    [unidades de cena]
  célula        = entidade GRID final (`style.size`); sem grid, 200 (régua do
                  catálogo — ver lafiga_inkarnate_modelo_escala_textura)
O ângulo já vem em GRAUS horários, como o `rotation` do token.

⚠️ A composição do fundo acontece AQUI porque produção não tem libvips
(`require "vips"` falha lá); o rake só anexa o arquivo pronto.

Uso: INK_DUMPS=<pasta dos dumps> python3 gerar_inkarnate_scenes.py <destino.json> <pasta-fundos>
"""
import json, os, sys, glob, collections

AQUI = os.path.dirname(os.path.abspath(__file__))   # db/data — onde vive o catálogo
SP = os.environ.get('INK_DUMPS') or AQUI            # dumps crus (não comitados)
UNIDADES_POR_CELULA_PADRAO = 200.0   # régua do catálogo quando a cena não tem grid
LADO_MAX = 1000                      # BattleMap::MAX_DIM
LADO_MIN_PLAUSIVEL = 20              # grid que dá menos que isto é lixo herdado, não grade
LADO_LEGADO = 40                     # lado maior das cenas antigas (o default deles: 8192/204,8)
# Acima disto o mapa ganha NÍVEL DE DETALHE por zoom em vez de entrar plano: um
# mapa-mundo do Inkarnate traz dezenas de milhares de árvores, e desenhar todas
# de longe é ilegível além de lento (é o que os mapas de papel sempre fizeram).
TETO_ESTRUTURADO = 3000

# Faixas de detalhe por POSTO DE TAMANHO (o maior primeiro): até tantos objetos,
# tal `zoomMin`. Orçamento por posto — e não por tamanho absoluto — porque é o
# que limita o custo POR CONSTRUÇÃO, qualquer que seja a distribuição do mapa:
# "Arredores Argoba" tem 3.460 objetos de 1 célula ou mais, e um corte por
# tamanho deixaria os 3.460 desenhando juntos com o mapa inteiro na tela.
# Medido nos três mapas densos: pico de ~1.770 desenhados, a maioria < 1.200.
DETALHE_FAIXAS = ((900, None), (2400, 1.2), (5000, 2.0), (10 ** 9, 2.6))


def achata(cmd):
    """cmd-composite embrulha outros comandos; o replay tem de entrar neles."""
    if cmd.get('cmdType') == 'cmd-composite':
        for sub in cmd.get('cmds') or []:
            yield from achata(sub)
    else:
        yield cmd


def replay(cmds):
    """Dobra o log até o estado final: entidades vivas + visibilidade das camadas."""
    ents, camadas = {}, {}
    for bruto in cmds:
        for c in achata(bruto):
            t = c.get('cmdType')
            if t == 'cmd-layer-add':
                camadas[c.get('layerId')] = (c.get('layerData') or {}).get('isVisible', True)
            elif t == 'cmd-layer-update-visibility':
                camadas[c.get('layerId')] = c.get('isVisible', c.get('visible', True))
            elif t == 'cmd-entity-add':
                for it in c.get('items') or []:
                    e = it.get('entity') or {}
                    ents[e.get('entityId')] = {'e': dict(e), 'camada': it.get('layerId')}
            elif t == 'cmd-entity-update':
                for it in c.get('items') or []:
                    eid = it.get('entityId')
                    if eid not in ents:
                        continue
                    upd = it.get('update') or it.get('entity') or {}
                    for k, v in upd.items():
                        if k == 'style' and isinstance(v, dict):
                            ents[eid]['e'].setdefault('style', {}).update(v)
                        else:
                            ents[eid]['e'][k] = v
                    if it.get('layerId'):
                        ents[eid]['camada'] = it['layerId']
            elif t == 'cmd-entity-remove':
                for eid in c.get('entityIds') or [x.get('entityId') for x in (c.get('items') or [])]:
                    ents.pop(eid, None)
    return ents, camadas


def celula_da_cena(ents):
    """A régua do mapa é o grid QUE O UTILIZADOR DEIXOU — em unidades de cena."""
    for v in ents.values():
        if v['e'].get('entityType') == 'grid':
            tam = (v['e'].get('style') or {}).get('size')
            if tam and tam > 1:
                return float(tam)
    return UNIDADES_POR_CELULA_PADRAO


def _baixa(url):
    import urllib.request
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=240) as r:
        return r.read()


def _tamanho(destino):
    from PIL import Image
    with Image.open(destino) as im:
        return im.size


def baixa_preview(cena, destino):
    """Modo PLANO: o render achatado do Inkarnate (terreno + objetos + grade)."""
    from PIL import Image
    import io
    if os.path.exists(destino):
        return _tamanho(destino)
    u = cena.get('preview')
    if not u:
        return None
    im = Image.open(io.BytesIO(_baixa(u))).convert('RGBA')
    im.save(destino, 'WEBP', quality=88, method=4)
    return im.size


def compoe_fundo(cena, destino):
    """bg + fg(recortado pela máscara) + top = o TERRENO, sem objeto nem grade."""
    from PIL import Image, ImageChops
    import io
    # resumível: compor de novo custa ~6 MB de download por cena
    if os.path.exists(destino):
        return _tamanho(destino)
    comp = None
    for L in cena.get('sceneLayers') or []:
        imgs = {im.get('canvasName'): im.get('imageUrl') for im in (L.get('layerImages') or [])}
        if not imgs.get('brush'):
            continue
        camada = Image.open(io.BytesIO(_baixa(imgs['brush']))).convert('RGBA')
        if imgs.get('mask'):
            m = Image.open(io.BytesIO(_baixa(imgs['mask'])))
            m = m.getchannel('A') if 'A' in m.getbands() else m.convert('L')
            camada.putalpha(ImageChops.multiply(camada.getchannel('A'), m))
        if comp is None:
            comp = Image.new('RGBA', camada.size, (0, 0, 0, 0))
        comp.alpha_composite(camada)
    if comp is None:
        return None
    # WebP com alfa: o vazio da masmorra continua transparente (o mapa mostra o
    # fundo dele por baixo) e pesa ~10× menos que PNG.
    comp.save(destino, 'WEBP', quality=88, method=4)
    return comp.size


def main():
    dest_json = sys.argv[1] if len(sys.argv) > 1 else SP + '/inkarnate_scenes.json'
    dir_fundos = sys.argv[2] if len(sys.argv) > 2 else SP + '/fundos'
    os.makedirs(dir_fundos, exist_ok=True)

    A = {a['id']: a for a in json.load(open(SP + '/stamp-groups.json'))['assets']}
    # aid presentes no catálogo que o rake importa (só esses viram token com arte)
    cat = os.path.join(AQUI, 'inkarnate_catalog.json')
    no_catalogo = {i['aid'] for i in json.load(open(cat))['itens']} if os.path.exists(cat) else set(A)

    cenas, resumo = [], collections.Counter()
    sem_arte = collections.Counter()
    for f in sorted(glob.glob(SP + '/cenas/*.json')):
        sid = os.path.basename(f)[:-5]
        det = json.load(open(f))
        cena = det.get('item') or det
        arq_cmds = f'{SP}/cenas-cmds/{sid}.json'
        if not os.path.exists(arq_cmds):
            resumo['sem log de comandos'] += 1
            continue
        ents, camadas = replay(json.load(open(arq_cmds)))
        norm = cena.get('normSceneSize') or {}
        # Cenas LEGADAS (majorVersion nulo): sceneLayers vazio e ZERO comandos —
        # o conteúdo delas não vive no log v2. Sobra o render achatado, que é
        # tudo o que existe; entram planas, dimensionadas pela proporção dele.
        legado = not norm.get('w')
        if legado:
            pd = cena.get('previewDimensions') or {}
            if not (pd.get('w') and pd.get('h')):
                resumo['legado sem preview (fora)'] += 1
                continue
            norm = {'w': float(pd['w']), 'h': float(pd['h'])}
            resumo['cenas LEGADAS (só render achatado)'] += 1

        C = celula_da_cena(ents)
        if legado:
            C = max(norm['w'], norm['h']) / LADO_LEGADO
        # Grade que produz um tabuleiro minúsculo é resquício de outro mapa (o
        # "Melee" dava 11x8 com 11 mil objetos) — cai na régua do catálogo.
        if min(norm['w'] / C, norm['h'] / C) < LADO_MIN_PLAUSIVEL:
            resumo['grid implausível -> régua do catálogo'] += 1
            C = UNIDADES_POR_CELULA_PADRAO
        larg = max(5, min(LADO_MAX, round(norm['w'] / C)))
        alt = max(5, min(LADO_MAX, round(norm['h'] / C)))

        tokens = []
        for v in ents.values():
            e = v['e']
            if e.get('entityType') != 'stamp':
                continue
            if camadas.get(v['camada']) is False:
                resumo['em camada oculta'] += 1
                continue
            a = A.get(e.get('stampId'))
            if not a:
                resumo['asset desconhecido'] += 1
                continue
            if a['id'] not in no_catalogo:
                sem_arte[a.get('title') or a['id']] += 1
                resumo['sem arte no catálogo'] += 1
                continue
            dados = a.get('data') or {}
            sz, off = dados.get('size') or {}, dados.get('offset') or {'x': 0, 'y': 0}
            esc = e.get('scale') or 1
            w, h = (sz.get('w') or 0) * esc, (sz.get('h') or 0) * esc
            if w <= 0 or h <= 0:
                resumo['sem tamanho'] += 1
                continue
            x = (e.get('x', 0) + off.get('x', 0) * esc) / C
            y = (e.get('y', 0) + off.get('y', 0) * esc) / C
            t = {'aid': a['id'], 'x': round(x, 4), 'y': round(y, 4),
                 'w': round(w / C, 4), 'h': round(h / C, 4)}
            ang = e.get('angle') or 0
            if ang % 360:
                t['rot'] = round(ang % 360, 2)
            z = e.get('z')
            if isinstance(z, (int, float)) and z:
                t['sub'] = max(-5, min(5, int(z)))
            tokens.append(t)
            resumo['tokens'] += 1

        # ordem de pintura: sublayer asc, e dentro dela a ordem do próprio editor
        tokens.sort(key=lambda t: t.get('sub', 0))
        # Denso demais para desenhar tudo de uma vez: os objetos CONTINUAM
        # editáveis, mas só aparecem no zoom em que se enxergam. O maior fica
        # sem limite; o resto entra conforme se aproxima.
        if not legado and len(tokens) > TETO_ESTRUTURADO:
            resumo['cenas com NÍVEL DE DETALHE'] += 1
            porte = sorted(tokens, key=lambda t: -max(t['w'], t['h']))
            i = 0
            for teto, zmin in DETALHE_FAIXAS:
                while i < min(teto, len(porte)):
                    if zmin is not None:
                        porte[i]['zmin'] = zmin
                    i += 1
                if i >= len(porte):
                    break
        plano = legado
        nome_fundo = f'{sid}.webp'
        caminho_fundo = os.path.join(dir_fundos, nome_fundo)
        if plano:
            resumo['cenas PLANAS (densas demais)'] += 0 if legado else 1
            resumo['tokens'] -= len(tokens)
            tokens = []
            if os.path.exists(caminho_fundo):
                os.remove(caminho_fundo)   # troca terreno-puro pelo achatado
            px = baixa_preview(cena, caminho_fundo)
        else:
            px = compoe_fundo(cena, caminho_fundo)
        cenas.append({
            'sid': int(sid),
            'titulo': (cena.get('title') or '').strip()[:120] or f'Inkarnate {sid}',
            'estilo': cena.get('styleId'),
            'largura': larg, 'altura': alt,
            'celula_u': round(C, 4),
            'modo': 'plano' if plano else 'estruturado',
            'fundo': nome_fundo if px else None,
            'fundo_px': list(px) if px else None,
            'tokens': tokens,
        })
        resumo['cenas'] += 1
        print(f'  {sid} {cenas[-1]["titulo"][:32]:<32} {larg:>4}x{alt:<4} céls  '
              f'{len(tokens):>5} tokens  célula={C:.1f}u  {"PLANO" if plano else ""}', flush=True)

    json.dump({'gerado_em': '2026-09-05', 'total': len(cenas), 'cenas': cenas},
              open(dest_json, 'w'), ensure_ascii=False, separators=(',', ':'))
    print(f'\n{len(cenas)} cenas -> {dest_json} ({os.path.getsize(dest_json)/1024:.0f} KB)')
    for k, v in resumo.most_common():
        print(f'  {k}: {v}')
    if sem_arte:
        print('  sem arte (top):', sem_arte.most_common(6))


if __name__ == '__main__':
    main()
