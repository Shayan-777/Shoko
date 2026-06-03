# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module StatusBar
          # What the status bar should show for the current view, independent of
          # how it is drawn. Built per-frame by a view-specific context builder
          # (reader, menu) and consumed by StatusBarComponent.
          #
          #   badge         - leading colored pill (FormatBadge::Badge) or nil
          #   title         - primary label (book / view name)
          #   details       - secondary left items, shown dimmed and separated
          #                   (e.g. ["Ch 3/12", "The Valley of Ashes"])
          #   trailing      - right-aligned textual items (e.g. ["42 / 318"])
          #   progress      - 0.0..1.0 reading progress, or nil for no bar
          #   progress_rgb  - fill color for the progress bar (e.g. the format color)
          #   placeholder   - dim hint shown in place of an empty title (e.g. search prompt)
          #   caret         - when true, a steady input caret follows the title (search input)
          StatusContext = Data.define(
            :badge, :title, :details, :trailing, :progress, :progress_rgb, :placeholder, :caret
          ) do
            def self.build(badge: nil, title: '', details: [], trailing: [], progress: nil,
                           progress_rgb: nil, placeholder: '', caret: false)
              new(
                badge: badge,
                title: title.to_s,
                details: Array(details).reject { |d| d.to_s.empty? },
                trailing: Array(trailing).reject { |t| t.to_s.empty? },
                progress: progress,
                progress_rgb: progress_rgb,
                placeholder: placeholder.to_s,
                caret: caret
              )
            end

            def empty?
              badge.nil? && title.to_s.empty? && details.empty? && trailing.empty? &&
                progress.nil? && placeholder.to_s.empty? && !caret
            end

            def progress?
              !progress.nil?
            end
          end
        end
      end
    end
  end
end
