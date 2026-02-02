require 'redmine'

Redmine::Plugin.register :redmine_tx_patchnotes do
  name 'Redmine Tx Patchnotes plugin'
  author 'KiHyun Kang'
  description 'This is a plugin for Redmine'
  version '0.0.1'
  url 'http://example.com/path/to/plugin'
  author_url 'http://example.com/about'

  requires_redmine_plugin :redmine_tx_advanced_issue_status, :version_or_higher => '0.0.1'
  requires_redmine_plugin :redmine_tx_advanced_tracker, :version_or_higher => '0.0.1'

  menu :project_menu, 
  :redmine_tx_patchnotes, 
  { controller: 'patchnotes', action: 'index' }, 
  caption: '패치노트', 
  param: :project_id, 
  after: :roadmap,
  permission: :view_patchnotes

  project_module :redmine_tx_patchnotes do
    permission :view_patchnotes, { patchnotes: [:index] }
  end

  settings :default => {
    'patch_note_header' => 'PATCH_NOTE',
    'patch_skip_header' => 'NO_PATCH_NOTE',
    'e_exclude_status' => [],  # 제외할 일감 상태 기본값,
    'e_skip_tags' => 'NoQA',  # 패치노트 업어도 되는 태그 기본값
    'tracker_order' => [],
    'internal_note_custom_field' => '',  # 패치노트 미공개용 커스텀 필드
  }, :partial => 'settings/redmine_tx_patchnotes'
end

# JavaScript assets 등록
#Rails.application.config.assets.paths << File.join(File.dirname(__FILE__), 'app', 'assets', 'javascripts')
#Rails.application.config.assets.precompile += %w( patchnotes.js )


