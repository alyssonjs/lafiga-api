import json, subprocess, os, collections
SP = os.path.dirname(os.path.abspath(__file__))
tok = open('/Users/alyssonjosesoares/Documents/lafiga/token inkarnate').read().strip()
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/122 Safari/537.36'

cenas = json.load(open('/Users/alyssonjosesoares/Documents/lafiga/api/db/data/inkarnate_scenes.json'))
cs = cenas['cenas'] if isinstance(cenas, dict) else cenas

def achata(c):
    if c.get('cmdType') == 'cmd-composite':
        for s in c.get('cmds') or []:
            yield from achata(s)
    else:
        yield c

def baixa_cmds(sid):
    dest = f'{SP}/ink_cenas/{sid}.json'
    if os.path.exists(dest):
        return json.load(open(dest))
    todos, offset = [], 0
    while True:
        url = f'https://api2.inkarnate.com/api/v2/scenes/{sid}/commandsPaginated?size=500&offset={offset}'
        out = subprocess.run(['curl','-sS','-H',f'Authorization: {tok}','-H',f'User-Agent: {UA}','--max-time','240',url], capture_output=True, timeout=260).stdout
        d = json.loads(out)
        lote = d.get('commands') or []
        if not lote: break
        todos += lote; offset += len(lote)
        if len(lote) < 500: break
    json.dump(todos, open(dest, 'w'))
    return todos

saida = {}
fontes = collections.Counter()
for c in cs:
    sid = c['sid']
    cmds = baixa_cmds(sid)
    # ⚠️ Espelha o replay do gerador ORIGINAL (gerar_inkarnate_scenes.py):
    # remoções vêm em DOIS formatos — `entityIds` (lista chata) OU `items`.
    # Tratar só um ressuscitou 137 textos apagados na Láfiga 2.0 (o "Midbar"
    # gigante do 1.x está literalmente numa remoção entityIds).
    ents, camadas, camada_de = {}, {}, {}
    for bruto in cmds:
        for cmd in achata(bruto):
            t = cmd.get('cmdType')
            if t == 'cmd-layer-add':
                camadas[cmd.get('layerId')] = (cmd.get('layerData') or {}).get('isVisible', True)
            elif t == 'cmd-layer-update-visibility':
                camadas[cmd.get('layerId')] = cmd.get('isVisible', cmd.get('visible', True))
            elif t == 'cmd-layer-remove':
                camadas[cmd.get('layerId')] = False
            elif t == 'cmd-entity-add':
                for it in cmd.get('items') or []:
                    e = it.get('entity') or {}
                    ents[e.get('entityId')] = dict(e)
                    camada_de[e.get('entityId')] = it.get('layerId')
            elif t == 'cmd-entity-update':
                for it in cmd.get('items') or []:
                    eid = it.get('entityId')
                    if eid not in ents:
                        continue
                    ents[eid].update(it.get('update') or it.get('entity') or {})
                    if it.get('layerId'):
                        camada_de[eid] = it['layerId']
            elif t == 'cmd-entity-remove':
                for eid in cmd.get('entityIds') or [x.get('entityId') for x in (cmd.get('items') or [])]:
                    ents.pop(eid, None)
    textos = [e for e in ents.values()
              if e.get('entityType') == 'text'
              and e.get('isVisible') is not False
              and camadas.get(camada_de.get(e.get('entityId')), True) is not False]
    for t in textos:
        f = (t.get('textStyle') or {}).get('fontFamily') or 'IM Fell English SC (padrão)'
        fontes[f] += 1
    saida[str(sid)] = {'titulo': c['titulo'], 'celula_u': c['celula_u'], 'textos': textos}
    print(f"{sid} {c['titulo'][:28]:28s} textos={len(textos)}", flush=True)

json.dump(saida, open(f'{SP}/ink_cenas/textos_por_cena.json', 'w'), ensure_ascii=False)
tot = sum(len(v['textos']) for v in saida.values())
print('== total de textos:', tot)
print('== fontes usadas:', dict(fontes))
