class TxPatchnotesHook < Redmine::Hook::ViewListener
  render_on :view_issues_show_description_bottom,
            partial: 'patch_notes/issue_patch_note_status'

  # 이슈 생성 시: 본문에 헤더가 있으면 동기화
  def controller_issues_new_after_save(context = {})
    issue = context[:issue]
    return unless issue
    text = issue.description.to_s
    PatchNoteTextSync.sync_from_text(issue, text, author: issue.author) if contains_header?(text)
  end

  # 이슈 수정 시: 새 코멘트 또는 본문 변경에 헤더가 있으면 동기화
  def controller_issues_edit_after_save(context = {})
    issue = context[:issue]
    journal = context[:journal]
    return unless issue

    # 코멘트가 작성된 경우 -> 코멘트 텍스트 확인
    if journal && journal.notes.present? && contains_header?(journal.notes)
      PatchNoteTextSync.sync_from_text(issue, journal.notes, author: journal.user, source_journal_id: journal.id)
      return
    end

    # 본문이 변경된 경우 -> 본문 텍스트 확인
    if journal && journal.details.any? { |d| d.prop_key == 'description' }
      PatchNoteTextSync.sync_from_text(issue, issue.description.to_s, author: issue.author) if contains_header?(issue.description.to_s)
    end
  end

  private

  def contains_header?(text)
    return false if text.blank?
    settings = Setting[:plugin_redmine_tx_patchnotes]
    return false unless settings[:auto_sync_text_to_db].to_s == '1'
    patch_header = settings[:patch_note_header].to_s.presence || 'PATCH_NOTE'
    skip_header = settings[:patch_skip_header].to_s.presence || 'NO_PATCH_NOTE'
    text.include?(patch_header) || text.include?(skip_header)
  end
end
