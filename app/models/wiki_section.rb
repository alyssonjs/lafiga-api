# frozen_string_literal: true

# Wiki sidebar entry — fonte de verdade compartilhada entre todos os
# usuarios. Built-ins sao seedadas em `db/seeds.rb` (BUILT_IN_DEFAULTS) e
# nao podem ser destruidas. Customs sao criadas pelo DM via
# `Api::V1::Admin::WikiSectionsController`.
#
# Slugs validos: alfanumerico + hifen, 1..40 chars, sem hifen no inicio
# ou fim. CamelCase aceito para preservar slugs canonicos das built-ins
# (ex.: `racesLore` espelha `BUILT_IN_WIKI_SECTIONS` em
# `WikiArticleContext.tsx`). Customs criadas pelo front passam por
# `slugify` que ja gera lowercase + hifen — este regex e a barreira final
# para POSTs diretos na API.
class WikiSection < ApplicationRecord
  SLUG_REGEX = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}[A-Za-z0-9])?\z/

  # Catalogo canonico de ícones aceitos. Mantido em sincronia com
  # `WIKI_ICON_OPTIONS` no front (`WikiSectionsContext.tsx`). Validar aqui
  # impede que um POST malformado quebre a renderizacao da sidebar com um
  # `iconName` desconhecido.
  ALLOWED_ICONS = %w[
    BookOpen Globe Sparkles Crown Flame Shield Users Landmark Star
    Castle Compass Map Skull Sword Anchor Feather Mountain TreeDeciduous
    Settings
  ].freeze

  # Built-ins canonicas. Slug => default (label/description/icon_name).
  # Usado pelo seed e por `Api::V1::Admin::WikiSectionsController` para
  # bloquear destroy. A ordem do hash define a posicao default.
  BUILT_IN_DEFAULTS = {
    'planes'       => { label: 'Os Planos',     description: 'Os planos de existencia',  icon_name: 'Globe'    },
    'entities'     => { label: 'As Entidades',  description: 'Seres cosmicos de poder',  icon_name: 'Sparkles' },
    'gods'         => { label: 'Os Deuses',     description: 'O panteao Lafigardiano',   icon_name: 'Crown'    },
    'creation'     => { label: 'A Criacao',     description: 'O nascimento do mundo',    icon_name: 'Flame'    },
    'asthrsherans' => { label: 'Asthrsherans',  description: 'Os pilares da realidade',  icon_name: 'Shield'   },
    'racesLore'    => { label: 'As Racas',      description: 'Lore das racas jogaveis',  icon_name: 'Users'    },
    'kingdoms'     => { label: 'Os Reinos',     description: 'Reinos e nacoes',          icon_name: 'Landmark' },
    'guilds'       => { label: 'As Guildas',    description: 'Organizacoes e ordens',    icon_name: 'BookOpen' }
  }.freeze

  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_REGEX }
  validates :label, presence: true, length: { maximum: 60 }
  validates :description, length: { maximum: 240 }, allow_blank: true
  validates :icon_name, presence: true, inclusion: { in: ALLOWED_ICONS }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :built_in, inclusion: { in: [true, false] }

  scope :ordered, -> { order(position: :asc, id: :asc) }

  # Path canonico exposto na API. Built-ins tem rotas dedicadas no front
  # (`/wiki/<slug-pt-br>`); customs vao sob `/wiki/c/<slug>` (prefixo `c/`
  # evita colisao). Mantido em paridade com BUILT_IN_DEFINITIONS no front.
  BUILT_IN_PATHS = {
    'planes'       => '/wiki/planos',
    'entities'     => '/wiki/entidades',
    'gods'         => '/wiki/deuses',
    'creation'     => '/wiki/criacao',
    'asthrsherans' => '/wiki/asthrsherans',
    'racesLore'    => '/wiki/racas',
    'kingdoms'     => '/wiki/reinos',
    'guilds'       => '/wiki/guildas'
  }.freeze

  def path
    return BUILT_IN_PATHS.fetch(slug) if built_in
    "/wiki/c/#{slug}"
  end

  def as_payload
    {
      id: id,
      slug: slug,
      label: label,
      description: description.presence,
      icon_name: icon_name,
      position: position,
      built_in: built_in,
      path: path
    }
  end
end
