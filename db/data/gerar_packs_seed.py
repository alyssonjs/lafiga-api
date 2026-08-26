# -*- coding: utf-8 -*-
"""
Descrição em prosa dos 7 pacotes (PHB pág. 151) → conteúdo ESTRUTURADO.

⚠️ O conteúdo que estava no banco DIVERGIA do livro: faltavam pé de cabra,
martelo e 10 pítons no Pacote de Aventureiro, e sobrava um "Saco" que o livro
não lista. Reconstruir da fonte conserta o link E o dado.

Cada frase do livro é mapeada EXPLICITAMENTE para um `api_index`. Frase não
mapeada ABORTA — adivinhar aqui poria o item errado na mochila do jogador.
"""
import json, re, sys, unicodedata, collections

S = "/private/tmp/claude-501/-Users-alyssonjosesoares-Documents-lafiga-front-lafiga/3d48da8b-c253-4475-b774-cebbdbaf6263/scratchpad/phb"

NUM = {"um": 1, "uma": 1, "dois": 2, "duas": 2, "3": 3, "5": 5, "10": 10, "2": 2, "15": 15}

# frase do livro (normalizada) → (api_index, quantidade)
# `None` no índice = item que não existe em tabela nenhuma do PHB; é criado
# pelo próprio rake, com o nome do livro.
MAPA = {
    "uma mochila": ("mochila", 1),
    "um saco de dormir": ("saco-de-dormir", 1),
    "duas fantasias": ("roupas-de-entretenimento", 2),
    "5 velas": ("vela", 5),
    "10 velas": ("vela", 10),
    "5 dias de racoes": ("racoes-de-viagem-1-dia", 5),
    "10 dias de racoes": ("racoes-de-viagem-1-dia", 10),
    "2 dias de racoes": ("racoes-de-viagem-1-dia", 2),
    "um cantil": ("cantil", 1),
    "um kit de disfarce": ("kit-de-disfarce", 1),
    "um saco com 1 000 esferas de metal": ("esferas-sacola-com-1-000", 1),
    "3 metros de linha": ("linha-3-metros", 1),
    "um sino": ("sino", 1),
    "um pe de cabra": ("pe-de-cabra", 1),
    "um martelo": ("martelo", 1),
    "10 pitons": ("piton", 10),
    "uma lanterna coberta": ("lanterna-coberta", 1),
    "2 frascos de oleo": ("oleo-frasco", 2),
    "uma caixa de fogo": ("caixa-de-fogo", 1),
    "15 metros de corda de canhamo amarrada ao lado dele": ("corda-de-canhamo-15-metros", 1),
    "10 tochas": ("tocha", 10),
    "um bau": ("bau", 1),
    "2 caixas para mapas ou pergaminhos": ("porta-mapas-ou-pergaminhos", 2),
    "um conjunto de roupas finas": ("roupas-finas", 1),
    "um vidro de tinta": ("tinta-frasco-de-30ml", 1),
    "uma caneta tinteiro": ("caneta-tinteiro", 1),
    "uma lampada": ("lampada", 1),
    "5 folhas de papel": ("papel-uma-folha", 5),
    "um vidro de perfume": ("perfume-frasco", 1),
    "parafina": ("parafina", 1),
    "sabao": ("sabao", 1),
    "um livro de estudo": ("livro", 1),
    "10 folhas de pergaminho": ("pergaminho-uma-folha", 10),
    "um saquinho de areia": ("saquinho-de-areia", 1),
    "uma pequena faca": ("faca-pequena", 1),
    "um kit de refeicao": ("kit-de-refeicao", 1),
    "um cobertor": ("cobertor-de-inverno", 1),
    "uma caixa de esmolas": ("caixa-de-esmolas", 1),
    "2 blocos de incenso": ("bloco-de-incenso", 2),
    "um incensario": ("incensario", 1),
    "vestes": ("vestes", 1),
}

# Itens citados só nos pacotes — não estão na tabela de Equipamento nem na de
# Ferramentas. O rake os cria com o nome do livro; preço/peso ficam a definir.
SO_NO_PACOTE = {
    "linha-3-metros": "Linha (3 metros)",
    "saquinho-de-areia": "Saquinho de areia",
    "faca-pequena": "Faca pequena",
    "caixa-de-esmolas": "Caixa de esmolas",
    "bloco-de-incenso": "Bloco de incenso",
    "incensario": "Incensário",
    "vestes": "Vestes",
}

def chave(s):
    s = unicodedata.normalize("NFD", str(s))
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", s.lower())).strip()

# api_index do pacote no banco (já existentes)
SLUG_PACOTE = {
    "Artista": "pacote-artista", "Assaltante": "pacote-assaltante",
    "Aventureiro": "pacote-aventureiro", "Diplomata": "pacote-diplomata",
    "Estudioso": "pacote-estudioso", "Explorador": "pacote-explorador",
    "Sacerdote": "pacote-sacerdote",
}

# ⚠️ O seed de equipamento REPARA item existente mantendo o api_index antigo
# (`pitons`, `racoes`, `corda-15m`) em vez de renomeá-lo — renomear quebraria
# referências. Então o pacote precisa saber os DOIS índices: tenta o canônico e
# cai no reparado.
gear = json.load(open(S + "/phb_gear_seed.json"))
FALLBACK = {g["api_index"]: g["repair_index"] for g in gear if g.get("repair_index")}

livro = json.load(open(S + "/pacotes_livro.json"))
saida, nao_mapeadas = [], collections.Counter()

for nome, dados in livro.items():
    txt = dados["texto"]
    txt = re.sub(r"^Inclui\s+", "", txt)
    txt = txt.replace("O kit também possui ", "e ").replace("O kit também tem ", "e ")
    txt = re.sub(r"\s*\d{3}\s*$", "", txt)
    # parte por vírgula e " e " — a prosa do livro usa os dois
    partes = [p.strip() for p in re.split(r",| e (?=\w)", txt) if p.strip()]
    itens = []
    for p in partes:
        k = chave(p)
        if k in MAPA:
            idx, qtd = MAPA[k]
            entrada = {"item_index": idx, "quantity": qtd, "raw": p}
            if FALLBACK.get(idx): entrada["fallback_index"] = FALLBACK[idx]
            itens.append(entrada)
        else:
            nao_mapeadas[p] += 1
    saida.append({
        "api_index": SLUG_PACOTE[nome], "name": f"Pacote de {nome}",
        "value_gp": dados["preco"], "contents": itens,
    })

print(f"pacotes: {len(saida)} | linhas mapeadas: {sum(len(p['contents']) for p in saida)}")
if nao_mapeadas:
    print(f"\n❌ FRASES NÃO MAPEADAS: {len(nao_mapeadas)}")
    for f, n in nao_mapeadas.most_common(): print(f"   {n}x {f!r}")
    sys.exit(1)

json.dump({"pacotes": saida, "itens_so_no_pacote": SO_NO_PACOTE},
          open(S + "/packs_seed.json", "w"), ensure_ascii=False, indent=1)
for p in saida:
    print(f"\n── {p['name']} ({p['value_gp']} po) — {len(p['contents'])} itens")
    for i in p["contents"]: print(f"     {i['quantity']}x {i['item_index']}")
