class FeaturesAggregator
  def initialize(sheet, sync: true)
    @sheet = sheet
    @sync = sync
  end

  def call
    sync_characters_features! if @sync
    char = @sheet.character
    show_map = CharactersFeature.where(character_id: char.id).pluck(:feature_id, :id, :show).each_with_object({}) do |(fid, id, show), h|
      h[fid] = { id: id, show: (show != false) }
    end
    items = []
    @sheet.sheet_klasses.each do |sk|
      klass = sk.klass
      next unless klass
      ClassLevel.includes(:features).where(klass_id: klass.id).where('level <= ?', sk.level.to_i).each do |cl|
        cl.features.each do |f|
          items << { id: f.id, level: cl.level, name: f.name, desc: f.description, source: 'Klass', show: (show_map[f.id]&.dig(:show) != false), pref_id: show_map[f.id]&.dig(:id) }
        end
      end
      if sk.sub_klass
        SubKlassLevel.includes(:features).where(sub_klass_id: sk.sub_klass_id).where('level <= ?', sk.level.to_i).each do |sl|
          sl.features.each do |f|
            items << { id: f.id, level: sl.level, name: f.name, desc: f.description, source: 'SubKlass', show: (show_map[f.id]&.dig(:show) != false), pref_id: show_map[f.id]&.dig(:id) }
          end
        end
      end
    end
    items.sort_by { |x| [x[:level].to_i, x[:name].to_s] }
  end

  private

  def sync_characters_features!
    @sheet.sheet_klasses.includes(:klass).each do |sk|
      FeatureGrantService.call(sheet: @sheet, klass: sk.klass, from_level: 0, to_level: sk.level)
    end
  end
end
