class PatchnotesController < ApplicationController
    include SortHelper
    include QueriesHelper
    include IssuesHelper
    helper :queries
    helper :sort
    helper :issues
    helper :patchnotes
      
      layout 'base'
      before_action :require_login
      before_action :find_project
      before_action :authorize
    
      def index
        # force 파라미터가 있으면 캐시를 클리어합니다
        #Rails.cache.delete('user_status_users') if params[:force].present?

        config_tracker_on = Setting[:plugin_redmine_tx_patchnotes][:e_tracker_on].to_s.tr('[]" ','').split(',').map {|i| i.to_i}
        config_tracker_off = Setting[:plugin_redmine_tx_patchnotes][:e_tracker_off].to_s.tr('[]" ','').split(',').map {|i| i.to_i}
        config_complete_status = Setting[:plugin_redmine_tx_patchnotes][:complete].to_s.tr('[]" ','').split(',').map {|i| i.to_i}

        @versions = Version.where("effective_date IS NOT NULL").where("effective_date > ?", Date.today - 2.month).open.order(:effective_date).to_a
        if @project
            @versions = @versions.select { |v| v.project_id == @project.id }
        end
        @versions = @versions[0..9]
        
        # 오늘 이후의 가장 빠른 버전을 기본값으로 설정
        @selected_version = if params[:version_id]
            version = @versions.find { |v| v.id == params[:version_id].to_i }
            version.nil? ? Version.find(params[:version_id].to_i) : version
        else
            @versions.find { |v| v.effective_date >= Date.today } || @versions.first
        end

        issues = Issue.where(fixed_version_id: @selected_version.id)
            .where(tracker_id: config_tracker_on)
            .where.not(status_id: IssueStatus.discarded_ids)
            .to_a
        issues.reject! { |issue| config_tracker_off.include?(issue.tracker_id) }

        # 상위 부모들 중 config_tracker_off 인 일감이 존재하는 일감도 제거
        issues.reject! { |issue| 
            current = issue
            while current.parent_id.present?
                current = current.parent
                if config_tracker_off.include?(current.tracker_id)
                    true
                    break
                end
            end
        }

        @no_patch_note_issues = []

        # redmineup_tags 플러그인이 설치된 경우 NoQA 태그가 달린 이슈를 제거
        if Redmine::Plugin.installed?(:redmineup_tags) && Issue.method_defined?(:tags)
            @no_patch_note_issues = issues.select { |issue| issue.tags.map(&:name).include?(Setting[:plugin_redmine_tx_patchnotes][:patch_skip_tag]) }
            issues.reject! { |issue| @no_patch_note_issues.include?(issue) }
        end

        # 미대상 유형 허용 시: 패치노트가 작성된 미대상 트래커 일감도 포함
        if Setting[:plugin_redmine_tx_patchnotes][:allow_non_target_tracker].to_s == '1'
            extra_issue_ids = PatchNote.joins(:issue)
                .where(issues: { fixed_version_id: @selected_version.id })
                .where.not(issues: { tracker_id: config_tracker_on })
                .where.not(issues: { status_id: IssueStatus.discarded_ids })
                .where.not(issue_id: issues.map(&:id))
                .pluck(:issue_id).uniq
            if extra_issue_ids.any?
                extra_issues = Issue.where(id: extra_issue_ids).to_a
                extra_issues.reject! { |issue| config_tracker_off.include?(issue.tracker_id) }
                issues.concat(extra_issues)
            end
        end

        issues.sort_by! { |issue| [0 - issue.priority.position, issue.done_ratio] }

        # DB에서 패치노트 조회
        issue_ids = issues.map(&:id)
        db_notes_by_issue = PatchNote.where(issue_id: issue_ids).group_by(&:issue_id)

        notes = []
        issues.each do |issue|
            issue_notes = db_notes_by_issue[issue.id] || []

            if issue_notes.any?(&:is_skipped)
                @no_patch_note_issues << issue
                next
            end

            issue_notes.select { |pn| !pn.is_skipped }.each do |pn|
                notes << { issue: issue, notes: pn.content, part: pn.part, is_internal: pn.is_internal }
            end
        end

        # 패치노트 기재 필요 없는 일감들 제거
        issues.reject! { |issue| @no_patch_note_issues.include?(issue) }

        # notes에 포함된 일감들을 issues 목록에서 제거
        noted_issue_ids = notes.map { |note| note[:issue].id }.uniq

        issues_patch_note_complete = issues.select { |issue| noted_issue_ids.include?(issue.id) }
        issues_need_patch_notes = issues.select { |issue| !noted_issue_ids.include?(issue.id) && !config_complete_status.include?(issue.status_id) }
        issues_complete_without_patch_notes = issues.select { |issue| config_complete_status.include?(issue.status_id) && !noted_issue_ids.include?(issue.id) }

        # 공개용과 내부용 패치노트 분류 (DB is_internal 필드 직접 사용)
        @public_notes = notes.reject { |n| n[:is_internal] }
        @internal_notes = notes.select { |n| n[:is_internal] }

        @notes = notes
        worker_ids = notes.map { |n| n[:issue].respond_to?(:worker_id) ? n[:issue].worker_id : nil }.compact.uniq
        @worker_users_map = worker_ids.any? ? User.where(id: worker_ids).index_by(&:id) : {}
        @issues = issues
        @issues_patch_note_complete = issues_patch_note_complete
        @issues_need_patch_notes = issues_need_patch_notes
        @issues_complete_without_patch_notes = issues_complete_without_patch_notes

        tracker_order = Setting[:plugin_redmine_tx_patchnotes][:tracker_order].to_s.tr('[]" ','').split(',').map(&:to_i)

        # 공개용 패치노트를 파트별로 그룹화
        @public_notes_by_part = @public_notes.group_by { |note| note[:part] }.sort_by { |part, _| part }
        @public_notes_by_part.each do |_part, part_notes|
            part_notes.sort_by! { |note|
                tracker_id = note[:issue].tracker_id
                order_index = tracker_order.index(tracker_id)
                order_index.nil? ? 999 : order_index
            }
        end

        # 내부용 패치노트를 파트별로 그룹화
        @internal_notes_by_part = @internal_notes.group_by { |note| note[:part] }.sort_by { |part, _| part }
        @internal_notes_by_part.each do |_part, part_notes|
            part_notes.sort_by! { |note|
                tracker_id = note[:issue].tracker_id
                order_index = tracker_order.index(tracker_id)
                order_index.nil? ? 999 : order_index
            }
        end

        # 하위 호환성을 위해 기존 변수도 유지
        @notes_by_part = @public_notes_by_part


      end
    
      private
  
      def find_project
        @user = params[:user_id] ? User.find(params[:user_id]) : User.current
        @project = Project.find(params[:project_id])
      rescue ActiveRecord::RecordNotFound
        render_404
      end
    
      def authorize
        raise Unauthorized unless User.current.allowed_to?(:view_patchnotes, @project)
      end



    end

