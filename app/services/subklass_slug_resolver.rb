# frozen_string_literal: true

# Slugs vindos do front (PT ou legado) → `sub_klasses.api_index` alinhado ao import D&D / rake aliases.
class SubklassSlugResolver
  SLUG = {
    # Barbaro: NÃO precisa alias para 'berserker'. O api_index no DB já é
    # 'berserker' (SRD), criado pelo dnd:import. Antes existia
    # 'berserker' => 'caminho-do-furioso' aqui mas 'caminho-do-furioso' nunca
    # foi seedado, e o resolver acabava transformando o slug que JÁ FUNCIONAVA
    # ('berserker') em outro inexistente. Bug Phase 4.
    'corruptor' => 'fiend',
    # Paladino: api_indexes do DB são 'devotion'/'ancients'/'vengeance' (SRD),
    # não 'oath_of_*'. As versões 'oath_of_devotion'/etc nunca foram seedadas;
    # antes da Phase 4 o resolver mapeava para esses slugs inexistentes e
    # quebrava o LevelUpService L3+ sempre que o jogador escolhesse o
    # juramento PT-BR no wizard.
    'juramento-de-devocao' => 'devotion',
    'juramento-dos-ancioes' => 'ancients',
    'juramento-de-vinganca' => 'vengeance',
    # Clérigo: ids SRD em ClassRules / draft → api_index em subclass_overrides.yml (SubKlass no DB)
    'life' => 'dominio-da-vida',
    'light' => 'dominio-da-luz',
    'knowledge' => 'dominio-do-conhecimento',
    'nature' => 'dominio-da-natureza',
    'tempest' => 'dominio-da-tempestade',
    'trickery' => 'dominio-da-trapaca',
    'war' => 'dominio-da-guerra',
    # Druida: ClassRules usa ids SRD; SubKlass.api_index vem de subclass_overrides.yml.
    # Sem esses aliases, `selectedSubclass` enriquecido pelo front (ruleSlug='moon'|'land')
    # estoura "SubKlass 'moon' não encontrada" no LevelUpService.
    'moon' => 'circulo-da-lua',
    'land' => 'circulo-da-terra',
    # Monge: idem (open_hand/shadow/four_elements em ClassRules vs slugs PT no DB).
    'open_hand' => 'mao-aberta',
    'open-hand' => 'mao-aberta',
    'shadow' => 'sombra',
    'four_elements' => 'quatro-elementos',
    'four-elements' => 'quatro-elementos'
    # Mago: NÃO precisa alias. O subclass_overrides.yml grava as escolas com
    # api_index 'escola-de-<nome>' (ex.: 'escola-de-evocacao'). O fallback
    # `ascii_slug` no resolver devolve o próprio slug PT-BR e o LevelUpService
    # encontra direto. Antes existia 'escola-de-evocacao' => 'evocation' aqui
    # mas 'evocation' nunca foi seedado no DB (o seed cria 'evocacao' sem 'n'
    # como compatibilidade legacy + 'escola-de-evocacao' como canônico),
    # quebrando o LevelUpService L2+ com "SubKlass não encontrada" sempre que
    # o jogador escolhia Evocação no wizard.
  }.freeze

  # Aceita:
  #   - já-slug (ex.: "circulo-vida") → retorna como está (após hit no SLUG)
  #   - nome PT exibido no wizard (ex.: "Círculo da Vida") → "circulo-da-vida"
  # Quem chama (`resolve_subclass_id`) tenta primeiro o resultado bruto; quando não acha,
  # cai no SubKlass.find_by(api_index: ascii_slug) — esse caminho é importante porque o
  # front grava `selectedSubclass` como o nome PT-BR, não como api_index.
  def self.normalize(slug)
    s = slug.to_s.strip.downcase
    return SLUG[s] if SLUG.key?(s)
    SLUG[ascii_slug(s)] || ascii_slug(s)
  end

  # 'Círculo da Vida' → 'circulo-da-vida' (sem acentos, espaços/underscore → '-')
  def self.ascii_slug(text)
    s = text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
    s.gsub(/[\s_]+/, '-').gsub(/[^a-z0-9-]/, '').squeeze('-')
  end
end
