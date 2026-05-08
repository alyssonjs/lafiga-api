# frozen_string_literal: true

require 'rails_helper'

# ----------------------------------------------------------------------------
# Audit completo PHB × backgrounds_phb.yml — facetas estáticas dos 13
# antecedentes do PHB (Cap. 4: Personalidade e Antecedentes).
#
# Escopo: dados FIXOS (não dependem de escolhas):
#   - skills (sempre 2, pareadas)
#   - tools (variáveis: 0/1/2 fixos OU "à escolha")
#   - languages.count
#
# Audit descobriu (2026-05-08):
#   - Sage tinha skill "Arcana" (EN) em vez de "Arcanismo" (PT-BR canônico
#     em config/skills.yml). Mesmo padrão do bug "Lidar com Animais" vs
#     "Adestrar Animais" — naming inconsistente entre YAMLs.
#
# Mudanças no `EXPECTED_BY_BG` exigem cruzar com PHB pt-BR
# (`docs/livro_do_jogador.txt` Cap. 4).
# ----------------------------------------------------------------------------
RSpec.describe 'Backgrounds — facetas estáticas × PHB', type: :service do
  EXPECTED_BY_BG = {
    'acolyte' => {
      name: 'Acólito',
      skills: %w[Intuição Religião],
      languages_count: 2
    },
    'criminal' => {
      name: 'Criminoso',
      skills: %w[Enganação Furtividade],
      tools_must_include: ['Ferramentas de ladrão']
    },
    'charlatan' => {
      name: 'Charlatão',
      skills: %w[Enganação Prestidigitação],
      tools_must_include: ['Kit de disfarce', 'Kit de falsificação']
    },
    'entertainer' => {
      name: 'Artista',
      skills: %w[Acrobacia Atuação],
      tools_must_include: ['Kit de disfarce']
    },
    'folk-hero' => {
      name: 'Herói do Povo',
      skills: ['Lidar com Animais', 'Sobrevivência']
    },
    'guild-artisan' => {
      name: 'Artesão da Guilda',
      skills: %w[Intuição Persuasão],
      languages_count: 1
    },
    'hermit' => {
      name: 'Eremita',
      skills: %w[Medicina Religião],
      tools_must_include: ['Kit de herbalismo'],
      languages_count: 1
    },
    'noble' => {
      name: 'Nobre',
      skills: %w[História Persuasão],
      languages_count: 1
    },
    'outlander' => {
      name: 'Forasteiro',
      skills: %w[Atletismo Sobrevivência],
      languages_count: 1
    },
    'sage' => {
      name: 'Sábio',
      # CANÔNICO PT-BR: "Arcanismo" (não "Arcana" — divergência corrigida).
      skills: %w[Arcanismo História],
      languages_count: 2
    },
    'sailor' => {
      name: 'Marinheiro',
      skills: %w[Atletismo Percepção]
    },
    'soldier' => {
      name: 'Soldado',
      skills: %w[Atletismo Intimidação]
    },
    'urchin' => {
      name: 'Órfão',
      skills: %w[Prestidigitação Furtividade],
      tools_must_include: ['Kit de disfarce', 'Ferramentas de ladrão']
    }
  }.freeze

  let(:yaml) { YAML.safe_load(File.read(Rails.root.join('config', 'backgrounds_phb.yml')))['backgrounds'] }

  # Garantia mínima: skills usadas têm que existir em config/skills.yml.
  # Sem isso, a ficha lê o background, procura o skill canônico e não acha
  # — gerando o bug "perícia escolhida não aparece marcada".
  let(:canonical_skill_names) do
    raw = YAML.safe_load(File.read(Rails.root.join('config', 'skills.yml')), aliases: true) || {}
    Array(raw['skills']).map { |s| s['name'] }.to_set
  end

  EXPECTED_BY_BG.each do |bg_id, expected|
    describe "Background '#{bg_id}' (#{expected[:name]})" do
      let(:bg) { yaml[bg_id] }

      it 'está definido em backgrounds_phb.yml' do
        expect(bg).to be_present, "yaml[#{bg_id.inspect}] retornou nil"
      end

      it "name = #{expected[:name].inspect}" do
        expect(bg['name']).to eq(expected[:name])
      end

      it "skills = #{expected[:skills].inspect} (PHB)" do
        got = Array(bg.dig('starting_proficiencies', 'skills')).map(&:to_s)
        expect(got.to_set).to eq(expected[:skills].to_set),
          "#{bg_id}: PHB diz skills #{expected[:skills].sort.inspect}, código tem #{got.sort.inspect}"
      end

      it 'todas as skills declaradas existem em config/skills.yml (PT-BR canônico)' do
        got = Array(bg.dig('starting_proficiencies', 'skills')).map(&:to_s)
        unknown = got.reject { |s| canonical_skill_names.include?(s) }
        expect(unknown).to be_empty,
          "#{bg_id}: skills com naming divergente de config/skills.yml: #{unknown.inspect}.\n" \
          "  Canônicos válidos: #{canonical_skill_names.to_a.sort.inspect}"
      end

      if expected[:tools_must_include]
        it "tools incluem fixos do PHB: #{expected[:tools_must_include].inspect}" do
          got = Array(bg.dig('starting_proficiencies', 'tools')).map(&:to_s)
          expected[:tools_must_include].each do |tool|
            # Match flexível: "Ferramentas de ladrão" no PHB pode estar no YAML
            # capitalizado de forma ligeiramente diferente. Compara case-insensitive.
            expect(got.any? { |g| g.downcase.include?(tool.downcase) }).to be(true),
              "#{bg_id}: tool '#{tool}' (PHB) ausente. Veio: #{got.inspect}"
          end
        end
      end

      if expected[:languages_count]
        it "languages.count = #{expected[:languages_count]}" do
          count = bg.dig('starting_proficiencies', 'languages', 'count')
          expect(count).to eq(expected[:languages_count]),
            "#{bg_id}: PHB diz languages.count #{expected[:languages_count]}, " \
            "código tem #{count.inspect}"
        end
      end
    end
  end

  describe 'Audit cobertura completa' do
    it 'EXPECTED_BY_BG cobre os 13 antecedentes do PHB' do
      expect(EXPECTED_BY_BG.size).to eq(13)
    end

    it 'backgrounds_phb.yml contém pelo menos os 13 do PHB' do
      defined_ids = yaml.keys.to_set
      missing = EXPECTED_BY_BG.keys.to_set - defined_ids
      expect(missing).to be_empty,
        "Backgrounds PHB ausentes: #{missing.to_a.inspect}"
    end
  end
end
