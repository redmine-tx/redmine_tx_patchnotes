module PatchnotesHelper
  TRACKER_COLORS = {
    '버그'    => '#e74c3c',
    '핫픽스'  => '#c0392b',
    '구현'    => '#3498db',
    '구현(단건)' => '#2980b9',
    '개선'    => '#27ae60',
    '설정'    => '#8e44ad',
    '번역'    => '#16a085',
    '아트리소스' => '#e67e22',
    '사운드'  => '#d35400',
    'QA'      => '#2c3e50',
    'FunQA'   => '#34495e',
  }.freeze

  TRACKER_COLOR_DEFAULT = '#7f8c8d'

  def render_issues_list(issues, project)
    query = IssueQuery.new(name: 'Patch Notes Issues')
    query.project = project
    query.column_names = [:id, :tracker, :status, :priority, :subject, :assigned_to, :done_ratio, :due_date]
    query.sort_criteria = params[:sort] if params[:sort].present?
    render partial: 'issues/list', locals: { query: query, issues: issues, context_menu: true }
  end

  def resolve_worker_name(issue, worker_users_map = {})
    if issue.respond_to?(:worker_id) && issue.worker_id.present?
      user = worker_users_map[issue.worker_id]
      return user.name.gsub(/ /, '') if user
    end
    issue.assigned_to.present? ? issue.assigned_to.name.gsub(/ /, '') : ''
  end

  def tracker_color(tracker_name)
    TRACKER_COLORS[tracker_name] || TRACKER_COLOR_DEFAULT
  end

  def tab_count_class(count, type)
    return 'pn-tab-count pn-tab-count--zero' if count == 0
    css = 'pn-tab-count pn-tab-count--'
    css + case type
          when :notes    then 'notes'
          when :complete then 'complete'
          when :exception then 'exception'
          when :missing  then 'missing'
          when :warning  then 'warning'
          else 'notes'
          end
  end
end
