# -*- coding: utf-8 -*-
"""
Tabela EQUIPAMENTO do PHB (pág. 150) → seed.

⚠️ O texto vem em DUAS COLUNAS, cortadas na coluna 53. O pai de um sub-item
(Foco arcano → Bastão/Cajado) tem de ser rastreado POR COLUNA: rastrear global
faz o "Símbolo sagrado" da direita adotar o "Totem" da esquerda, que é foco
druídico.

⚠️ O peso do PHB pt-BR já é em KG (a edição em inglês é lb). O banco é canônico
em kg — não se converte nada, converter dobraria o peso.
"""
import re, json, unicodedata

S = "/private/tmp/claude-501/-Users-alyssonjosesoares-Documents-lafiga-front-lafiga/3d48da8b-c253-4475-b774-cebbdbaf6263/scratchpad/phb"
CORTE = 53
MOEDA = {"po": 1.0, "pp": 0.1, "pc": 0.01}

def num(t): return float(t.replace(".", "").replace(",", "."))

CELULA = re.compile(
    r"^(?P<nome>.+?)\s{2,}(?P<val>[\d.,]+)\s*(?P<moeda>po|pp|pc)\s+(?P<peso>[\d.,]+\s*kg|–|-)\s*$"
)

itens, pendentes = [], []
pai = {0: None, 1: None}   # ← por COLUNA

for linha in open(S + "/tabela_bruta.txt"):
    linha = linha.rstrip("\n")
    if not linha.strip(): continue
    for col, meia in enumerate((linha[:CORTE], linha[CORTE:])):
        if not meia.strip(): continue
        indent = len(meia) - len(meia.lstrip())
        # Indentação MEDIDA no texto, não suposta: esquerda 7 (sub 10),
        # direita 3 (sub 6). Errar aqui faz item normal herdar pai alheio —
        # foi assim que "Pá" e "Sabão" viraram "Munição: …".
        indentado = indent >= (10 if col == 0 else 6)
        m = CELULA.match(meia.strip())
        if not m:
            cru = meia.strip()
            # Cabeçalho de grupo: sem número e curto (Foco arcano, Munição…).
            if cru and not re.search(r"\d", cru) and len(cru) < 30:
                pai[col] = cru
            elif cru:
                pendentes.append(cru)
            continue
        nome = m.group("nome").strip()
        peso_txt = m.group("peso")
        peso = 0.0 if peso_txt in ("–", "-") else num(peso_txt.replace("kg", "").strip())
        preco = round(num(m.group("val")) * MOEDA[m.group("moeda")], 4)
        rotulo = f"{pai[col]}: {nome}" if (indentado and pai[col]) else nome
        itens.append({"name": rotulo, "value_gp": preco, "weight_kg": peso,
                      "parent": pai[col] if indentado else None})
        if not indentado: pai[col] = None

print(f"itens: {len(itens)} | não parseadas: {len(pendentes)}")
for p in pendentes[:8]: print("   ?", p)
print("\nsub-itens (pai correto?):")
for i in itens:
    if i["parent"]: print(f"   {i['name']:<36} {i['value_gp']} po, {i['weight_kg']} kg")
json.dump(itens, open(S + "/tabela.json", "w"), ensure_ascii=False, indent=1)
