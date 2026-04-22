namespace :drafts do
  desc 'Show schema audit (count by _version) for all draft characters.'
  task audit: :environment do
    histogram = Hash.new(0)
    Character.where(status: :draft).find_each do |char|
      v = (char.draft_data || {})['_version'].to_i
      histogram[v] += 1
    end
    puts '[drafts:audit] _version histogram:'
    histogram.sort.each { |v, c| puts "  v#{v} -> #{c}" }
  end
end
