# Regras de Negócio – D&D 5e (Criação e Progressão de Personagem)

Objetivo: consolidar as regras essenciais de criação e evolução de personagens de Dungeons & Dragons 5ª Edição e como mapeá-las ao modelo atual do projeto.

## Entidades e Mapeamento ao Modelo
- Raça/Sub-raça: `Race` e `SubRace` (1:N). Regra: sub-raça deve pertencer à raça.
- Classe/Subclasse: `Klass` e `SubKlass` (1:N). Regra: subclasse pertence à classe e é escolhida em nível específico da classe.
- Níveis de Classe: `ClassLevel` (1:N com `Klass`, níveis 1..20). Associa a recursos de classe via N:N com `Feature`.
- Magia da Classe: `Spellcasting` (1:1 com `ClassLevel`). Guarda progressão de magia/slots/cantrips quando aplicável.
- Recursos/Talentos: `Feature`. Pode representar traços de raça, recursos de classe e talentos (feats). Ligação a níveis de classe via tabela de junção.
- Personagem: `Character` (pertence a `User`, opcionalmente a `Group`). Ficha única via `Sheet`.
- Ficha: `Sheet` (1:1 com `Character`). Guarda `race`, `sub_race` e relação com classes.
- Classe na Ficha: `SheetKlass` (N:N entre `Sheet` e `Klass`, com atributos: `level` 1..20 e `sub_klass` opcional).

Observações do modelo atual
- `Sheet` valida que `sub_race` pertence à `race`.
- `SheetKlass` valida `level` ∈ [1,20] e que `sub_klass` pertence à `klass`.
- Multiclasse é suportado via múltiplos `SheetKlass` para a mesma `Sheet` (somatório de níveis limitado a 20).

## Fluxo de Criação de Personagem
1) Definir Conceito e Atributos
- Pontos de habilidade (STR/DEX/CON/INT/WIS/CHA) definidos por método da mesa (ex.: point-buy 27, rolagem, array padrão). Não há persistência direta hoje; pode ser derivado/capturado na `Sheet` no futuro.

2) Escolher Raça e Sub-raça
- Concede traços raciais (velocidade, idiomas, proficiências, `Feature`s raciais).
- No modelo: `sheet.race_id` e `sheet.sub_race_id` (opcional). Traços podem ser representados por `Feature`s associadas à raça (quando necessário, via service/seed).

3) Escolher Classe Inicial
- Define DV de vida (Hit Die), perícias e salvaguardas, proficiências de equipamentos, e recursos de classe de nível 1.
- No modelo: criar `SheetKlass(sheet: sheet, klass: X, level: 1)`. Associar `Feature`s de `ClassLevel(klass,1)`.

4) Definir Antecedente (Background)
- Concede perícias, ferramentas, idiomas e um recurso de background. No modelo atual, `Character.background` é um texto; detalhes podem ser capturados como `Feature`s genéricos via service/seed.

5) Vida (HP)
- Nível 1: HP = DV máximo da classe + modificador de CON.
- Níveis seguintes: rolagem do DV ou média fixa (ex.: d8 → +5) + mod CON por nível da classe que aumentou.
- HP total deriva da soma por classe; persistência pode ser calculada ou armazenada na `Sheet` se necessário.

6) Proficiência
- Bônus de proficiência por nível total do personagem:
  - Nível 1–4: +2; 5–8: +3; 9–12: +4; 13–16: +5; 17–20: +6.
- Use o nível total (soma de `SheetKlass.level`) para derivar.

7) Subclasse (Arquetipo)
- Escolhida em nível específico por classe (geralmente 3; algumas no 1 ou 2). Ex.: Clérigo 1, Druida 2, Guerreiro 3.
- No modelo: setar `sheet_klass.sub_klass_id` quando o nível da classe alcançar o mínimo definido. A regra do “nível de subclasse” pode ser parametrizada via seed/constante por `Klass`.

8) Magias (quando aplicável)
- Progressão definida por classe/nível (cantrips conhecidos, magias preparadas/conhecidas, slots por círculo).
- No modelo: consultar `Spellcasting` ligado ao `ClassLevel` da classe relevante e derivar a soma correta (atenção às regras de multiclasse para conjuradores).

9) Aprimoramentos de Atributo (ASI) e Talentos (Feats)
- Em geral nos níveis de classe: 4, 8, 12, 16, 19 (algumas classes têm adicionais).
- Jogador escolhe: +2 em um atributo, +1 em dois atributos distintos, ou 1 talento se permitido.
- No modelo: representar talentos como `Feature`s atribuídas ao personagem via camada de serviço.

## Progressão (Level Up)
- Nível do Personagem: soma de níveis de todas as `SheetKlass` (máx. 20).
- Ao subir 1 nível, escolher a classe que avança:
  1) Incrementar `sheet_klass.level` para a classe escolhida (ou criar um novo `SheetKlass` se iniciar multiclasse).
  2) Conceder `Feature`s de `ClassLevel(klass, novo_nível)` via vínculo ao personagem (ex.: tabela de junção personagem↔feature ou materializar em cache na `Sheet`).
  3) Atualizar HP com DV da classe elevada + mod CON.
  4) Se o novo nível for elegível a ASI/Feat, aplicar a escolha (atributos ou `Feature` de talento).
  5) Se atingir o nível de escolha de subclasse e ainda não definida, setar `sub_klass`.
  6) Atualizar progressão de magia consultando `Spellcasting` do novo `ClassLevel` (e, em multiclasse, aplicar as regras de conjuração combinada quando aplicável).

Validações recomendadas
- `SheetKlass.level` ∈ [1,20] (já existe) e soma dos níveis ≤ 20.
- `sub_klass` só pode ser definida/alterada quando o nível de classe alcançar o limite mínimo.
- `sub_race` deve pertencer à `race` (já existe).
- Ao criar/agregar `Feature`s, garantir unicidade por origem/nível.

## Regras de Conjuração – Notas
- Conjuradores de preparação (ex.: Clérigo, Druida, Mago): magias preparadas = modificador de atributo chave + nível da classe (mínimo 1), conforme a classe.
- Conjuradores de magias conhecidas (ex.: Bardo, Feiticeiro): número de magias conhecidas por nível conforme tabela da classe.
- Slots de magia: definidos por `Spellcasting` por nível da classe; em multiclasse, usar a regra combinada para “Conjuradores” somando níveis efetivos conforme o PHB.

## Multiclasse – Resumo
- Requisitos mínimos de atributos para multiclasse (ex.: STR/DEX/INT/WIS/CHA mínimos) – implementar como validação opcional.
- Proficiências de multiclasse: concedidas apenas no primeiro nível da nova classe conforme regras.
- Conjuração multiclasse: combinar níveis de classes conjuradoras para slots; magias conhecidas/preparadas permanecem por classe.

## Integração com o Projeto
- Seeds: popular `Klass`, `SubKlass`, `ClassLevel(1..20)`, `Feature`s por nível e `Spellcasting` por nível quando cabível.
- Services:
  - Criação de personagem: orquestrar `Sheet`, `SheetKlass(level:1)`, traços raciais e recursos de nível 1.
  - Level up: aplicar regras de incremento de `SheetKlass`, `Feature`s, HP, ASI/Feat e subclasse.
  - Cálculos derivados: bônus de proficiência, DC de magia, ataque mágico, proficiências de armas/armaduras/skills (podem ser computados sob demanda).
- Endpoints: expor contratos coerentes com `{ character/sheet, meta }` e evitar N+1 com `includes`.

## Campos/Parametrizações Úteis (sugestões)
- Em `Klass`: `subclass_level` (nível da escolha de subclasse) – pode ser mantido via seed ou constante.
- Em `Feature`: `source_type`/`source_id` (ex.: race, class_level, feat) para rastrear origem e evitar duplicidade.
- Em `Spell`: atributo da habilidade chave (INT/WIS/CHA) e escolas/nível da magia.

## Exemplos de Fluxo
- Personagem 1º nível (Guerreiro 1):
  - `sheet.race=Humano`, `sheet.sub_race=nil`.
  - `sheet_klass(klass=Guerreiro, level=1, sub_klass=nil)`.
  - Features: proficiências e estilo de luta (conforme `ClassLevel` 1 do Guerreiro).
  - HP: max do d10 + mod CON.
- Personagem 5º nível (Guerreiro 3 / Ladino 2):
  - `sheet_klass(Guerreiro).level=3`, definir `sub_klass` do Guerreiro (ex.: Campeão).
  - `sheet_klass(Ladino).level=2`.
  - Proficiência total: +3 (nível 5).
  - Features: somatório das de Guerreiro 1–3 e Ladino 1–2; ASI no Guerreiro 4 ainda não obtido.

Referências
- PHB 5e (Player’s Handbook) – regras gerais de criação e progressão. Este documento é um resumo técnico para implementação, não substitui o livro.

