# frozen_string_literal: true

require 'rails_helper'

# Um BLOCO do mapa da vila (L1.2; plano B3 e D5): 40×40 células, o terreno nos vértices (uma camada de bits por
# terreno) e os objetos esparsos que moram nele (cada um em um bloco só, pelo pé).
RSpec.describe MapaBloco do
  let(:mapa) { create(:battle_map, :vila) } # 100×100: blocos de 40, 40 e 20

  # uma camada de bits do tamanho certo para os vértices do bloco (todos ligados ou todos desligados)
  def camada(colunas, linhas, ligada: true)
    Base64.strict_encode64((ligada ? "\xFF".b : "\x00".b) * (((colunas + 1) * (linhas + 1) + 7) / 8))
  end

  def bloco(bc: 0, bl: 0, terreno: { 'camadas' => {} }, objetos: [])
    build(:mapa_bloco, battle_map: mapa, bc: bc, bl: bl, terreno: terreno, objetos: objetos)
  end

  def arvore(col, lin, id: "arvore-#{col}-#{lin}")
    { 'id' => id, 'tipo' => 'arvore', 'especie' => 'carvalho', 'col' => col, 'lin' => lin }
  end

  def carimbo(peca, col, lin, **resto)
    { 'id' => "carimbo-#{peca}-#{col}-#{lin}", 'tipo' => 'carimbo', 'peca' => peca, 'col' => col, 'lin' => lin }
      .merge(resto.transform_keys(&:to_s))
  end

  def erro_dos_objetos(*objetos)
    b = bloco(objetos: objetos)
    b.valid?
    b.errors[:objetos].join
  end

  it 'lê o formato compartilhado com o front' do
    expect(described_class::LADO).to eq(40)
    expect(described_class::TERRENOS).to include('Grass', 'Water')
    expect(described_class::TERRENOS.index('Sand')).to be < described_class::TERRENOS.index('Water')
    expect(described_class::ESPECIES).to include('carvalho', 'pinheiro')
    expect(described_class::PECAS).to include('ponte', 'cerca', 'montanhaGrande')
  end

  it 'o bloco da borda é menor: as células que sobram do mapa' do
    expect(bloco(bc: 0, bl: 0)).to have_attributes(colunas: 40, linhas: 40)
    expect(bloco(bc: 2, bl: 0)).to have_attributes(colunas: 20, linhas: 40)
    expect(bloco(bc: 2, bl: 2)).to have_attributes(colunas: 20, linhas: 20)
  end

  it 'aceita o bloco vazio e o bloco com terreno e objetos' do
    expect(bloco).to be_valid
    cheio = bloco(
      bc: 2, bl: 2,
      terreno: { 'camadas' => { 'Grass' => camada(20, 20), 'Water' => camada(20, 20, ligada: false) } },
      objetos: [arvore(85, 99)],
    )
    expect(cheio).to be_valid
  end

  it 'recusa bloco fora do mapa' do
    expect(bloco(bc: 3, bl: 0)).not_to be_valid
    expect(bloco(bc: 0, bl: -1)).not_to be_valid
  end

  describe 'o terreno' do
    it 'recusa camada que não está no formato' do
      b = bloco(terreno: { 'camadas' => { 'Lava' => camada(40, 40) } })
      expect(b).not_to be_valid
      expect(b.errors[:terreno].join).to include('terreno desconhecido: Lava')
    end

    it 'recusa camada com o número errado de vértices' do
      b = bloco(bc: 2, bl: 2, terreno: { 'camadas' => { 'Grass' => camada(40, 40) } })
      expect(b).not_to be_valid
      expect(b.errors[:terreno].join).to include('Grass')
    end

    it 'recusa camada que não é base64' do
      expect(bloco(terreno: { 'camadas' => { 'Grass' => '%%%' } })).not_to be_valid
    end
  end

  describe 'os objetos' do
    it 'cada um mora no bloco do seu pé' do
      expect(bloco(objetos: [arvore(39, 39)])).to be_valid
      expect(bloco(objetos: [arvore(40, 0)])).not_to be_valid
    end

    it 'o carimbo mora no bloco da célula do seu pé (o canto de baixo, à esquerda da pegada)' do
      expect(bloco(objetos: [carimbo('ponte', 39, 39, colunas: 4)])).to be_valid
      expect(bloco(objetos: [carimbo('ponte', 39, 40)])).not_to be_valid
    end

    it 'recusa tipo desconhecido, id repetido e campo que falta' do
      expect(bloco(objetos: [arvore(1, 1).merge('tipo' => 'dragao')])).not_to be_valid
      expect(bloco(objetos: [arvore(1, 1, id: 'x'), arvore(2, 2, id: 'x')])).not_to be_valid
      expect(bloco(objetos: [arvore(1, 1).except('lin')])).not_to be_valid
    end

    it 'a árvore guarda a espécie; o desenho é da arte' do
      expect(erro_dos_objetos(arvore(1, 1))).to eq('')
      expect(erro_dos_objetos(arvore(1, 1).merge('especie' => 'baobá'))).to include('espécie desconhecida')
      expect(erro_dos_objetos(arvore(1, 1).except('especie'))).to include('espécie desconhecida')
      expect(erro_dos_objetos(arvore(1, 1).merge('variante' => 'redonda'))).to include('variante é da arte')
    end

    it 'o carimbo guarda a peça do catálogo, nunca a folha nem o recorte (nenhum PNG no estado do mundo)' do
      expect(erro_dos_objetos(carimbo('cerca', 3, 3, dy: -24))).to eq('')
      expect(erro_dos_objetos(carimbo('dragao', 3, 3))).to include('peça fora do catálogo')
      com_png = carimbo('ponte', 3, 3).merge('folha' => 'ponte', 'ret' => { 'x' => 96, 'y' => 0, 'w' => 96, 'h' => 77 })
      expect(erro_dos_objetos(com_png)).to include('folha, ret é da arte')
    end

    it 'o ajuste fino fica dentro da célula, e o vão da ponte dentro de um bloco' do
      expect(erro_dos_objetos(carimbo('tabuas', 3, 3, dx: -16))).to eq('')
      expect(erro_dos_objetos(carimbo('tabuas', 3, 3, dx: -32))).to include('dx')
      expect(erro_dos_objetos(carimbo('tabuas', 3, 3, dy: 1.5))).to include('dy')
      expect(erro_dos_objetos(carimbo('ponte', 3, 3, colunas: 5))).to eq('')
      expect(erro_dos_objetos(carimbo('ponte', 3, 3, colunas: 0))).to include('colunas')
      expect(erro_dos_objetos(carimbo('ponte', 3, 3, colunas: 41))).to include('colunas')
    end

    it 'recusa mais objetos que o teto' do
      muitos = Array.new(described_class::MAX_OBJETOS + 1) { |i| arvore(i % 40, (i / 40) % 40, id: "a#{i}") }
      expect(bloco(objetos: muitos)).not_to be_valid
    end
  end

  it 'a janela devolve os blocos em volta, cortados na borda do mapa, em ordem' do
    (0..2).each { |bl| (0..2).each { |bc| create(:mapa_bloco, battle_map: mapa, bc: bc, bl: bl) } }

    expect(mapa.mapa_blocos.na_janela(1, 1, 1).map { |b| [b.bc, b.bl] })
      .to eq([[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1], [0, 2], [1, 2], [2, 2]])
    expect(mapa.mapa_blocos.na_janela(0, 0, 1).count).to eq(4)
    expect(mapa.mapa_blocos.na_janela(2, 2, 0).map { |b| [b.bc, b.bl] }).to eq([[2, 2]])
  end

  it 'um bloco por lugar do mapa' do
    create(:mapa_bloco, battle_map: mapa, bc: 1, bl: 1)

    expect(bloco(bc: 1, bl: 1)).not_to be_valid
  end
end
