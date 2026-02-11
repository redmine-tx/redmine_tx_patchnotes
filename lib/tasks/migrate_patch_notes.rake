namespace :redmine_tx_patchnotes do
  desc 'Migrate all text-based patch notes to DB records (DRY_RUN=1 for preview)'
  task migrate_all: :environment do
    require_dependency File.expand_path('../../patch_note_migrator', __FILE__)
    dry_run = ENV['DRY_RUN'] == '1'
    migrator = PatchNoteMigrator.new(dry_run: dry_run)
    migrator.migrate_all
  end

  desc 'Migrate text-based patch notes for a specific version (DRY_RUN=1 for preview)'
  task :migrate_version, [:version_id] => :environment do |_t, args|
    unless args[:version_id]
      puts "Usage: rake redmine_tx_patchnotes:migrate_version[version_id]"
      exit 1
    end
    require_dependency File.expand_path('../../patch_note_migrator', __FILE__)
    dry_run = ENV['DRY_RUN'] == '1'
    migrator = PatchNoteMigrator.new(dry_run: dry_run)
    migrator.migrate_version(args[:version_id].to_i)
  end
end
