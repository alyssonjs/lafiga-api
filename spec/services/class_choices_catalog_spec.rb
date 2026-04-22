# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe ClassChoicesCatalog do
  before(:each) { described_class.reset! }
  after(:each)  { described_class.reset! }

  describe '.load(:metamagic) — catálogo real PoC' do
    it 'carrega o YAML de metamágicas sem erro' do
      entries = described_class.load(:metamagic)
      expect(entries).to be_an(Array)
      expect(entries.size).to eq(8)
    end

    it 'cada entry tem slug, name_pt, name_en, description, mechanical_summary' do
      entries = described_class.load(:metamagic)
      entries.each do |e|
        expect(e[:slug]).to be_present
        expect(e[:name_pt]).to be_present
        expect(e[:name_en]).to be_present
        expect(e[:description]).to be_present
        expect(e[:mechanical_summary]).to be_present
      end
    end

    it 'todas marcam classes: [sorcerer]' do
      entries = described_class.load(:metamagic)
      expect(entries.map { |e| e[:classes] }).to all(eq(['sorcerer']))
    end

    it 'slugs canônicos: mm-careful, mm-distant, mm-empowered, mm-extended, mm-heightened, mm-quickened, mm-subtle, mm-twinned' do
      slugs = described_class.slugs(:metamagic)
      expect(slugs).to match_array(%w[mm-careful mm-distant mm-empowered mm-extended mm-heightened mm-quickened mm-subtle mm-twinned])
    end
  end

  describe '.resolve(:metamagic, identifier)' do
    it 'matched por slug' do
      e = described_class.resolve(:metamagic, 'mm-careful')
      expect(e[:name_pt]).to eq('Magia Cuidadosa')
    end

    it 'matched por name_pt (do front)' do
      e = described_class.resolve(:metamagic, 'Magia Cuidadosa')
      expect(e[:slug]).to eq('mm-careful')
    end

    it 'matched por name_en (PHB EN)' do
      e = described_class.resolve(:metamagic, 'Careful Spell')
      expect(e[:slug]).to eq('mm-careful')
    end

    it 'matched por alias (nome legado do backend)' do
      e = described_class.resolve(:metamagic, 'Suturar Magia')
      expect(e[:slug]).to eq('mm-careful')
    end

    it 'retorna nil para identificador inexistente' do
      expect(described_class.resolve(:metamagic, 'Foobar Magia')).to be_nil
    end

    it 'retorna nil para nil/blank' do
      expect(described_class.resolve(:metamagic, nil)).to be_nil
      expect(described_class.resolve(:metamagic, '')).to be_nil
      expect(described_class.resolve(:metamagic, '   ')).to be_nil
    end
  end

  describe '.acceptable_identifiers(:metamagic)' do
    it 'retorna slugs + names PT + names EN + aliases (todos lookups válidos)' do
      ids = described_class.acceptable_identifiers(:metamagic)
      expect(ids).to include('mm-careful', 'Magia Cuidadosa', 'Careful Spell', 'Suturar Magia')
      # 8 entries × ~4 identifiers = 32, minus 0 dupes
      expect(ids.size).to be_between(28, 40)
    end
  end

  describe 'schema validation' do
    let(:tmp_dir) { Dir.mktmpdir }
    after(:each) { FileUtils.rm_rf(tmp_dir) }

    def with_tmp_catalog(name, content)
      stub_const('ClassChoicesCatalog::CONFIG_DIR', tmp_dir)
      File.write(File.join(tmp_dir, "#{name}.yml"), content.is_a?(String) ? content : YAML.dump(content))
    end

    it 'rejeita arquivo inexistente' do
      stub_const('ClassChoicesCatalog::CONFIG_DIR', tmp_dir)
      expect { described_class.load(:nonexistent) }.to raise_error(ClassChoicesCatalog::SchemaError, /não encontrado/)
    end

    it 'rejeita top-level que não é array' do
      with_tmp_catalog(:bad, { 'foo' => 'bar' })
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /lista no topo/)
    end

    it 'rejeita slug ausente' do
      with_tmp_catalog(:bad, [{ 'name_pt' => 'X', 'name_en' => 'X', 'description' => 'a' * 30, 'mechanical_summary' => 'x' }])
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /slug obrigatório/)
    end

    it 'rejeita slug em formato errado (não kebab-case)' do
      with_tmp_catalog(:bad, [{ 'slug' => 'BadSlug', 'name_pt' => 'X', 'name_en' => 'X', 'description' => 'a' * 30, 'mechanical_summary' => 'x' }])
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /kebab-case/)
    end

    it 'rejeita slug duplicado' do
      with_tmp_catalog(:bad, [
        { 'slug' => 'a', 'name_pt' => 'A', 'name_en' => 'A', 'description' => 'a' * 30, 'mechanical_summary' => 'x' },
        { 'slug' => 'a', 'name_pt' => 'B', 'name_en' => 'B', 'description' => 'b' * 30, 'mechanical_summary' => 'y' }
      ])
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /slug duplicado/)
    end

    it 'rejeita description curta' do
      with_tmp_catalog(:bad, [{ 'slug' => 'x', 'name_pt' => 'X', 'name_en' => 'X', 'description' => 'short', 'mechanical_summary' => 'x' }])
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /description muito curta/)
    end

    it 'rejeita mechanical_summary longo' do
      with_tmp_catalog(:bad, [{ 'slug' => 'x', 'name_pt' => 'X', 'name_en' => 'X', 'description' => 'a' * 30, 'mechanical_summary' => 'x' * 101 }])
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /mechanical_summary muito longo/)
    end

    it 'rejeita prereqs com chave desconhecida' do
      with_tmp_catalog(:bad, [{ 'slug' => 'x', 'name_pt' => 'X', 'name_en' => 'X', 'description' => 'a' * 30, 'mechanical_summary' => 'x', 'prereqs' => { 'unknown_key' => 1 } }])
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /prereqs.*inválida/)
    end

    it 'rejeita alias duplicado entre entries' do
      with_tmp_catalog(:bad, [
        { 'slug' => 'a', 'name_pt' => 'A', 'name_en' => 'A', 'description' => 'a' * 30, 'mechanical_summary' => 'x', 'aliases' => ['shared'] },
        { 'slug' => 'b', 'name_pt' => 'B', 'name_en' => 'B', 'description' => 'b' * 30, 'mechanical_summary' => 'y', 'aliases' => ['shared'] }
      ])
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /alias duplicado/)
    end

    it 'aceita cost integer' do
      with_tmp_catalog(:good, [{ 'slug' => 'x', 'name_pt' => 'X', 'name_en' => 'X', 'description' => 'a' * 30, 'mechanical_summary' => 'x', 'cost' => 3 }])
      expect { described_class.load(:good) }.not_to raise_error
    end

    it 'aceita cost spell_level' do
      with_tmp_catalog(:good, [{ 'slug' => 'x', 'name_pt' => 'X', 'name_en' => 'X', 'description' => 'a' * 30, 'mechanical_summary' => 'x', 'cost' => 'spell_level' }])
      expect { described_class.load(:good) }.not_to raise_error
    end

    it 'rejeita cost inválido (string desconhecida)' do
      with_tmp_catalog(:bad, [{ 'slug' => 'x', 'name_pt' => 'X', 'name_en' => 'X', 'description' => 'a' * 30, 'mechanical_summary' => 'x', 'cost' => 'invalid' }])
      expect { described_class.load(:bad) }.to raise_error(ClassChoicesCatalog::SchemaError, /cost inválido/)
    end
  end

  describe 'cache behavior' do
    it 'cacheia o catálogo entre calls' do
      first = described_class.load(:metamagic)
      second = described_class.load(:metamagic)
      expect(first.object_id).to eq(second.object_id)
    end

    it 'reset! invalida o cache' do
      first = described_class.load(:metamagic)
      described_class.reset!
      second = described_class.load(:metamagic)
      expect(first.object_id).not_to eq(second.object_id)
    end
  end
end
