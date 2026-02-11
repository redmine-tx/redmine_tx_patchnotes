class PatchNoteMigrator
  attr_reader :stats

  def initialize(dry_run: false)
    @dry_run = dry_run
    @stats = { migrated: 0, skipped: 0, already_exists: 0, no_patch_note: 0, errors: 0 }
    @settings = Setting[:plugin_redmine_tx_patchnotes]
    @patch_note_header = @settings[:patch_note_header].to_s.presence || 'PATCH_NOTE'
    @patch_skip_header = @settings[:patch_skip_header].to_s.presence || 'NO_PATCH_NOTE'
    @internal_custom_field_id = @settings[:internal_note_custom_field].to_s.presence
  end

  def dry_run?
    @dry_run
  end

  def migrate_all
    label = dry_run? ? '[DRY RUN] ' : ''
    puts "#{label}Starting full migration of text-based patch notes to DB..."
    puts "  Header: '#{@patch_note_header}', Skip header: '#{@patch_skip_header}'"
    puts "  Internal custom field ID: #{@internal_custom_field_id || '(none)'}"

    target_ids = find_target_issue_ids
    puts "  Target issues: #{target_ids.size}"
    puts ""

    Issue.where(id: target_ids).find_each do |issue|
      migrate_issue(issue)
    end
    print_stats
  end

  def migrate_version(version_id)
    version = Version.find(version_id)
    label = dry_run? ? '[DRY RUN] ' : ''
    puts "#{label}Migrating patch notes for version: #{version.name} (ID: #{version.id})..."
    puts "  Header: '#{@patch_note_header}', Skip header: '#{@patch_skip_header}'"

    target_ids = find_target_issue_ids(scope: Issue.where(fixed_version_id: version.id))
    puts "  Target issues: #{target_ids.size}"
    puts ""

    Issue.where(id: target_ids).find_each do |issue|
      migrate_issue(issue)
    end
    print_stats
  end

  def migrate_issue(issue)
    # Skip if already has DB patch notes
    if PatchNote.for_issue(issue.id).exists?
      @stats[:already_exists] += 1
      return
    end

    is_internal = check_internal(issue)

    # Check for skip header first
    if has_skip_header?(issue)
      log_skip(issue)
      unless dry_run?
        create_skip_record(issue)
      end
      @stats[:skipped] += 1
      return
    end

    # Check description for patch note
    patch_info = nil
    source_journal = nil
    source_location = nil

    if issue.description.present?
      patch_info = find_patch_note_info(issue.description.to_s.strip)
      source_location = 'description' if patch_info
    end

    # If not in description, search journals in reverse order
    unless patch_info
      issue.journals.order(id: :desc).each do |journal|
        next unless journal.notes.present?
        notes = journal.notes.strip

        # Check for skip header in journals
        if notes.include?(@patch_skip_header)
          log_skip(issue, journal_id: journal.id)
          unless dry_run?
            create_skip_record(issue, source_journal_id: journal.id)
          end
          @stats[:skipped] += 1
          return
        end

        if notes.include?(@patch_note_header)
          patch_info = find_patch_note_info(notes)
          source_journal = journal
          source_location = "journal ##{journal.id}"
          break
        end
      end
    end

    unless patch_info
      @stats[:no_patch_note] += 1
      return
    end

    author = source_journal ? source_journal.user : issue.author

    log_migrate(issue, patch_info, source_location, author, is_internal)

    unless dry_run?
      PatchNote.create!(
        issue: issue,
        author: author,
        part: patch_info[:part],
        content: patch_info[:notes],
        is_internal: is_internal,
        is_skipped: false,
        source: 'migrated',
        source_journal_id: source_journal&.id
      )
    end
    @stats[:migrated] += 1
  rescue => e
    @stats[:errors] += 1
    puts "  ERROR issue ##{issue.id}: #{e.message}"
  end

  private

  def find_target_issue_ids(scope: nil)
    headers = [@patch_note_header, @patch_skip_header]

    # description에서 헤더가 있는 일감
    desc_query = scope || Issue
    ids_from_desc = headers.flat_map do |header|
      desc_query.where("description LIKE ?", "%#{header}%").pluck(:id)
    end

    # journal notes에서 헤더가 있는 일감
    journal_query = Journal.where(journalized_type: 'Issue')
    if scope
      journal_query = journal_query.where(journalized_id: scope.select(:id))
    end
    ids_from_journals = headers.flat_map do |header|
      journal_query.where("notes LIKE ?", "%#{header}%").pluck(:journalized_id)
    end

    # 이미 DB에 있는 일감 제외
    already_migrated = PatchNote.pluck(:issue_id)

    target_ids = (ids_from_desc + ids_from_journals).uniq - already_migrated
    target_ids
  end

  def find_patch_note_info(full_notes)
    header_index = full_notes.index(@patch_note_header)
    return nil unless header_index

    lines_from_header = full_notes[header_index..-1].split("\n")
    header_line = lines_from_header[0]

    # Extract part number and inline content from header line
    # e.g. "PATCH_NOTE#2 some content" or "PATCH_NOTE some content"
    after_keyword = header_line[@patch_note_header.length..-1].to_s
    part = 1
    if after_keyword =~ /\A#(\d+)/
      part = $1.to_i
      after_keyword = after_keyword.sub(/\A#\d+/, '')
    end
    inline_content = after_keyword.strip

    # Combine inline content with subsequent lines
    subsequent_lines = lines_from_header[1..-1].join("\n")
    notes = if inline_content.present? && subsequent_lines.present?
              "#{inline_content}\n#{subsequent_lines}"
            elsif inline_content.present?
              inline_content
            else
              subsequent_lines
            end

    { notes: notes, part: part }
  end

  def has_skip_header?(issue)
    return true if issue.description.to_s.include?(@patch_skip_header)
    issue.journals.any? { |j| j.notes.to_s.include?(@patch_skip_header) }
  end

  def check_internal(issue)
    return false unless @internal_custom_field_id
    custom_value = issue.custom_field_value(@internal_custom_field_id)
    custom_value == '1' || custom_value == true
  end

  def create_skip_record(issue, source_journal_id: nil)
    PatchNote.create!(
      issue: issue,
      author: issue.author,
      part: 0,
      content: '',
      is_internal: false,
      is_skipped: true,
      skip_reason: 'Migrated from text header',
      source: 'migrated',
      source_journal_id: source_journal_id
    )
  end

  def log_migrate(issue, patch_info, source_location, author, is_internal)
    label = dry_run? ? '[DRY RUN] ' : ''
    internal_label = is_internal ? ' [INTERNAL]' : ''
    preview = patch_info[:notes].to_s.gsub(/\s+/, ' ').strip[0..80]
    puts "  #{label}##{issue.id} (#{issue.tracker.name}) Part #{patch_info[:part]}#{internal_label} from #{source_location} by #{author.name}"
    puts "    -> #{preview}#{'...' if patch_info[:notes].to_s.length > 80}"
  end

  def log_skip(issue, journal_id: nil)
    label = dry_run? ? '[DRY RUN] ' : ''
    source = journal_id ? "journal ##{journal_id}" : 'description/journals'
    puts "  #{label}##{issue.id} (#{issue.tracker.name}) SKIP from #{source}"
  end

  def print_stats
    label = dry_run? ? '[DRY RUN] ' : ''
    puts ""
    puts "#{label}Migration complete!"
    puts "  Would migrate:  #{@stats[:migrated]}" if dry_run?
    puts "  Migrated:        #{@stats[:migrated]}" unless dry_run?
    puts "  Skipped (no PN): #{@stats[:skipped]}"
    puts "  Already in DB:   #{@stats[:already_exists]}"
    puts "  No patch note:   #{@stats[:no_patch_note]}"
    puts "  Errors:          #{@stats[:errors]}"
    puts ""
    if dry_run?
      puts "This was a dry run. No data was written."
      puts "Run without DRY_RUN=1 to actually migrate."
    end
  end
end
