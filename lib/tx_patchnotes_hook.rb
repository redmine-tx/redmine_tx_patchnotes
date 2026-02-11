class TxPatchnotesHook < Redmine::Hook::ViewListener
  render_on :view_issues_show_description_bottom,
            partial: 'patch_notes/issue_patch_note_status'
end
