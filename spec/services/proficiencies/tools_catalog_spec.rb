# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'yaml'

# FASE 0 do catálogo — FERRAMENTAS e VEÍCULOS.
#
# ⚠️ É aqui que mora o pior histórico do projeto: "Veículos terrestres" chegou a
# existir em QUATRO grafias, e 14 proficiências ficaram órfãs em silêncio porque
# duas listas rivais para a mesma coisa divergiram. O que este guarda prende é
# que o catálogo continue sendo a UNIÃO das fontes, e não uma lista nova.
RSpec.describe 'catálogo de ferramentas e veículos (fase 0)' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before do
    Proficiency.where(category: %w[tool vehicle]).destroy_all
    Rake::Task['dnd:seed_proficiency_tools'].reenable
    Rake::Task['dnd:seed_proficiency_tools'].invoke
  end

  def resolve(v) = Proficiency.resolve(v)

  it 'semeia 46 ferramentas e 2 veículos' do
    expect(Proficiency.of('tool').count).to eq(46)
    expect(Proficiency.of('vehicle').count).to eq(2)
  end

  describe '⚠️ as QUATRO grafias de veículo apontam para a MESMA linha' do
    it 'todas resolvem, e para a mesma proficiência' do
      # Foi a divergência entre estas quatro que deixou Herói do Povo e Soldado
      # SEM a proficiência que o antecedente concede — em silêncio, porque o
      # modo de falha é a linha não aparecer.
      terrestres = ['Veículos (terrestres)', 'Veículos terrestres',
                    'Veículos (terrestre)', 'vehicles_land']
      linhas = terrestres.map { |v| resolve(v) }
      expect(linhas).to all(be_present)
      expect(linhas.map(&:id).uniq.size).to eq(1)
      expect(linhas.first.category).to eq('vehicle')
      expect(linhas.first.sub_category).to eq('land')
    end

    it 'e o mesmo para os aquáticos' do
      aquaticos = ['Veículos (aquáticos)', 'Veículos aquáticos',
                   'Veículos (aquático)', 'vehicles_water']
      expect(aquaticos.map { |v| resolve(v)&.id }.uniq).to eq([resolve('Veículos (aquáticos)').id])
    end
  end

  describe '⚠️ veículo CONCRETO não é proficiência' do
    it 'Biga, Carroça, Galera e afins ficam de fora' do
      # O `VEHICLE_CATALOG` do front lista os 10 como se fossem proficiência.
      # Não são: são ITENS (`dnd:seed_phb_vehicles`). Ninguém é proficiente em
      # "Galera" — é proficiente em "Veículos (aquáticos)". Medido: nenhuma
      # ficha tem veículo concreto gravado como proficiência.
      %w[Biga Carroça Carruagem Trenó Galera Veleiro Dracar].each do |v|
        expect(resolve(v)).to be_nil, "#{v} não devia ser proficiência"
      end
    end
  end

  describe 'as fontes do backend reconciliam' do
    it 'background_rules.rb — os 48 valores resolvem' do
      # ⚠️ Esta lista tinha "Kit de Disfarce" E "Kit de disfarce" na MESMA
      # lista, além de Coureiro/Vidraceiro/Marceneiro/Tecelão, que são outras
      # palavras para ofícios já nomeados de outro jeito no front.
      ofertas = BackgroundRules::RULES.values.flat_map do |bg|
        Array(bg[:tools]).flat_map do |t|
          if t.is_a?(String) then [t]
          elsif t.is_a?(Hash)
            t.values.flat_map { |sub| sub.is_a?(Hash) ? Array(sub[:choices] || sub['choices']) : [] }
          else [] end
        end
      end
      expect(ofertas).not_to be_empty
      expect(ofertas.uniq.reject { |v| resolve(v) }).to eq([])
    end

    it 'race_rules.yml — inclusive o "Voz (instrumento)"' do
      yaml = YAML.load_file(Rails.root.join('config', 'race_rules.yml'))
      vistos = []
      anda = lambda do |n|
        case n
        when Hash
          t = n.dig('proficiencies', 'tools')
          if t.is_a?(Hash)
            vistos.concat(Array(t['fixed'])); vistos.concat(Array(t['choices']))
          elsif t.is_a?(Array)
            vistos.concat(t.select { |x| x.is_a?(String) })
          end
          n.each_value { |v| anda.call(v) }
        when Array then n.each { |v| anda.call(v) }
        end
      end
      anda.call(yaml)
      expect(vistos).not_to be_empty
      expect(vistos.uniq.reject { |v| resolve(v) }).to eq([])
    end

    it 'o que está GRAVADO em class_summary.tools resolve' do
      # Os 12 valores distintos medidos nas 69 fichas reais de dev.
      gravados = ['Alaúde', 'Charamela', 'Ferramentas de Artesão (Cozinheiro)',
                  'Ferramentas de Ladrão', 'Flauta', 'Flauta de Pã', 'Gaita de Foles',
                  'Kit de Herbalismo', 'Lira', 'Tambor', 'Trompa', 'Violino']
      expect(gravados.reject { |v| resolve(v) }).to eq([])
    end
  end

  describe 'a união preserva o que tem uso, e marca o que é de fora' do
    it 'os 6 instrumentos que só o front tinha continuam' do
      # Charamela, Cítara, Cornamusa, Viola, Saltério e Trompa têm escolha
      # gravada em ficha. Cortá-los para "alinhar ao livro" órfãos essas fichas
      # — foi exatamente o erro que a unificação de ago/2026 já tinha pago.
      %w[Charamela Cítara Cornamusa Viola Saltério Trompa].each do |i|
        expect(resolve(i)&.sub_category).to eq('instrument')
      end
    end

    it 'os 3 do livro que faltavam entraram' do
      %w[Oboé Trombeta Xilofone].each { |i| expect(resolve(i)).to be_present }
    end

    it '⚠️ o que está fora do livro fica MARCADO, não escondido' do
      expect(resolve('Ferramentas de ferreiro de armaduras').source).to eq('homebrew')
      expect(resolve('Voz (instrumento)').source).to eq('homebrew')
      # E ferreiro de armaduras é ofício DIFERENTE de ferreiro — linha própria,
      # não apelido. Fundir por semelhança é como se criam apelidos errados.
      expect(resolve('Ferramentas de ferreiro de armaduras'))
        .not_to eq(resolve('Ferramentas de ferreiro'))
    end
  end

  describe 'o nome do LIVRO resolve, mesmo não sendo o canônico' do
    it 'as 4 divergências apontam para o nome em uso' do
      # ⚠️ O canônico é o nome EM USO, não o do livro: o catálogo de `Item` (o
      # que o jogador compra) já usa os do front, e adotar o livro criaria uma
      # divergência NOVA entre proficiência e item.
      {
        'Ferramentas de coureiro'   => 'Ferramentas de curtidor',
        'Suprimentos de caligrafia' => 'Ferramentas de calígrafo',
        'Ferramentas de pintor'     => 'Suprimentos de pintor',
        'Ferramentas de costureiro' => 'Kit de costura',
      }.each { |do_livro, em_uso| expect(resolve(do_livro)&.name).to eq(em_uso) }
    end
  end

  it 'é idempotente' do
    antes = [Proficiency.count, ProficiencyAlias.count]
    Rake::Task['dnd:seed_proficiency_tools'].reenable
    Rake::Task['dnd:seed_proficiency_tools'].invoke
    expect([Proficiency.count, ProficiencyAlias.count]).to eq(antes)
  end

  it '⚠️ o guarda PEGA o não catalogado — senão é teatro' do
    expect(resolve('Ferramentas de coisa nenhuma')).to be_nil
  end
end
