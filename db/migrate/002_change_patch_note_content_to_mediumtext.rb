class ChangePatchNoteContentToMediumtext < ActiveRecord::Migration[6.1]
  def up
    change_column :patch_notes, :content, :text, limit: 16.megabytes - 1
  end

  def down
    change_column :patch_notes, :content, :text
  end
end
