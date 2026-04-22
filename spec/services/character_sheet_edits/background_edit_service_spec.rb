# frozen_string_literal: true

require 'rails_helper'

# Cobre o fix B3.1 do relatorio de auditoria de steps: antes da introducao de
# `resolve_background_id`, este service fazia `data['backgroundId'].to_i`
# direto, entao um slug ('soldier'/'soldado') virava 0 e o background era
# apagado silenciosamente. Pattern espelhado de RaceEditService/ClassEditService.
RSpec.describe CharacterSheetEdits::BackgroundEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  describe '#apply! resolve_background_id' do
    let!(:bg) do
      Background.find_or_create_by!(api_index: 'soldier') do |row|
        row.name = 'Soldado'
        row.feature_name = 'Patente Militar'
      end
    end

    it 'aceita id numerico cru' do
      svc = described_class.new(character: character, data: { 'backgroundId' => bg.id.to_s })
      svc.call
      sheet.reload
      expect(sheet.background_id).to eq(bg.id)
    end

    it 'aceita api_index kebab-case (slug do front)' do
      svc = described_class.new(character: character, data: { 'backgroundId' => 'soldier' })
      svc.call
      sheet.reload
      expect(sheet.background_id).to eq(bg.id)
    end

    it 'aceita api_index com underscore (snake_case)' do
      # Slug unico para nao colidir com seed/factories que ja popularam
      # 'guild_artisan'/'guild-artisan' em rodadas anteriores.
      bg_snake = Background.find_or_create_by!(api_index: 'cazador_de_monstros') do |row|
        row.name = 'Cazador de Monstros'
      end
      svc = described_class.new(character: character, data: { 'backgroundId' => 'cazador-de-monstros' })
      svc.call
      sheet.reload
      expect(sheet.background_id).to eq(bg_snake.id)
    end

    it 'limpa o vinculo quando recebe nil/blank' do
      sheet.update!(background_id: bg.id)
      svc = described_class.new(character: character, data: { 'backgroundId' => '' })
      svc.call
      sheet.reload
      expect(sheet.background_id).to be_nil
    end

    # ZE1 do segundo audit: ANTES o teste validava o BUG (slug invalido apaga
    # silenciosamente). Agora o contrato e:
    #   - raw nil/blank      -> clear explicito (ja coberto acima).
    #   - slug invalido      -> warn, NAO altera background_id.
    #   - slug valido        -> seta normal.
    it 'ZE1 — slug invalido emite warn e NAO apaga o background existente' do
      sheet.update!(background_id: bg.id)
      svc = described_class.new(character: character.reload, data: { 'backgroundId' => 'slug-que-nao-existe' })
      result = svc.call
      sheet.reload

      expect(sheet.background_id).to eq(bg.id) # preservado!
      expect(result.warnings.first).to include('slug-que-nao-existe')
      expect(result.warnings.first).to include('nao corresponde')
    end
  end

  describe 'G3.3 — invalidate ao trocar background' do
    let!(:bg_old) do
      Background.find_or_create_by!(api_index: 'soldier') do |row|
        row.name = 'Soldado'
        row.feature_name = 'Patente Militar'
      end
    end
    let!(:bg_new) do
      Background.find_or_create_by!(api_index: 'sage') do |row|
        row.name = 'Erudito'
        row.feature_name = 'Pesquisador'
      end
    end

    before do
      sheet.update!(
        background_id: bg_old.id,
        metadata: {
          'background_choices' => {
            'traits' => ['Mantenho a postura de soldado'],
            'ideals' => ['Disciplina'],
            'bonds'  => ['Meu pelotao'],
            'flaws'  => ['Obedeco ordens cegamente']
          },
          'background_proficiencies' => ['Jogo de cartas', 'Veiculo terrestre']
        }
      )
    end

    it 'limpa choices/profs do bg antigo quando troca sem reenviar (force: true)' do
      svc = described_class.new(
        character: character.reload, force: true,
        data: { 'backgroundId' => 'sage' }
      )
      result = svc.call
      sheet.reload

      expect(sheet.background_id).to eq(bg_new.id)
      expect(sheet.metadata.dig('background_choices', 'traits')).to eq([])
      expect(sheet.metadata.dig('background_choices', 'ideals')).to eq([])
      expect(sheet.metadata['background_proficiencies']).to eq([])
      # ZE8 do segundo audit: cleared_keys agora e granular (uma key por sub-campo)
      # em vez de uma key generica `metadata.background_choices`. UI mostra
      # exatamente o que vai ser perdido.
      expect(result.cleared_keys).to include('background_choices.traits')
      expect(result.cleared_keys).to include('background_choices.ideals')
      expect(result.cleared_keys).to include('background_proficiencies')
    end

    it 'requires_confirmation sem force quando troca implicaria limpeza' do
      svc = described_class.new(
        character: character.reload,
        data: { 'backgroundId' => 'sage' }
      )
      result = svc.call

      expect(result.requires_confirmation).to be_present
      expect(result.requires_confirmation[:reason]).to include('Trocar de antecedente')
      # Rollback: nada foi persistido
      expect(sheet.reload.background_id).to eq(bg_old.id)
      expect(sheet.metadata.dig('background_choices', 'traits')).to eq(['Mantenho a postura de soldado'])
    end

    it 'PRESERVA choices quando vieram no MESMO PATCH (atomico)' do
      svc = described_class.new(
        character: character.reload, force: true,
        data: {
          'backgroundId' => 'sage',
          'backgroundPersonalityTraits' => ['Sou estudioso e curioso'],
          'backgroundIdeals' => ['Conhecimento'],
          'backgroundBonds'  => ['Minha biblioteca'],
          'backgroundFlaws'  => ['Sou distraido com livros']
        }
      )
      svc.call
      sheet.reload

      expect(sheet.background_id).to eq(bg_new.id)
      expect(sheet.metadata.dig('background_choices', 'traits')).to eq(['Sou estudioso e curioso'])
      expect(sheet.metadata.dig('background_choices', 'ideals')).to eq(['Conhecimento'])
    end

    it 'NAO limpa quando o backgroundId NAO mudou (apenas atualizou choices)' do
      svc = described_class.new(
        character: character.reload,
        data: {
          'backgroundId' => bg_old.id.to_s,
          'backgroundIdeals' => ['Honra']
        }
      )
      result = svc.call
      sheet.reload

      expect(sheet.background_id).to eq(bg_old.id)
      expect(sheet.metadata.dig('background_choices', 'traits')).to eq(['Mantenho a postura de soldado']) # preservado
      expect(sheet.metadata.dig('background_choices', 'ideals')).to eq(['Honra']) # atualizado
      expect(result.cleared_keys).not_to include('metadata.background_choices')
    end
  end

  describe 'B3.2 — tools e languages persistidos separadamente' do
    let!(:bg) do
      Background.find_or_create_by!(api_index: 'soldier_b32') do |row|
        row.name = 'Soldado B32'
      end
    end

    before { sheet.update!(background_id: bg.id) }

    it 'salva tools e languages em campos distintos (bc.tools e bc.languages)' do
      svc = described_class.new(character: character.reload, data: {
        'backgroundId' => bg.id.to_s,
        'backgroundToolChoices' => ['Jogo de cartas'],
        'backgroundLanguageChoices' => ['Anão']
      })
      svc.call
      sheet.reload

      expect(sheet.metadata.dig('background_choices', 'tools')).to eq(['Jogo de cartas'])
      expect(sheet.metadata.dig('background_choices', 'languages')).to eq(['Anão'])
      # Legacy concatenado mantido para retrocompat
      expect(sheet.metadata['background_proficiencies']).to contain_exactly('Jogo de cartas', 'Anão')
    end

    it 'roundtrip: read devolve tools e languages SEM mistura' do
      described_class.new(character: character.reload, data: {
        'backgroundId' => bg.id.to_s,
        'backgroundToolChoices' => ['Jogo de cartas', 'Veiculo terrestre'],
        'backgroundLanguageChoices' => ['Anão', 'Élfico']
      }).call

      out = described_class.new(character: character.reload, data: {}).read
      expect(out['backgroundToolChoices']).to eq(['Jogo de cartas', 'Veiculo terrestre'])
      expect(out['backgroundLanguageChoices']).to eq(['Anão', 'Élfico'])
      # Anti-regressao: linguagens NAO devem aparecer em tools
      expect(out['backgroundToolChoices']).not_to include('Anão')
      expect(out['backgroundToolChoices']).not_to include('Élfico')
    end

    it 'PATCH parcial (so tools) NAO zera languages anteriores' do
      described_class.new(character: character.reload, data: {
        'backgroundId' => bg.id.to_s,
        'backgroundToolChoices' => ['Jogo'],
        'backgroundLanguageChoices' => ['Anão']
      }).call

      described_class.new(character: character.reload, data: {
        'backgroundToolChoices' => ['Veiculo']
      }).call
      sheet.reload

      expect(sheet.metadata.dig('background_choices', 'tools')).to eq(['Veiculo'])
      expect(sheet.metadata.dig('background_choices', 'languages')).to eq(['Anão']) # preservado
    end

    it 'fallback: chars antigos (so bg_summary, sem bc.tools) leem corretamente do summary' do
      # Char criado pelo CharacterProvisioningService: bg_summary populado
      # com tools/languages separados. Anti-regressao: o read NAO mistura
      # `background_proficiencies` (legacy concatenado) com tools.
      sheet.update!(metadata: {
        'background_proficiencies' => ['Jogo de cartas', 'Anão'], # legacy misturado
        'background_summary' => { 'tools' => ['Jogo de cartas'], 'languages' => ['Anão'] },
        'background_choices' => {}
      })
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['backgroundToolChoices']).to eq(['Jogo de cartas'])
      expect(out['backgroundLanguageChoices']).to eq(['Anão'])
      # Anti-regressao: idioma NAO aparece em tools mesmo com legacy presente
      expect(out['backgroundToolChoices']).not_to include('Anão')
    end
  end
end
