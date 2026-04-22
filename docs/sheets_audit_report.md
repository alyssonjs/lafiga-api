# Audit das fichas importadas vs Rules canonicas

Cruza `api/docs/imported_sheets.json` (39 fichas) contra:
- `Race` (DB): 12 races, 27 subraces
- `Klass` (DB): 13 classes, 142 subklasses
- `SubclassRules` (alternativas extras): 72 subclasses
- `FeatRules::RULES` (35 feats)
- `ClassRules::FIGHTING_STYLES` (6 estilos)

## Sumario

| Categoria | Qtd | % do auditavel |
|---|---:|---:|
| OK total (sem issues, sem warns) | 35 | 100.0% |
| OK com warnings | 0 | 0.0% |
| BLOQUEADO (issues) | 0 | 0.0% |
| **Auditavel** | **35** | 100% |
| Skipped (template / fora do escopo) | 4 | — |
| **Total fichas** | **39** | — |

## Issues mais frequentes (bloqueiam criacao)


## Warnings mais frequentes (criacao funciona, mas perde fidelidade)


## Detalhe por personagem

| # | Aba | Personagem | Class/Sub | Race/Sub | Lvl | Issues | Warns |
|---|---|---|---|---|---:|---:|---:|
| 1 | Nayara | ABIGAIL LE FAY | wizard/- | human/standard | 9 | 0 | 0 |
| 2 | Fininho | ADIMAEL | ranger/rastreador_urbano | elf/wood | 9 | 0 | 0 |
| 3 | Caio | STIVI MAGAL | rogue/cacador-de-tesouros | gnome/rock | 9 | 0 | 0 |
| 4 | Allan | Sirius Bastião de Ferro | fighter/cavaleiro-arcano | human/standard | 7 | 0 | 0 |
| 5 | João | Lenny | rogue/assassino | half_elf/- | 7 | 0 | 0 |
| 6 | Amani | Amani Okoye | paladin/juramento-misericordia | human/standard | 4 | 0 | 0 |
| 7 | Levi | Igris Elthred | fighter/champion | half_orc/- | 4 | 0 | 0 |
| 8 | Ellel | Ellel Pés Macios | cozinheiro/- | halfling/- | 1 | 0 | 0 |
| 9 | Kalt | Kalt | druid/circulo-da-terra | human/variant | 3 | 0 | 0 |
| 10 | Miguel | Rolander | paladin/- | human/standard | 7 | 0 | 0 |
| 11 | Milo | Milo | druid/circulo-da-lua | halfling/- | 6 | 0 | 0 |
| 12 | Bult | Bult Seewell | barbarian/barbaro-cicatrizes-runicas | minotaur/- | 5 | 0 | 0 |
| 13 | Namari | Namari | fighter/mestre-de-batalha | dwarf/hill | 5 | 0 | 0 |
| 14 | Bellamy | Bellamy | warlock/archfey | aarakocra/cypselanos | 5 | 0 | 0 |
| 15 | Thaindriel | Thaindriel | monk/sombra | elf/wood | 6 | 0 | 0 |
| 16 | Trall | Thralliant | barbarian/guerreiro-urso | half_elf/- | 5 | 0 | 0 |
| 17 | Alieksey | Darkmenos | warlock/- | tiefling/infernal | 5 | 0 | 0 |
| 18 | Lyra | Lyra El'Asah | ranger/flagelo-dos-inimigos | elf/wood | 6 | 0 | 0 |
| 19 | Shanti | Shanti | cleric/dominio-da-vida | half_elf/- | 5 | 0 | 0 |
| 20 | Joe | Joe | bard/colegio-comedia | half_elf/- | 6 | 0 | 0 |
| 21 | Kanlu | Kanlu Wanderblade | sorcerer/feiticaria-da-espada | elf/wood | 8 | 0 | 0 |
| 22 | Orsik | Orsik Stoneforge | cleric/dominio-da-guerra | dwarf/- | 7 | 0 | 0 |
| 23 | Torres | Vallen Evenwood | fighter/- | human/standard | 1 | 0 | 0 |
| 24 | Lucinano | Avalon Mellion | wizard/navegacao-planar | elf/high | 4 | 0 | 0 |
| 25 | Ruric | Ruric | barbarian/furioso-imortal | half_orc/- | 6 | 0 | 0 |
| 26 | Ainor | Ainor | bard/colegio-fortuna | human/variant | 5 | 0 | 0 |
| 27 | Aberrama | Aberama Gold | fighter/atirador_inigualavel | tiefling/infernal | 8 | 0 | 0 |
| 28 | Ysari | Ysari Nyrae’vell | cleric/dominio-da-tempestade | aarakocra/- | 4 | 0 | 0 |
| 29 | Jamerson | Erlingorn | ranger/- | halfling/stout | 3 | 0 | 0 |
| 30 | Rorinar | Rorinar | barbarian/guerreiro-urso | dwarf/hill | 4 | 0 | 0 |
| 31 | Valac | Valac Gigamaquia | wizard/maestria-dos-automatos | gnome/rock | 4 | 0 | 0 |
| 32 | Sabrino | Sabrino | warlock/great_old_one | half_elf/- | 4 | 0 | 0 |
| 33 | Nikos | Nikos | monk/- | human/standard | 3 | 0 | 0 |
| 34 | Sanda | Sanda | monk/caminho_mestre_bebado | human/variant | 3 | 0 | 0 |
| 35 | Modelo |  | ?/- | ?/- | 1 | 0 | 1 |
| 36 | Angelina | Angelina | warlock/patrono-morte | tiefling/infernal | 10 | 0 | 0 |
| 37 | Drugoy | Drugoy | barbarian/berserker | ?/- | 10 | 0 | 1 |
| 38 | Tony Ramos | Tony Ramos | druid/verdejante | ?/- | 10 | 0 | 1 |
| 39 | Pandora | Pandora | bard/colegio-pavor | ?/- | 10 | 0 | 1 |

## Personagens BLOQUEADOS

## Personagens com WARNINGS apenas

