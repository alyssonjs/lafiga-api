# frozen_string_literal: true

# Um artigo da wiki — o texto que a mesa lê, agora no banco (07/10/2026).
#
# Antes disto o texto vivia em `const SEED` dentro de cada página do front e
# era carregado para um `useState`: o que se editava sumia ao recarregar e
# ninguém mais via. Ver `CreateWikiArticles` para o histórico.
#
# O FORMATO é aberto de propósito (`data` jsonb). Cada seção tem os seus
# campos, declarados em `wikiEditorConfigs.ts` no front — Deus tem `domains` e
# `clericNote`, Plano tem `inhabitants` e `dangers`. Fixá-los em colunas
# obrigaria a uma migration sempre que o Mestre quisesse um campo novo, que é
# exatamente o que esta feature quer evitar.
class WikiArticle < ApplicationRecord
  # Mesma gramática de slug de `WikiSection`: alfanumérico + hífen, sem hífen
  # nas pontas. CamelCase aceito porque os slugs canônicos das built-ins são
  # camelCase (`racesLore`) e o `section` daqui aponta para eles.
  SLUG_REGEX = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}[A-Za-z0-9])?\z/

  # Teto do corpo de um artigo. Não é regra de negócio — é barreira contra um
  # POST que encha a coluna com megabytes e derrube a listagem da seção, que é
  # lida inteira de uma vez.
  MAX_DATA_BYTES = 64 * 1024

  validates :section, presence: true, format: { with: SLUG_REGEX }
  validates :slug, presence: true, format: { with: SLUG_REGEX },
                   uniqueness: { scope: :section, message: 'já existe nesta seção' }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :data_e_um_objeto
  validate  :data_cabe_no_teto

  scope :in_section, ->(section) { where(section: section.to_s) }
  scope :ordered, -> { order(:position, :id) }

  # O front consome `{ id, section, data }` — o mesmo formato que o
  # `WikiArticleContext` já usava em memória, para a troca de fonte (useState →
  # API) não mexer em nenhuma página.
  #
  # ⚠️ `id` aqui é o SLUG, não a chave primária: é ele que as páginas usam para
  # navegar (`/wiki/deuses/editar/god-01`) e que o `data.id` do seed carregava.
  # Devolver o id numérico do banco quebraria todo link já guardado.
  def as_payload
    {
      id: slug,
      section: section,
      position: position,
      data: (data || {}).merge('id' => slug),
      updated_at: updated_at
    }
  end

  private

  def data_e_um_objeto
    return if data.is_a?(Hash)

    errors.add(:data, 'deve ser um objeto')
  end

  def data_cabe_no_teto
    return unless data.is_a?(Hash)
    return if data.to_json.bytesize <= MAX_DATA_BYTES

    errors.add(:data, "excede #{MAX_DATA_BYTES / 1024} KB")
  end
end
