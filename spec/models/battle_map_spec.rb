# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BattleMap, type: :model do
  describe 'validacoes' do
    it 'aceita mapa valido com cells matrix bem-formada' do
      map = build(:battle_map)
      expect(map).to be_valid
    end

    it 'rejeita name em branco' do
      map = build(:battle_map, name: '')
      expect(map).not_to be_valid
      expect(map.errors[:name]).to be_present
    end

    it 'rejeita width fora do range MIN_DIM..MAX_DIM' do
      expect(build(:battle_map, width: 4)).not_to be_valid
      expect(build(:battle_map, width: 51)).not_to be_valid
    end

    it 'rejeita matriz cells com height inconsistente' do
      map = build(:battle_map, width: 5, height: 5, cells: Array.new(3) { Array.new(5, 'empty') })
      expect(map).not_to be_valid
      expect(map.errors[:cells].join).to include('row count')
    end

    it 'rejeita row de cells com width errado' do
      cells = Array.new(5) { Array.new(5, 'empty') }
      cells[2] = Array.new(3, 'empty')
      map = build(:battle_map, width: 5, height: 5, cells: cells)
      expect(map).not_to be_valid
    end

    it 'aceita fog nullo (mapa sem fog of war)' do
      map = build(:battle_map, fog: nil)
      expect(map).to be_valid
    end

    it 'rejeita fog com dimensoes erradas' do
      map = build(:battle_map, width: 5, height: 5, fog: Array.new(3) { Array.new(5, false) })
      expect(map).not_to be_valid
    end

    it 'rejeita grid_opacity fora de [0,1]' do
      expect(build(:battle_map, grid_opacity: 1.5)).not_to be_valid
      expect(build(:battle_map, grid_opacity: -0.1)).not_to be_valid
    end

    it 'rejeita fog_mode invalido' do
      map = build(:battle_map, fog_mode: 'nope')
      expect(map).not_to be_valid
      expect(map.errors[:fog_mode]).to be_present
    end
  end

  describe '.visible_to' do
    let(:dm_role) { create(:role, name: 'DM') }
    let(:player_role) { create(:role, name: 'Player') }
    let(:dm) { create(:user, role: dm_role) }
    let(:owner) { create(:user, role: player_role) }
    let(:other) { create(:user, role: player_role) }
    let(:group) { create(:group) }

    before do
      # other entra no group via Character (membership = ter Character no grupo)
      create(:character, user: other, group: group)
    end

    it 'DM ve todos os mapas (site-wide)' do
      m1 = create(:battle_map, user: owner)
      m2 = create(:battle_map, user: other, group: group)
      expect(BattleMap.visible_to(dm)).to include(m1, m2)
    end

    it 'owner ve seus proprios mapas' do
      mine = create(:battle_map, user: owner)
      others = create(:battle_map, user: other)
      result = BattleMap.visible_to(owner)
      expect(result).to include(mine)
      expect(result).not_to include(others)
    end

    it 'membro do grupo ve mapas compartilhados via group_id' do
      shared = create(:battle_map, user: owner, group: group)
      expect(BattleMap.visible_to(other)).to include(shared)
    end

    it 'nao-membro de outro grupo nao ve os mapas dele' do
      stranger = create(:user, role: player_role)
      shared = create(:battle_map, user: owner, group: group)
      expect(BattleMap.visible_to(stranger)).not_to include(shared)
    end
  end

  describe '#writable_by?' do
    let(:dm_role) { create(:role, name: 'DM') }
    let(:player_role) { create(:role, name: 'Player') }
    let(:dm) { create(:user, role: dm_role) }
    let(:owner) { create(:user, role: player_role) }
    let(:other) { create(:user, role: player_role) }

    it 'DM pode escrever em qualquer mapa' do
      m = create(:battle_map, user: owner)
      expect(m.writable_by?(dm)).to be true
    end

    it 'owner pode escrever no proprio mapa' do
      m = create(:battle_map, user: owner)
      expect(m.writable_by?(owner)).to be true
    end

    it 'outro player nao pode escrever' do
      m = create(:battle_map, user: owner)
      expect(m.writable_by?(other)).to be false
    end

    it 'nil retorna false' do
      m = create(:battle_map, user: owner)
      expect(m.writable_by?(nil)).to be false
    end
  end
end
