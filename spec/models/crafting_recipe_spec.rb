# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CraftingRecipe, type: :model do
  let(:produto) { Item.create!(api_index: 'p-1', name: 'Poção de Cura', kind: 'consumable', category: 'potion') }
  let(:extrato) { Item.create!(api_index: 'm-1', name: 'Extrato Vegetal', kind: 'material', category: 'essence') }
  let(:mineral) { Item.create!(api_index: 'm-2', name: 'Fonte Mineral', kind: 'material', category: 'essence') }
  let(:acido)   { Item.create!(api_index: 'm-3', name: 'Componente Ácido', kind: 'material', category: 'essence') }
  let(:receita) do
    described_class.create!(result_item: produto, craft: 'alchemy', dc: 8, days: 2,
                            craft_cost_gp: 25, processes: ['Calor'])
  end

  describe 'validações' do
    it 'exige um ofício conhecido' do
      receita.craft = 'necromancia'
      expect(receita).not_to be_valid
    end

    it 'aceita um produto só uma vez (índice único)' do
      receita
      outra = described_class.new(result_item: produto, craft: 'alchemy')
      expect { outra.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'o alvo do ingrediente é uma UNIÃO' do
    it 'aceita item, magia e texto livre' do
      magia = Spell.create!(api_index: 's-1', name: 'Amizade Animal')
      receita.ingredients.create!(ingredient_item: extrato, quantity: 30, unit: 'ml')
      receita.ingredients.create!(spell: magia, quantity: 1, unit: 'un')
      receita.ingredients.create!(raw_text: 'Componente Extra', is_choice: true, quantity: 1, unit: 'un')

      expect(receita.ingredients.map(&:target_kind)).to contain_exactly(:item, :spell, :raw)
      expect(receita.ingredients.map(&:display_name))
        .to contain_exactly('Extrato Vegetal', 'Amizade Animal', 'Componente Extra')
    end

    it 'recusa ingrediente SEM alvo — senão a receita fica muda' do
      orfao = receita.ingredients.build(quantity: 1, unit: 'un')
      expect(orfao).not_to be_valid
      expect(orfao.errors.full_messages.join).to match(/exatamente um alvo/)
    end

    it 'recusa DOIS alvos — item e magia ao mesmo tempo' do
      magia = Spell.create!(api_index: 's-2', name: 'Voo')
      dois = receita.ingredients.build(ingredient_item: extrato, spell: magia, quantity: 1, unit: 'un')
      expect(dois).not_to be_valid
    end

    it '⚠️ o BANCO barra o órfão ONDE a constraint existe (ver comentário)' do
      # A migration cria `chk_ingredient_exactly_one_target`, mas o `schema.rb`
      # do Rails 6.0 NÃO despeja CHECK constraints (só a partir do 6.1). Logo:
      #   - dev e produção TÊM a constraint (o deploy roda `db:migrate`);
      #   - o banco de TESTE, carregado do schema.rb, NÃO tem.
      # Em vez de afirmar algo falso aqui, o teste verifica onde ela existe e
      # deixa o registro do porquê onde não existe. A garantia que vale em todo
      # lugar é a validação do model (testada acima) — por isso o import da
      # Fase 3 usa `create!`, nunca `insert_all`.
      tem_constraint = described_class.connection.exec_query(
        "SELECT 1 FROM pg_constraint WHERE conrelid = 'crafting_recipe_ingredients'::regclass " \
        "AND contype = 'c' AND conname = 'chk_ingredient_exactly_one_target'"
      ).any?

      if tem_constraint
        expect {
          described_class.connection.execute(
            "INSERT INTO crafting_recipe_ingredients (crafting_recipe_id, quantity, unit, created_at, updated_at) " \
            "VALUES (#{receita.id}, 1, 'un', now(), now())"
          )
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_ingredient_exactly_one_target/)
      else
        skip 'banco sem a CHECK constraint (schema.rb do Rails 6.0 não a despeja)'
      end
    end
  end

  describe 'alternativas ("X ou Y")' do
    before do
      receita.ingredients.create!(ingredient_item: extrato, quantity: 25, unit: 'ml', position: 0)
      receita.ingredients.create!(ingredient_item: mineral, quantity: 10, unit: 'ml',
                                  alternative_group: 1, position: 1)
      receita.ingredients.create!(ingredient_item: acido, quantity: 5, unit: 'ml',
                                  alternative_group: 1, position: 2)
    end

    it 'o grupo conta UMA vez: somar os dois cobraria material que a receita não exige' do
      expect(receita.required_ingredients.size).to eq(2)
      expect(receita.required_ingredients.map(&:display_name)).to eq(['Extrato Vegetal', 'Fonte Mineral'])
    end

    it 'expõe as opções agrupadas para o front oferecer a escolha' do
      expect(receita.alternatives.keys).to eq([1])
      expect(receita.alternatives[1].map(&:display_name)).to eq(['Fonte Mineral', 'Componente Ácido'])
    end
  end

  describe 'ciclo de vida' do
    it 'a receita morre com o produto — ela só existe para fabricá-lo' do
      receita.ingredients.create!(ingredient_item: extrato, quantity: 30, unit: 'ml')
      expect { produto.destroy! }
        .to change(described_class, :count).by(-1)
        .and change(CraftingRecipeIngredient, :count).by(-1)
    end

    it '⚠️ o MATERIAL não some por baixo da receita' do
      receita.ingredients.create!(ingredient_item: extrato, quantity: 30, unit: 'ml')
      expect(extrato.destroy).to be_falsey
      expect(extrato.errors.full_messages.join).to be_present
      expect(Item.exists?(extrato.id)).to be(true)
    end
  end
end
