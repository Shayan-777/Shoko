# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          module AnnotationMarkup
            # Shared style and width helpers for annotation markup collaborators.
            module StylePrimitives
              private

              def remove_style(active, style)
                idx = active.rindex(style)
                active.delete_at(idx) if idx
              end

              def normalize_cluster(cluster)
                cluster == "\r" ? ' ' : cluster
              end

              def display_width_for(cluster)
                Shoko::Shared::Terminal::TextMetrics.display_width_for(cluster)
              end

              def tab_spaces(col)
                size = Shoko::Shared::Terminal::TextMetrics::TAB_SIZE
                size - (col % size)
              end

              def refresh_sequence(active)
                sequence = AnnotationMarkup::STYLE_RESET.dup
                active_styles(active).each { |style| sequence << AnnotationMarkup::STYLE_ON.fetch(style) }
                sequence
              end

              def active_styles(active)
                AnnotationMarkup::STYLE_ORDER.select { |style| active.include?(style) }
              end
            end
          end
        end
      end
    end
  end
end
