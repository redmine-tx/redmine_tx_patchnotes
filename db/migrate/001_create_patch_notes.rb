class CreatePatchNotes < ActiveRecord::Migration[6.1]
  def change
    create_table :patch_notes, options: 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci' do |t|
      t.integer :issue_id, null: false
      t.integer :author_id, null: false
      t.integer :part, null: false, default: 1
      t.text :content
      t.boolean :is_internal, null: false, default: false
      t.boolean :is_skipped, null: false, default: false
      t.string :skip_reason
      t.string :source, null: false, default: 'db'
      t.integer :source_journal_id
      t.timestamps
    end
    add_index :patch_notes, :issue_id
    add_index :patch_notes, :author_id
    add_index :patch_notes, [:issue_id, :part], unique: true
    add_foreign_key :patch_notes, :issues, column: :issue_id, on_delete: :cascade
    add_foreign_key :patch_notes, :users, column: :author_id
  end
end
