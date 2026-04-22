class AddCoverImageUrlToGroups < ActiveRecord::Migration[6.0]
  def change
    add_column :groups, :cover_image_url, :string
  end
end
