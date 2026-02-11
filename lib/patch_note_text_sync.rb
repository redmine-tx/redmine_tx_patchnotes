class PatchNoteTextSync
  def self.sync_from_text(issue, text, author:, source_journal_id: nil)
    settings = Setting[:plugin_redmine_tx_patchnotes]
    patch_header = settings[:patch_note_header].to_s.presence || 'PATCH_NOTE'
    skip_header = settings[:patch_skip_header].to_s.presence || 'NO_PATCH_NOTE'

    # 스킵 헤더 처리
    if text.include?(skip_header)
      return if PatchNote.for_issue(issue.id).skipped.exists?
      PatchNote.create!(
        issue: issue, author: author, part: 0, content: '',
        is_skipped: true, skip_reason: 'Auto-synced from text header',
        source: 'auto_sync', source_journal_id: source_journal_id
      )
      return
    end

    # 패치노트 헤더 파싱
    patch_info = find_patch_note_info(text, patch_header)
    return unless patch_info

    allow_multi = settings[:allow_multiple_parts].to_s == '1'

    # 다중 파트 비허용 시 파트를 1로 고정하고, 이미 활성 노트가 있으면 스킵
    unless allow_multi
      patch_info[:part] = 1
      return if PatchNote.for_issue(issue.id).active.exists?
    end

    # 동일 파트가 이미 있으면 스킵
    return if PatchNote.for_issue(issue.id).where(part: patch_info[:part]).exists?

    is_internal = check_internal(issue, settings)

    PatchNote.create!(
      issue: issue, author: author,
      part: patch_info[:part], content: patch_info[:notes],
      is_internal: is_internal, is_skipped: false,
      source: 'auto_sync', source_journal_id: source_journal_id
    )
  rescue => e
    Rails.logger.error "[PatchNoteTextSync] Error syncing issue ##{issue.id}: #{e.message}"
  end

  private

  def self.find_patch_note_info(text, header)
    header_index = text.index(header)
    return nil unless header_index
    lines = text[header_index..-1].split("\n")
    after_keyword = lines[0][header.length..-1].to_s
    part = 1
    if after_keyword =~ /\A#(\d+)/
      part = $1.to_i
      after_keyword = after_keyword.sub(/\A#\d+/, '')
    end
    inline = after_keyword.strip
    subsequent = lines[1..-1].join("\n")
    notes = [inline.presence, subsequent.presence].compact.join("\n")
    notes.present? ? { notes: notes, part: part } : nil
  end

  def self.check_internal(issue, settings)
    cf_id = settings[:internal_note_custom_field].to_s.presence
    return false unless cf_id
    val = issue.custom_field_value(cf_id)
    val == '1' || val == true
  end
end
