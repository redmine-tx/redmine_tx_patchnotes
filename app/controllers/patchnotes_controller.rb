class PatchnotesController < ApplicationController
    include SortHelper
    include QueriesHelper
    include IssuesHelper
    helper :queries
    helper :sort
    helper :issues
      
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

        patch_note_header = Setting[:plugin_redmine_tx_patchnotes][:patch_note_header].to_s || 'PATCH_NOTE'
        patch_skip_header = Setting[:plugin_redmine_tx_patchnotes][:patch_skip_header].to_s || 'NO_PATCH_NOTE'

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

=begin
        # 연관 일감들 중 config_tracker_off 인 일감이 존재하는 일감도 제거
        issues.reject! { |issue|
            issue.relations.any? { |relation| 
                related_issue = relation.issue_from_id == issue.id ? 
                    Issue.find(relation.issue_to_id) : 
                    Issue.find(relation.issue_from_id)
                config_tracker_off.include?(related_issue.tracker_id)
            }
        }
=end

        @no_patch_note_issues = []

        # redmineup_tags 플러그인이 설치된 경우 NoQA 태그가 달린 이슈를 제거
        if Redmine::Plugin.installed?(:redmineup_tags) && Issue.method_defined?(:tags)
            @no_patch_note_issues = issues.select { |issue| issue.tags.map(&:name).include?(Setting[:plugin_redmine_tx_patchnotes][:patch_skip_tag]) }
            issues.reject! { |issue| @no_patch_note_issues.include?(issue) }
        end

        issues.sort_by! { |issue| [0 - issue.priority.position, issue.done_ratio] }

        # 패치노트 헤더가 포함된 마지막 노트만 수집
        notes = issues.map do |issue|
            patch_note_info = issue.description ? find_patch_note_info( issue, issue.description.strip, patch_note_header ) : nil
            unless patch_note_info then
                journal = issue.journals.reverse_each.find do |journal|
                    next unless journal.notes.present?
                    notes = journal.notes.strip
                    @no_patch_note_issues.push(issue) if notes.include?(patch_skip_header)
                    notes.include?(patch_note_header)
                end
                if journal then
                    patch_note_info = find_patch_note_info( issue, journal.notes.strip, patch_note_header )
                else
                    nil
                end
            end
            patch_note_info
        end.compact

        # 패치노트 기재 필요 없는 일감들 제거
        issues.reject! { |issue| @no_patch_note_issues.include?(issue) }

        # notes에 포함된 일감들을 issues 목록에서 제거
        noted_issue_ids = notes.map { |note| note[:issue].id }

        
        issues_patch_note_complete = issues.select{ |issue| noted_issue_ids.include?(issue.id) }
        issues_need_patch_notes = issues.select { |issue| !noted_issue_ids.include?(issue.id) && !config_complete_status.include?(issue.status_id) }
        issues_complete_without_patch_notes = issues.select { |issue| config_complete_status.include?(issue.status_id) && !noted_issue_ids.include?(issue.id) }
        
        # 내부용 패치노트 커스텀 필드 확인
        internal_custom_field_id = Setting[:plugin_redmine_tx_patchnotes][:internal_note_custom_field].to_s

        # 공개용과 내부용 패치노트 분류
        if internal_custom_field_id.present?
            public_notes = []
            internal_notes = []

            notes.each do |note|
                custom_value = note[:issue].custom_field_value(internal_custom_field_id)
                is_internal = custom_value == '1' || custom_value == true

                if is_internal
                    internal_notes << note
                else
                    public_notes << note
                end
            end

            @public_notes = public_notes
            @internal_notes = internal_notes
        else
            # 설정되지 않은 경우 모든 패치노트를 공개용으로 처리
            @public_notes = notes
            @internal_notes = []
        end

        @notes = notes
        @issues = issues
        @issues_patch_note_complete = issues_patch_note_complete
        @issues_need_patch_notes = issues_need_patch_notes
        @issues_complete_without_patch_notes = issues_complete_without_patch_notes

        tracker_order = Setting[:plugin_redmine_tx_patchnotes][:tracker_order].to_s.tr('[]" ','').split(',').map(&:to_i)

        # 공개용 패치노트를 파트별로 그룹화
        @public_notes_by_part = @public_notes.group_by { |note| note[:part] }.sort_by { |part, notes| part }
        @public_notes_by_part.each do |part, notes|
            notes.sort_by! { |note|
                tracker_id = note[:issue].tracker_id
                order_index = tracker_order.index(tracker_id)
                order_index.nil? ? 999 : order_index
            }
        end

        # 내부용 패치노트를 파트별로 그룹화
        @internal_notes_by_part = @internal_notes.group_by { |note| note[:part] }.sort_by { |part, notes| part }
        @internal_notes_by_part.each do |part, notes|
            notes.sort_by! { |note|
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



      def find_patch_note_info( issue, full_notes, patch_note_header )
        patch_note_header_index = full_notes.index(patch_note_header)
        if patch_note_header_index then
            # patch_note_header가 있는 줄부터 끝까지 추출
            lines_from_header = full_notes[patch_note_header_index..-1].split("\n")
            header = lines_from_header[0]
            notes = lines_from_header[1..-1].join("\n") # 첫 번째 줄을 제거하고 나머지 줄들을 다시 결합        

            # header에서 part 추출
            part = if header.include?('#')
                header.split('#').last.to_i
            else
                1
            end

            return { issue: issue, notes: notes, part: part }
        end

        nil
      end
      
    end
    
  
