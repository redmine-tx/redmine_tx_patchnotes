class PatchNote < ActiveRecord::Base
  belongs_to :issue
  belongs_to :author, class_name: 'User'

  validates :part, presence: true,
            uniqueness: { scope: :issue_id, message: 'already exists for this issue' }
  validates :content, presence: true, unless: :is_skipped?
  validates :part, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_issue, ->(issue_id) { where(issue_id: issue_id) }
  scope :active, -> { where(is_skipped: false) }
  scope :skipped, -> { where(is_skipped: true) }
  scope :public_notes, -> { where(is_internal: false, is_skipped: false) }
  scope :internal_notes, -> { where(is_internal: true, is_skipped: false) }

  def editable_by?(user)
    return true if user.admin?
    return true if user.allowed_to?(:edit_patchnotes, issue.project)
    user.allowed_to?(:edit_own_patchnotes, issue.project) && author_id == user.id
  end
end
