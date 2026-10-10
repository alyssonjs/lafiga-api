# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Rolar e gravar (L0.6): a rolagem sai selada, não se repete pela chave, não muda depois de gravada e se deixa
# reconferir (`dados:verificar`).
RSpec.describe Dados::Rola do
  it 'grava a rolagem selada, com a forma canônica e os dados de cada grupo' do
    r = described_class.call(expressao: 'd20+5', chave: 'teste:1', contexto: { 'rotulo' => 'percepção' })

    expect(r).to be_persisted
    expect(r).to have_attributes(fonte: 'segura', expressao: '1d20+5', contexto: { 'rotulo' => 'percepção' })
    expect(r.total).to eq(r.dados.first['rolagens'].first + 5)
    expect(r.selo).to match(/\A\h{64}\z/)
    expect(r.selo_confere?).to be(true)
  end

  it 'a mesma chave devolve a rolagem gravada, sem rolar de novo' do
    primeira = described_class.call(expressao: '4d6', chave: 'teste:2')
    expect(Dados::Fonte::Segura).not_to receive(:new)
    de_novo = described_class.call(expressao: '1d100', chave: 'teste:2')

    expect(de_novo.id).to eq(primeira.id)
    expect(de_novo.expressao).to eq('4d6')
    expect(Dados::Rolagem.where(chave: 'teste:2').count).to eq(1)
  end

  it 'na fonte hmac, a mesma chave dá os mesmos dados' do
    gravada = described_class.call(expressao: '3d6', chave: 'mundo:1:evento:9', fonte: :hmac)
    de_novo = Dados::Expressao.parse('3d6').rola(Dados::Fonte::Hmac.new('mundo:1:evento:9'))

    expect(gravada.fonte).to eq('hmac')
    expect(gravada.dados).to eq(de_novo['grupos'])
  end

  it 'só entra: depois de gravada não muda nem some' do
    r = described_class.call(expressao: 'd20', chave: 'teste:3')

    expect { r.update!(total: 99) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { r.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  describe 'a reconferência' do
    it 'confere a rolagem intacta, nas duas fontes' do
      segura = Dados::Verifica.call(described_class.call(expressao: 'd20', chave: 'v:1'))
      hmac = Dados::Verifica.call(described_class.call(expressao: '2d6+1', chave: 'v:2', fonte: :hmac))

      expect(segura.to_h).to include(ok: true, selo: true, dados: :sem_como_rolar_de_novo)
      expect(hmac.to_h).to include(ok: true, selo: true, dados: :conferem)
    end

    it 'acusa o total mexido na tabela, e os dados que não são os da chave' do
      r = described_class.call(expressao: '2d6+1', chave: 'v:3', fonte: :hmac)
      Dados::Rolagem.where(id: r.id).update_all(total: 99)
      expect(Dados::Verifica.call(r.reload).to_h).to include(ok: false, selo: false)

      outra = described_class.call(expressao: '2d6+1', chave: 'v:4', fonte: :hmac)
      falsos = outra.dados.map { |g| g.merge('rolagens' => [6, 6], 'mantidos' => [6, 6]) }
      Dados::Rolagem.where(id: outra.id).update_all(dados: falsos)
      expect(Dados::Verifica.call(outra.reload).to_h).to include(ok: false, dados: :diferem)
    end

    it 'a tarefa dados:verificar mostra o que conferiu, e sai com erro quando não confere' do
      Rake::Task.clear
      Rails.application.load_tasks
      r = described_class.call(expressao: 'd20', chave: 'v:5', fonte: :hmac)

      expect { Rake::Task['dados:verificar'].invoke(r.id) }.to output(/selo: confere\ndados: conferem/).to_stdout

      Dados::Rolagem.where(id: r.id).update_all(total: 99)
      Rake::Task['dados:verificar'].reenable
      saida = StringIO.new
      antes = [$stdout, $stderr]
      $stdout = $stderr = saida
      expect { Rake::Task['dados:verificar'].invoke(r.id) }.to raise_error(SystemExit)
      $stdout, $stderr = antes
      expect(saida.string).to include('selo: NÃO CONFERE')
    ensure
      $stdout, $stderr = antes if antes
    end
  end
end
