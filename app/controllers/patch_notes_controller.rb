class PatchNotesController < ApplicationController
  before_action :require_login
  before_action :find_issue, only: [:new, :create, :skip, :unskip]
  before_action :find_patch_note, only: [:edit, :update, :destroy]
  before_action :authorize_edit

  def new
    unless allow_multiple_parts?
      if PatchNote.for_issue(@issue.id).active.exists?
        respond_to do |format|
          format.html { redirect_to issue_path(@issue), alert: l(:error_patch_note_single_only) }
          format.js { render js: "alert('#{j l(:error_patch_note_single_only)}');" }
        end
        return
      end
    end

    @patch_note = PatchNote.new(part: next_available_part(@issue))
    respond_to do |format|
      format.html
      format.js
    end
  end

  def create
    @patch_note = PatchNote.new(patch_note_params)
    @patch_note.issue = @issue
    @patch_note.author = User.current

    unless allow_multiple_parts?
      if PatchNote.for_issue(@issue.id).active.exists?
        @patch_note.errors.add(:base, l(:error_patch_note_single_only))
        respond_to do |format|
          format.html { render :new }
          format.js
        end
        return
      end
    end

    respond_to do |format|
      if @patch_note.save
        notes = l(:journal_patch_note_created, part: @patch_note.part) + "\n\n" + format_patch_note_content(@patch_note)
        log_journal(@issue, notes)
        format.html { redirect_to issue_path(@issue), notice: l(:notice_patch_note_created) }
        format.js
      else
        format.html { render :new }
        format.js
      end
    end
  end

  def edit
    respond_to do |format|
      format.html
      format.js
    end
  end

  def update
    old_values = { content: @patch_note.content, part: @patch_note.part, is_internal: @patch_note.is_internal }
    respond_to do |format|
      if @patch_note.update(patch_note_params)
        diff = build_update_diff(old_values, @patch_note)
        notes = l(:journal_patch_note_updated, part: @patch_note.part) + "\n\n" + diff
        log_journal(@patch_note.issue, notes)
        format.html { redirect_to issue_path(@patch_note.issue), notice: l(:notice_patch_note_updated) }
        format.js
      else
        format.html { render :edit }
        format.js
      end
    end
  end

  def destroy
    issue = @patch_note.issue
    part = @patch_note.part
    notes = l(:journal_patch_note_deleted, part: part) + "\n\n" + format_patch_note_content(@patch_note)
    @patch_note.destroy
    log_journal(issue, notes)
    respond_to do |format|
      format.html { redirect_to issue_path(issue), notice: l(:notice_patch_note_deleted) }
      format.js { @issue = issue }
    end
  end

  def skip
    # Remove existing active patch notes for this issue first
    existing_skip = PatchNote.for_issue(@issue.id).skipped.first
    if existing_skip
      existing_skip.update(skip_reason: params[:skip_reason])
    else
      PatchNote.create!(
        issue: @issue,
        author: User.current,
        part: 0,
        content: '',
        is_skipped: true,
        skip_reason: params[:skip_reason]
      )
    end
    reason = params[:skip_reason].presence
    if reason
      log_journal(@issue, l(:journal_patch_note_skipped_with_reason, reason: reason))
    else
      log_journal(@issue, l(:journal_patch_note_skipped))
    end
    respond_to do |format|
      format.html { redirect_to issue_path(@issue), notice: l(:notice_patch_note_skipped) }
      format.js
    end
  end

  def unskip
    PatchNote.for_issue(@issue.id).skipped.destroy_all
    log_journal(@issue, l(:journal_patch_note_unskipped))
    respond_to do |format|
      format.html { redirect_to issue_path(@issue), notice: l(:notice_patch_note_unskipped) }
      format.js
    end
  end

  private

  def find_issue
    @issue = Issue.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_patch_note
    @patch_note = PatchNote.find(params[:id])
    @issue = @patch_note.issue
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_edit
    unless @patch_note&.editable_by?(User.current) ||
           User.current.allowed_to?(:edit_patchnotes, @project) ||
           User.current.allowed_to?(:edit_own_patchnotes, @project)
      deny_access
    end
  end

  def patch_note_params
    params.require(:patch_note).permit(:part, :content, :is_internal)
  end

  def next_available_part(issue)
    existing_parts = PatchNote.for_issue(issue.id).active.pluck(:part)
    part = 1
    part += 1 while existing_parts.include?(part)
    part
  end

  def allow_multiple_parts?
    Setting[:plugin_redmine_tx_patchnotes][:allow_multiple_parts].to_s == '1'
  end

  def log_journal(issue, notes)
    issue.init_journal(User.current, notes)
    issue.save
  end

  def format_patch_note_content(patch_note)
    lines = []
    lines << "<pre>\n#{patch_note.content}\n</pre>"
    if patch_note.is_internal?
      lines << "(#{l(:field_patch_note_is_internal)})"
    end
    lines.join("\n")
  end

  def build_update_diff(old_values, patch_note)
    changes = []
    if old_values[:part] != patch_note.part
      changes << "#{l(:field_patch_note_part)}: #{old_values[:part]} → #{patch_note.part}"
    end
    if old_values[:is_internal] != patch_note.is_internal
      old_label = old_values[:is_internal] ? l(:general_text_Yes) : l(:general_text_No)
      new_label = patch_note.is_internal ? l(:general_text_Yes) : l(:general_text_No)
      changes << "#{l(:field_patch_note_is_internal)}: #{old_label} → #{new_label}"
    end
    if old_values[:content] != patch_note.content
      changes << "--- #{l(:label_patch_note_old_content)}\n<pre>\n#{old_values[:content]}\n</pre>"
      changes << "+++ #{l(:label_patch_note_new_content)}\n<pre>\n#{patch_note.content}\n</pre>"
    end
    changes.join("\n")
  end
end
