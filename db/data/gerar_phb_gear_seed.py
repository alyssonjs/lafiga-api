# -*- coding: utf-8 -*-
"""Tabela do PHB → `phb_gear_seed.json` (o que o rake importa)."""
import json, re, unicodedata

S = "/private/tmp/claude-501/-Users-alyssonjosesoares-Documents-lafiga-front-lafiga/3d48da8b-c253-4475-b774-cebbdbaf6263/scratchpad/phb"

def slug(s):
    s = unicodedata.normalize("NFD", str(s))
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", s.lower())).strip("-")

# `kind` por item. Fora desta tabela tudo é `gear` — a tabela do PHB é de
# EQUIPAMENTO, e o resto (ferramentas, armas, armaduras) tem tabela própria.
KIND = {
    "flechas-20": ("ammunition", "ammunition"), "virotes-20": ("ammunition", "ammunition"),
    "balas-de-funda-20": ("ammunition", "ammunition"), "zarabatana-50": ("ammunition", "ammunition"),
    "acido-vidro": ("consumable", "alchemical"), "fogo-alquimico-frasco": ("consumable", "alchemical"),
    "agua-benta-frasco": ("consumable", "alchemical"),
    "veneno-basico-frasco": ("consumable", "poison"),
    "pocao-de-cura": ("consumable", "potion"), "antidoto-vidro": ("consumable", "potion"),
    "racoes-de-viagem-1-dia": ("consumable", "supply"), "tocha": ("consumable", "supply"),
    "vela": ("consumable", "supply"), "cantil": ("consumable", "supply"),
    "oleo-frasco": ("consumable", "supply"),
    "livro": ("book", None), "grimorio": ("book", None),
}

# Itens que JÁ EXISTEM com nome torto. Explícito de propósito: reparar por
# semelhança fundiria "Livro" com "Livro yuan-ti". Aqui só entra o que foi
# conferido a olho — o resto é criado.
REPAROS = {
    "piton": "pitons",
    "racoes-de-viagem-1-dia": "racoes",
    "esferas-sacola-com-1-000": "saco-com-esferas",
    "roupas-de-viajante": "roupa-de-viajante",
    "corda-de-canhamo-15-metros": "corda-15m",
}
# ⚠️ `Estrepes 20` está no catálogo como `kind: armor` — estrepe não é
# armadura. O rake corrige o kind junto com o preço.
# ⚠️ Itens PRÉ-EXISTENTES com kind errado. Estrepe, martelo e pá estavam
# catalogados como `armor` — nenhum é armadura, e nessa aba ninguém os acha.
CORRIGE_KIND = {"estrepes-20": "gear", "martelo": "gear", "pa": "gear"}

tab = json.load(open(S + "/tabela.json"))
saida = []
for t in tab:
    base = t["name"].split(": ", 1)[-1]
    # "Foco arcano: Bastão" → "Bastão (foco arcano)": lê melhor numa lista, e o
    # pai é a informação que distingue o Bastão do foco do bastão-arma.
    nome = f"{base} ({t['parent'].lower()})" if t["parent"] and t["parent"] != "Munição" else base
    idx = slug(nome)
    kind, cat = KIND.get(slug(base), ("gear", None))
    # ⚠️ `category` EXPLÍCITA no gear: o balde `:gear` usa `where.not(...)`, que
    # é NULL-unsafe — item com category nil fica INVISÍVEL em toda aba. Foi o
    # que aconteceu com 77 destes na primeira rodada.
    if kind == "gear" and cat is None:
        cat = "equipment"
    saida.append({
        "api_index": idx, "name": nome, "kind": kind, "category": cat,
        "value_gp": t["value_gp"], "weight_kg": t["weight_kg"],
        "source": "PHB — Equipamento",
        "repair_index": REPAROS.get(slug(base)),
        "fix_kind": CORRIGE_KIND.get(slug(base)),
    })

json.dump(saida, open(S + "/phb_gear_seed.json", "w"), ensure_ascii=False, indent=1)
import collections
print("itens:", len(saida))
print("por kind:", dict(collections.Counter(i["kind"] for i in saida)))
print("reparos declarados:", sum(1 for i in saida if i["repair_index"]))
print("\namostra:")
for i in saida[:3] + [x for x in saida if x["repair_index"]][:3]:
    print(f"  {i['api_index']:<30} {i['name']:<32} {i['kind']:<11} {i['value_gp']} po {i['weight_kg']} kg")
