# frozen_string_literal: true

# FASE 0 do catálogo de proficiências — IDIOMAS.
#
#   bundle exec rake dnd:seed_proficiency_languages            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_proficiency_languages  # só relata
#
# Idempotente: casa por `api_index` e nunca apaga nada.
#
# ⚠️ A lista é a UNIÃO das quatro fontes que existiam, não uma lista nova.
# Escrever uma lista nova "limpa" é exatamente o que criou as quatro grafias de
# "Veículos terrestres" — e cortar um valor que parece errado órfã personagem
# real. As fontes conferidas:
#   1. `front-lafiga/src/app/data/languageCatalog.ts`  (22, bate com o livro)
#   2. `api/config/race_rules.yml`                      (12)
#   3. `api/app/services/background_rules.rb` + `Background#rules` (9)
#   4. o que está GRAVADO em `sheets.race_summary.languages` (11)
namespace :dnd do
  # nome, sub-categoria, [apelidos extras]
  IDIOMAS = [
    # ---- Livro do Jogador, tabela IDIOMAS PADRÃO (pg. 123) ----
    ['Comum',    'standard'], ['Anão',   'standard'], ['Élfico',   'standard'],
    ['Gigante',  'standard'], ['Gnômico', 'standard'], ['Goblin',  'standard'],
    ['Halfling', 'standard'], ['Orc',    'standard'],

    # ---- Livro do Jogador, tabela IDIOMAS EXÓTICOS (pg. 123) ----
    ['Abissal', 'exotic'], ['Celestial', 'exotic'], ['Dracônico', 'exotic'],
    ['Infernal', 'exotic'], ['Primordial', 'exotic'], ['Silvestre', 'exotic'],
    ['Subcomum', 'exotic'],
    # O livro grafa "Dialeto Subterrâneo"; "Fala Profunda" é a tradução mais
    # comum noutras edições e entra como apelido para ficha antiga não órfã.
    ['Dialeto Subterrâneo', 'exotic', ['Fala Profunda', 'Deep Speech', 'Undercommon']],

    # ---- Dialetos do Primordial ----
    # ⚠️ O livro é explícito: "o idioma Primordial inclui os dialetos Auran,
    # Aquan, Ignan e Terran" e quem fala um entende os outros. A relação vive
    # no `metadata` para não se perder — a ficha pode dizer "fala Ignan" sem
    # sugerir que Terran seja inacessível.
    ['Aquan', 'primordial_dialect'], ['Auran', 'primordial_dialect'],
    ['Ignan', 'primordial_dialect'], ['Terran', 'primordial_dialect'],

    # ---- Monstro / suplemento ----
    ['Esfinge', 'monster'], ['Língua do Caos', 'monster'],

    # ---- Raciais de suplemento, COM personagem real ----
    ['Aarakocra', 'racial'], ['Minotauro', 'racial'],

    # ---- Secretos de classe ----
    # ⚠️ Não se escolhem: vêm com a classe no nível 1 (features do Druida e do
    # Ladino). Estão no catálogo para poderem ser exibidos e auditados, e é o
    # `metadata['grantable']=false` que impede um mago de os escolher.
    ['Druídico', 'class_secret', ['Druidico', 'Druidic']],
    ['Gíria de Ladrão', 'class_secret', ['Giria de Ladrao', "Thieves' Cant", 'Gíria de Ladrões']],

    # ---- ⚠️ FORA DO LIVRO ----
    # Não está em nenhuma das duas tabelas do PHB pt-BR. Chegou por
    # `background_rules.rb` e é oferecido por 6 antecedentes, mas **nenhuma
    # ficha o tem**. Entra como linha própria e marcado, em vez de ser fundido
    # por palpite com "Dialeto Subterrâneo" — parecem-se, e adivinhar é como se
    # criam apelidos errados. Decisão de produto pendente.
    ['Anão das Profundezas', 'exotic', [], 'homebrew'],
  ].freeze

  DIALETOS_PRIMORDIAIS = %w[Aquan Auran Ignan Terran].freeze
  # Sub-categorias que entram numa escolha livre de idioma.
  SELECIONAVEIS = %w[standard exotic primordial_dialect monster].freeze

  desc 'FASE 0 — semeia o catálogo de proficiências de IDIOMA (DRY_RUN=1 relata)'
  task seed_proficiency_languages: :environment do
    seco = ENV['DRY_RUN'].present?
    criados = atualizados = apelidos = 0

    ActiveRecord::Base.transaction do
      IDIOMAS.each do |nome, sub, extras, fonte|
        idx = "lang-#{Proficiency.normalize(nome).tr(' ', '-')}"
        meta = {}
        meta['grantable'] = false if sub == 'class_secret'
        # ⚠️ `selectable` = aparece numa escolha LIVRE de idioma. É eixo próprio,
        # separado de `grantable`:
        #   - `racial` (Aarakocra, Minotauro) É concedido — pela RAÇA —, mas um
        #     humano não o escolhe numa lista aberta;
        #   - `class_secret` vem da classe no nível 1;
        #   - "Anão das Profundezas" fica de fora enquanto a decisão de produto
        #     não sai (ver abaixo). Os 6 antecedentes que o oferecem continuam a
        #     oferecê-lo pela lista DELES — são coisas diferentes.
        # O resultado é 22, exatamente o que `languageCatalog.ts` já mostrava.
        # A política vive AQUI para o front não voltar a ser dono dela.
        meta['selectable'] = SELECIONAVEIS.include?(sub) && (fonte.nil?)
        meta['dialect_of'] = 'lang-primordial' if sub == 'primordial_dialect'
        meta['dialects'] = DIALETOS_PRIMORDIAIS.map { |d| "lang-#{Proficiency.normalize(d)}" } if nome == 'Primordial'

        p = Proficiency.find_or_initialize_by(api_index: idx)
        novo = p.new_record?
        p.assign_attributes(
          name: nome, category: 'language', sub_category: sub,
          metadata: meta, source: fonte || 'PHB', published: true,
        )
        if seco
          puts "  #{novo ? 'CRIARIA' : 'atualizaria'} #{idx.ljust(28)} #{nome} (#{sub}#{fonte ? ", #{fonte}" : ''})"
        else
          p.save!
        end
        novo ? criados += 1 : atualizados += 1

        next if seco

        # O próprio nome + as variantes conhecidas. `add_alias!` normaliza, então
        # acento e caixa já estão cobertos sem entrada extra.
        # ⚠️ Conta só o que NASCEU. `add_alias!` devolve o registo existente
        # quando já aponta para esta linha (é idempotente de propósito), e
        # contar o retorno truthy fazia a 2ª rodada relatar 35 apelidos novos
        # com zero escrita — relatório que mente é pior do que nenhum.
        ([nome] + Array(extras)).each do |a|
          antes = ProficiencyAlias.count
          p.add_alias!(a)
          apelidos += 1 if ProficiencyAlias.count > antes
        end
      end
      raise ActiveRecord::Rollback if seco
    end

    puts "\n#{seco ? '[DRY RUN] ' : ''}idiomas: #{criados} criados, #{atualizados} já existiam, #{apelidos} apelidos novos"
    puts "total no catálogo: #{Proficiency.of('language').count}" unless seco
  end
end
