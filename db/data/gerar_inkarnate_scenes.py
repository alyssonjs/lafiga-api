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
# ⚠️ NADA de esconder objeto por zoom: todo objeto importado aparece sempre.
# Chegou a existir aqui uma atribuição automática de `zoomMin` por tamanho, para
# aliviar os mapas-mundo (o "Melee" tem 11.531 objetos). O utilizador viu e
# rejeitou: sumiço automático confunde mais do que o custo que evita, e o
# controlo de detalhe por objeto continua na interface para quem quiser usá-lo.


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


def ordem_das_camadas(cmds):
    """Pilha das camadas (a de baixo primeiro), REPLAY completo do log.

    ⚠️ `sceneLayers` NÃO vem em ordem de z: a cena "Melee" traz [fg, bg], e
    compor na ordem do array pintava o oceano POR CIMA do continente. O nome
    também não serve de régua — há cenas com camadas de pincel batizadas com
    UUID ou `layer-brush-71`.

    ⚠️ `cmd-layer-reorder` é AUTORITÁRIO (traz a lista inteira) e tem de ser
    replicado: derivar só dos `atIndex` pôs as poças da "Mephit dungeon" no
    topo quando na pilha real elas vivem DEBAIXO da tinta do chão — o anel de
    lava é a tinta com buraco por cima da poça inteira.
    """
    ordem = []
    for bruto in cmds:
        for c in achata(bruto):
            t = c.get('cmdType')
            if t == 'cmd-layer-add':
                lid = c.get('layerId')
                if lid in ordem:
                    continue
                i = c.get('atIndex')
                ordem.insert(min(i, len(ordem)) if isinstance(i, int) else len(ordem), lid)
            elif t == 'cmd-layer-remove':
                lid = c.get('layerId')
                if lid in ordem:
                    ordem.remove(lid)
            elif t == 'cmd-layer-reorder':
                novo = [l for l in (c.get('newLayerOrder') or []) if l]
                if novo:
                    ordem = novo + [l for l in ordem if l not in novo]
    return ordem


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


def _alfa_da_mascara(dados):
    """A máscara vive no ALFA — o RGB dela é preto puro em todas as cenas.

    ⚠️ Converter para 'L' lia essa cor e devolvia 0, apagando a camada inteira:
    foi o que sumiu com o continente do "Melee". Máscara de PALETA guarda a
    transparência em bytes, e só o RGBA a resolve; sem canal alfa (RGB puro), o
    RGBA nasce opaco — que é o certo: máscara cheia não recorta nada.
    """
    from PIL import Image
    import io
    return Image.open(io.BytesIO(dados)).convert('RGBA').getchannel('A')


def salva_mascara_de_terra(cena, ordem, destino):
    """Exporta a silhueta de TERRA da cena (alfa = terra) para semear a
    Ferramenta de Terra: litoral vivo/editável e pintar/apagar na união.

    Só vale quando a máscara DISTINGUE terra de mar (1%..99% opaca): a do
    "Arredores Argoba" é 100% opaca (mapa todo é terra) e viraria só uma
    moldura de contorno na borda do mapa. Reduzida a ≤2048 px — silhueta não
    precisa dos 4096 da arte. Resumível pelo arquivo no destino.
    """
    from PIL import Image
    import io
    if os.path.exists(destino):
        return True
    pos = {lid: i for i, lid in enumerate(ordem)}
    camadas = sorted(cena.get('sceneLayers') or [],
                     key=lambda L: (L.get('layerId') != 'layer-fg', pos.get(L.get('layerId'), len(pos))))
    for L in camadas:
        um = {im.get('canvasName'): im.get('imageUrl') for im in (L.get('layerImages') or [])}
        if not um.get('mask'):
            continue
        m = Image.open(io.BytesIO(_baixa(um['mask']))).convert('RGBA')
        alfa = m.getchannel('A')
        h = alfa.histogram()
        opaco = sum(h[250:]) / max(1, sum(h))
        if not (0.01 < opaco < 0.99):
            return False
        if m.width > 2048:
            m = m.resize((2048, round(m.height * 2048 / m.width)), Image.LANCZOS)
        m.save(destino, 'WEBP', quality=90, method=4)
        return True
    return False


def salva_miniatura(caminho_fundo, destino):
    """Miniatura do CARD da lista (~420 px) a partir do fundo já composto.

    ⚠️ Sem isto a miniatura só nasce quando o construtor captura a tela — e se
    o fundo ainda não carregou, ela congela a textura de base chapada ("a
    miniatura não pega nada"). Gerada aqui, é determinística e certa desde o
    primeiro import. Teto do endpoint: 300 KB em base64.
    """
    from PIL import Image
    if os.path.exists(destino):
        return True
    with Image.open(caminho_fundo) as im:
        im = im.convert('RGB')
        larg = 420
        im = im.resize((larg, max(1, round(im.height * larg / im.width))), Image.LANCZOS)
        im.save(destino, 'WEBP', quality=80, method=4)
    return True


# Modos de mistura que o Inkarnate escreve direto no `globalCompositeOperation`
# do canvas. `darken` fica de FORA da assadura de propósito: medido no acervo,
# a diferença de compor um penhasco escuro com min() contra o terreno é de 0,1
# a 1,9 em 255 — invisível, e assar 2.241 penhascos custaria a edição deles.
BLEND_DE_TINTA = ('multiply', 'hard-light', 'soft-light', 'overlay', 'luminosity',
                  'screen', 'lighten', 'color-burn', 'color-dodge', 'difference',
                  'exclusion')


def efeitos_do_stamp(e):
    """hue/saturação/brilho/contraste/desfoque/mistura — só o que sai do padrão.

    Receita COPIADA do editor deles (`computeFilters` no bundle): a ordem é
    hue-rotate, saturate, CONTRAST, brightness, blur — contraste antes do
    brilho, que não é a ordem que se escreveria por instinto.
    """
    ef = {}
    hue = e.get('hue') or 0
    sat = e.get('saturation')
    bri = e.get('brightness')
    con = e.get('contrast')
    if hue:
        ef['hue'] = round(float(hue), 2)
    if sat is not None and sat != 100:
        ef['sat'] = round(float(sat), 2)
    if con is not None and con != 100:
        ef['con'] = round(float(con), 2)
    if bri is not None and bri != 100:
        ef['bri'] = round(float(bri), 2)
    # `blur: true` com raio 0 é o padrão de 8.344 objetos — ligado e sem efeito.
    if e.get('blur') and (e.get('blurRadius') or 0):
        ef['blur'] = round(float(e['blurRadius']), 2)
    if e.get('blendMode'):
        ef['blend'] = e['blendMode']
    return ef


def _matriz(rgb, m):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    import numpy as np
    return np.stack([
        m[0][0] * r + m[0][1] * g + m[0][2] * b,
        m[1][0] * r + m[1][1] * g + m[1][2] * b,
        m[2][0] * r + m[2][1] * g + m[2][2] * b,
    ], axis=-1)


def aplica_filtros(img, ef):
    """O mesmo que `ctx.filter` faria no browser, em sRGB e na ordem deles.

    As matrizes são as da spec de Filter Effects (a mesma luminância
    0.213/0.715/0.072 que o Chrome usa) — copiar a fórmula é o que garante que
    o assado no fundo e o token vivo pintem a MESMA cor.
    """
    import math
    import numpy as np
    from PIL import Image, ImageFilter
    if not any(k in ef for k in ('hue', 'sat', 'con', 'bri', 'blur')):
        return img
    a = np.asarray(img.convert('RGBA'), dtype=np.float64) / 255.0
    rgb, alfa = a[..., :3], a[..., 3:]
    if 'hue' in ef:
        t = math.radians(ef['hue'])
        c, sn = math.cos(t), math.sin(t)
        rgb = _matriz(rgb, [
            [0.213 + c * 0.787 - sn * 0.213, 0.715 - c * 0.715 - sn * 0.715, 0.072 - c * 0.072 + sn * 0.928],
            [0.213 - c * 0.213 + sn * 0.143, 0.715 + c * 0.285 + sn * 0.140, 0.072 - c * 0.072 - sn * 0.283],
            [0.213 - c * 0.213 - sn * 0.787, 0.715 - c * 0.715 + sn * 0.715, 0.072 + c * 0.928 + sn * 0.072],
        ])
    if 'sat' in ef:
        k = ef['sat'] / 100.0
        rgb = _matriz(rgb, [
            [0.213 + 0.787 * k, 0.715 - 0.715 * k, 0.072 - 0.072 * k],
            [0.213 - 0.213 * k, 0.715 + 0.285 * k, 0.072 - 0.072 * k],
            [0.213 - 0.213 * k, 0.715 - 0.715 * k, 0.072 + 0.928 * k],
        ])
    if 'con' in ef:
        k = ef['con'] / 100.0
        rgb = (rgb - 0.5) * k + 0.5
    if 'bri' in ef:
        rgb = rgb * (ef['bri'] / 100.0)
    saida = Image.fromarray(
        (np.clip(np.concatenate([rgb, alfa], axis=-1), 0, 1) * 255).astype('uint8'), 'RGBA')
    if 'blur' in ef:
        saida = saida.filter(ImageFilter.GaussianBlur(ef['blur']))
    return saida


def _mistura(Cb, Cs, modo):
    import numpy as np
    if modo == 'multiply':
        return Cs * Cb
    if modo == 'screen':
        return Cs + Cb - Cs * Cb
    if modo == 'darken':
        return np.minimum(Cs, Cb)
    if modo == 'lighten':
        return np.maximum(Cs, Cb)
    if modo == 'difference':
        return np.abs(Cs - Cb)
    if modo == 'exclusion':
        return Cs + Cb - 2 * Cs * Cb
    if modo == 'hard-light':
        return np.where(Cs <= 0.5, 2 * Cs * Cb, 1 - 2 * (1 - Cs) * (1 - Cb))
    if modo == 'overlay':
        return np.where(Cb <= 0.5, 2 * Cs * Cb, 1 - 2 * (1 - Cs) * (1 - Cb))
    if modo == 'soft-light':
        d = np.where(Cb <= 0.25, ((16 * Cb - 12) * Cb + 4) * Cb, np.sqrt(np.maximum(Cb, 0)))
        return np.where(Cs <= 0.5,
                        Cb - (1 - 2 * Cs) * Cb * (1 - Cb),
                        Cb + (2 * Cs - 1) * (d - Cb))
    if modo == 'color-dodge':
        return np.where(Cb <= 0, 0.0, np.where(Cs >= 1, 1.0, np.minimum(1.0, Cb / np.maximum(1 - Cs, 1e-6))))
    if modo == 'color-burn':
        return np.where(Cb >= 1, 1.0, np.where(Cs <= 0, 0.0, 1 - np.minimum(1.0, (1 - Cb) / np.maximum(Cs, 1e-6))))
    if modo == 'luminosity':
        lum = lambda C: 0.3 * C[..., 0:1] + 0.59 * C[..., 1:2] + 0.11 * C[..., 2:3]
        d = lum(Cs) - lum(Cb)
        return np.clip(Cb + d, 0, 1)
    return Cs   # modo desconhecido: como o canvas faria com source-over


def compoe_com_mistura(comp, img, pos, modo):
    """`alpha_composite` que respeita o modo de mistura, na área do sprite.

    A fórmula é a do spec de compositing (Co = αs(1-αb)Cs + αsαb·B + (1-αs)αbCb):
    com o fundo TRANSPARENTE o blend some e sobra a arte crua — que é
    justamente o que o canvas faz, e a razão de assar o objeto só quando ele
    tem terreno por baixo.
    """
    import numpy as np
    from PIL import Image
    x, y = pos
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(comp.width, x + img.width), min(comp.height, y + img.height)
    if x1 <= x0 or y1 <= y0:
        return
    recorte = img.crop((x0 - x, y0 - y, x1 - x, y1 - y))
    base = comp.crop((x0, y0, x1, y1))
    s = np.asarray(recorte.convert('RGBA'), dtype=np.float64) / 255.0
    b = np.asarray(base.convert('RGBA'), dtype=np.float64) / 255.0
    Cs, As = s[..., :3], s[..., 3:]
    Cb, Ab = b[..., :3], b[..., 3:]
    B = _mistura(Cb, Cs, modo)
    Co = As * (1 - Ab) * Cs + As * Ab * B + (1 - As) * Ab * Cb
    Ao = As + Ab * (1 - As)
    with np.errstate(divide='ignore', invalid='ignore'):
        Cout = np.where(Ao > 0, Co / np.maximum(Ao, 1e-6), 0)
    saida = Image.fromarray(
        (np.clip(np.concatenate([Cout, Ao], axis=-1), 0, 1) * 255).astype('uint8'), 'RGBA')
    comp.paste(saida, (x0, y0))


def _arte_do_stamp(a, cache_dir):
    """Arte no maior nível do CDN, cacheada em disco — só para ASSAR no fundo."""
    from PIL import Image
    dest = os.path.join(cache_dir, f"{a['id']}.png")
    if not os.path.exists(dest):
        imgs = a.get('images') or {}
        u = imgs.get('x8') or imgs.get('x4') or imgs.get('x2') or imgs.get('x1')
        if not u:
            return None
        with open(dest, 'wb') as f:
            f.write(_baixa(u))
    return Image.open(dest).convert('RGBA')


def assa_stamps(comp, stamps, A, k, cache_dir, avisos):
    """Pinta stamps DIRETO no fundo — os que vivem debaixo de tinta.

    Objeto sob pincel não pode ser token: mover ele revelaria o buraco que o
    pintor deixou na tinta de cima (é assim que a Mephit faz o anel de lava).
    Âncora: (x,y) da entidade corresponde ao ponto (-offset) da arte; rotação
    em GRAUS horários em torno da âncora, igual ao editor.
    """
    import math
    from PIL import Image
    for e in sorted(stamps, key=lambda e: (e.get('z') or 0, e.get('order') or 0, e.get('entityId') or 0)):
        a = A.get(e.get('stampId'))
        if not a:
            avisos['assado sem asset'] += 1
            continue
        try:
            arte = _arte_do_stamp(a, cache_dir)
        except Exception:
            arte = None
        if arte is None:
            avisos['assado sem arte'] += 1
            continue
        dados = a.get('data') or {}
        sz, off = dados.get('size') or {}, dados.get('offset') or {'x': 0, 'y': 0}
        esc = e.get('scale') or 1
        w_px = (sz.get('w') or 0) * esc * k
        h_px = (sz.get('h') or 0) * esc * k
        if w_px < 1 or h_px < 1:
            continue
        img = arte.resize((max(1, round(w_px)), max(1, round(h_px))), Image.LANCZOS)
        ax = -off.get('x', 0) * esc * k
        ay = -off.get('y', 0) * esc * k
        if e.get('flipX'):
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
            ax = img.width - ax
        if e.get('flipY'):
            img = img.transpose(Image.FLIP_TOP_BOTTOM)
            ay = img.height - ay
        ef = efeitos_do_stamp(e)
        img = aplica_filtros(img, ef)
        op = e.get('opacity')
        if isinstance(op, (int, float)) and 0 <= op < 1:
            img.putalpha(img.getchannel('A').point(lambda v: int(v * op)))
        x, y = e.get('x', 0) * k, e.get('y', 0) * k
        ang = (e.get('angle') or 0) % 360
        modo = ef.get('blend')
        if ang:
            lado = int(2 * math.hypot(max(ax, img.width - ax), max(ay, img.height - ay))) + 2
            folha = Image.new('RGBA', (lado, lado), (0, 0, 0, 0))
            folha.alpha_composite(img, (round(lado / 2 - ax), round(lado / 2 - ay)))
            folha = folha.rotate(-ang, resample=Image.BICUBIC, center=(lado / 2, lado / 2))
            img, ax, ay = folha, lado / 2, lado / 2
        destino = (round(x - ax), round(y - ay))
        if modo:
            compoe_com_mistura(comp, img, destino, modo)
            avisos['assados COM mistura'] += 1
        else:
            comp.alpha_composite(img, destino)
        avisos['assados no fundo'] += 1


def _caixa(e, A):
    """Retângulo do sprite em unidades de cena (mesma conta da geometria)."""
    a = A.get(e.get('stampId'))
    if not a:
        return None
    d = a.get('data') or {}
    sz, off = d.get('size') or {}, d.get('offset') or {'x': 0, 'y': 0}
    esc = e.get('scale') or 1
    w, h = (sz.get('w') or 0) * esc, (sz.get('h') or 0) * esc
    if w <= 0 or h <= 0:
        return None
    x0 = e.get('x', 0) + off.get('x', 0) * esc
    y0 = e.get('y', 0) + off.get('y', 0) * esc
    return (x0, y0, x0 + w, y0 + h)


def coberto_por(caixa, caixas, celula=512.0, grelha=None):
    """Alguém do conjunto se sobrepõe a esta caixa?

    Um objeto assado desce para o FUNDO, abaixo de todo token — então só pode
    ser assado se nenhum token o cobrir, senão a pilha inverte e o que estava
    por cima passa a esconder o que estava por baixo.
    """
    if grelha is None:
        return any(caixa[0] < c[2] and c[0] < caixa[2] and caixa[1] < c[3] and c[1] < caixa[3]
                   for c in caixas)
    for gx in range(int(caixa[0] // celula), int(caixa[2] // celula) + 1):
        for gy in range(int(caixa[1] // celula), int(caixa[3] // celula) + 1):
            for c in grelha.get((gx, gy), ()):
                if caixa[0] < c[2] and c[0] < caixa[2] and caixa[1] < c[3] and c[1] < caixa[3]:
                    return True
    return False


def indexa(caixas, celula=512.0):
    g = {}
    for c in caixas:
        for gx in range(int(c[0] // celula), int(c[2] // celula) + 1):
            for gy in range(int(c[1] // celula), int(c[3] // celula) + 1):
                g.setdefault((gx, gy), []).append(c)
    return g


def compoe_fundo(cena, destino, ordem=(), assar=None, visiveis=None,
                 unidades_larg=None, A=None, cache_dir=None, avisos=None):
    """bg + fg(recortado pela máscara) + top = o TERRENO, sem objeto nem grade.

    `assar` = {layerId: [entidades]} INTERCALA objetos entre as camadas de
    tinta, na posição verdadeira da pilha — camada de objetos que vive abaixo
    de um pincel é parte do sanduíche do terreno, não token.
    """
    from PIL import Image, ImageChops
    import io
    # resumível: compor de novo custa ~6 MB de download por cena
    if os.path.exists(destino):
        return _tamanho(destino)
    canv = {}
    for L in cena.get('sceneLayers') or []:
        lid = L.get('layerId')
        if visiveis is not None and visiveis.get(lid) is False:
            continue
        imgs = {im.get('canvasName'): im.get('imageUrl') for im in (L.get('layerImages') or [])}
        if not imgs.get('brush'):
            continue
        camada = Image.open(io.BytesIO(_baixa(imgs['brush']))).convert('RGBA')
        if imgs.get('mask'):
            m = _alfa_da_mascara(_baixa(imgs['mask']))
            camada.putalpha(ImageChops.multiply(camada.getchannel('A'), m))
        canv[lid] = camada
    if not canv:
        return None
    W, H = next(iter(canv.values())).size
    comp = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    pos = {lid: i for i, lid in enumerate(ordem)}
    k = (W / unidades_larg) if unidades_larg else None
    fila = sorted(set(list(canv) + list(assar or {})), key=lambda l: pos.get(l, len(pos)))
    for lid in fila:
        if lid in canv:
            comp.alpha_composite(canv[lid])
        if assar and lid in assar and k and A:
            assa_stamps(comp, assar[lid], A, k, cache_dir, avisos)
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
    os.makedirs(os.path.join(SP, 'arte-assada'), exist_ok=True)
    sem_arte = collections.Counter()
    so = os.environ.get('INK_SID')   # reprocessa SO esta cena e FUNDE no indice
    for f in sorted(glob.glob(SP + '/cenas/*.json')):
        sid = os.path.basename(f)[:-5]
        if so and sid != so:
            continue
        det = json.load(open(f))
        cena = det.get('item') or det
        arq_cmds = f'{SP}/cenas-cmds/{sid}.json'
        if not os.path.exists(arq_cmds):
            resumo['sem log de comandos'] += 1
            continue
        cmds = json.load(open(arq_cmds))
        ents, camadas = replay(cmds)
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

        # O corte fundo/tokens: tudo abaixo do ULTIMO pincel visivel e terreno
        # (tinta E objetos, intercalados); so o topo livre vira token editavel.
        ordem = ordem_das_camadas(cmds)
        pos = {lid: i for i, lid in enumerate(ordem)}
        pinceis = [L.get('layerId') for L in (cena.get('sceneLayers') or [])
                   if any(im.get('canvasName') == 'brush' for im in (L.get('layerImages') or []))]
        corte = max((pos[l] for l in pinceis
                     if l in pos and camadas.get(l) is not False), default=-1)

        # Quem mistura com o terreno (`blendMode`) só fica igual ao editor se
        # for composto CONTRA ele — então vai para o fundo, desde que nenhum
        # objeto que continua token o cubra (senão a pilha inverteria).
        acima = [c for c in (_caixa(v['e'], A) for v in ents.values()
                             if v['e'].get('entityType') == 'stamp'
                             and camadas.get(v['camada']) is not False
                             and pos.get(v['camada'], len(pos)) >= corte
                             and v['e'].get('blendMode') not in BLEND_DE_TINTA) if c]
        malha = indexa(acima)
        livres = set()
        for v in ents.values():
            e = v['e']
            if e.get('blendMode') not in BLEND_DE_TINTA:
                continue
            if camadas.get(v['camada']) is False or pos.get(v['camada'], len(pos)) < corte:
                continue
            cx = _caixa(e, A)
            if cx and not coberto_por(cx, acima, grelha=malha):
                livres.add(e.get('entityId'))

        tokens = []
        assar = collections.defaultdict(list)
        for v in ents.values():
            e = v['e']
            if e.get('entityType') != 'stamp':
                continue
            if camadas.get(v['camada']) is False:
                resumo['em camada oculta'] += 1
                continue
            if not legado and pos.get(v['camada'], len(pos)) < corte:
                assar[v['camada']].append(e)
                continue
            if not legado and e.get('entityId') in livres:
                assar[v['camada']].append(e)
                resumo['assados por MISTURA com o terreno'] += 1
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
            ef = efeitos_do_stamp(e)
            if ef:
                t['ef'] = ef
                resumo['tokens com efeito de cor/mistura'] += 1
            tokens.append(t)
            resumo['tokens'] += 1

        # ordem de pintura: sublayer asc, e dentro dela a ordem do próprio editor
        tokens.sort(key=lambda t: t.get('sub', 0))
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
            if so:
                # reprocesso dirigido: joga fora o cache e compoe do zero
                for velho in (caminho_fundo, os.path.join(dir_fundos, sid + '-thumb.webp')):
                    if os.path.exists(velho):
                        os.remove(velho)
            px = compoe_fundo(cena, caminho_fundo, ordem, assar=assar, visiveis=camadas,
                              unidades_larg=norm['w'], A=A,
                              cache_dir=os.path.join(SP, 'arte-assada'), avisos=resumo)
            if salva_mascara_de_terra(cena, ordem, os.path.join(dir_fundos, f'{sid}-mask.webp')):
                resumo['máscaras de terra'] += 1
        if px:
            salva_miniatura(caminho_fundo, os.path.join(dir_fundos, f'{sid}-thumb.webp'))
            resumo['miniaturas'] += 1
        cenas.append({
            'sid': int(sid),
            'titulo': (cena.get('title') or '').strip()[:120] or f'Inkarnate {sid}',
            'estilo': cena.get('styleId'),
            'largura': larg, 'altura': alt,
            'celula_u': round(C, 4),
            'modo': 'plano' if plano else 'estruturado',
            'fundo': nome_fundo if px else None,
            'mascara': os.path.exists(os.path.join(dir_fundos, f'{sid}-mask.webp')),
            'fundo_px': list(px) if px else None,
            'assados': sum(len(v) for v in assar.values()) or None,
            'tokens': tokens,
        })
        resumo['cenas'] += 1
        print(f'  {sid} {cenas[-1]["titulo"][:32]:<32} {larg:>4}x{alt:<4} céls  '
              f'{len(tokens):>5} tokens  célula={C:.1f}u  {"PLANO" if plano else ""}', flush=True)

    if so and os.path.exists(dest_json):
        velho = json.load(open(dest_json))
        novos = {c['sid']: c for c in cenas}
        cenas = [novos.pop(c['sid'], c) for c in velho.get('cenas', [])] + list(novos.values())
    json.dump({'gerado_em': '2026-09-08', 'total': len(cenas), 'cenas': cenas},
              open(dest_json, 'w'), ensure_ascii=False, separators=(',', ':'))
    print(f'\n{len(cenas)} cenas -> {dest_json} ({os.path.getsize(dest_json)/1024:.0f} KB)')
    for k, v in resumo.most_common():
        print(f'  {k}: {v}')
    if sem_arte:
        print('  sem arte (top):', sem_arte.most_common(6))


if __name__ == '__main__':
    main()
