module RedmineTxPatchnotes
  module Patches
    module IssuesHelperPatch
      def self.included(base)
        base.send(:include, InstanceMethods)
        base.send(:alias_method, :show_detail_without_tx_patchnotes, :show_detail)
        base.send(:alias_method, :show_detail, :show_detail_with_tx_patchnotes)
      end

      module InstanceMethods
        PATCHNOTE_PROP_KEYS = %w[patch_note patch_note_part patch_note_internal patch_note_content patch_note_skip].freeze

        def show_detail_with_tx_patchnotes(detail, no_html = false, options = {})
          if detail.property == 'attr' && PATCHNOTE_PROP_KEYS.include?(detail.prop_key)
            return tx_patchnotes_render_detail(detail, no_html, options)
          end

          show_detail_without_tx_patchnotes(detail, no_html, options)
        end

        private

        def tx_patchnotes_render_detail(detail, no_html, options)
          case detail.prop_key
          when 'patch_note'
            label = l(:label_journal_patch_note)
            value = detail.value.present? ? "Part ##{detail.value}" : nil
            old_value = detail.old_value.present? ? "Part ##{detail.old_value}" : nil
          when 'patch_note_part'
            label = l(:label_journal_patch_note_part)
            value = detail.value
            old_value = detail.old_value
          when 'patch_note_internal'
            label = l(:label_journal_patch_note_internal)
            value = detail.value
            old_value = detail.old_value
          when 'patch_note_content'
            label = l(:label_journal_patch_note_content)
            return tx_patchnotes_render_diff(detail, label, no_html, options)
          when 'patch_note_skip'
            label = l(:label_journal_patch_note_skip)
            value = detail.value
            old_value = detail.old_value
          end

          tx_patchnotes_render_change(detail, label, value, old_value, no_html, options)
        end

        def tx_patchnotes_render_diff(detail, label, no_html, options)
          unless no_html
            label = content_tag('strong', label)
          end
          s = l(:text_journal_changed_no_detail, label: label)
          unless no_html
            diff_link = link_to(
              l(:label_diff),
              diff_journal_url(detail.journal_id, detail_id: detail.id, only_path: options[:only_path]),
              title: l(:label_view_diff)
            )
            s << " (#{diff_link})"
          end
          s.html_safe
        end

        def tx_patchnotes_render_change(detail, label, value, old_value, no_html, options)
          unless no_html
            label = content_tag('strong', label)
            old_value = content_tag('i', h(old_value)) if detail.old_value.present?
            old_value = content_tag('del', old_value) if detail.old_value.present? && detail.value.blank?
            value = content_tag('i', h(value)) if value.present?
          end

          if detail.value.present?
            if detail.old_value.present?
              l(:text_journal_changed, label: label, old: old_value, new: value).html_safe
            else
              l(:text_journal_set_to, label: label, value: value).html_safe
            end
          elsif detail.old_value.present?
            l(:text_journal_deleted, label: label, old: old_value).html_safe
          else
            l(:text_journal_changed_no_detail, label: label).html_safe
          end
        end
      end
    end
  end
end

unless IssuesHelper.included_modules.include?(RedmineTxPatchnotes::Patches::IssuesHelperPatch)
  IssuesHelper.send(:include, RedmineTxPatchnotes::Patches::IssuesHelperPatch)
end
