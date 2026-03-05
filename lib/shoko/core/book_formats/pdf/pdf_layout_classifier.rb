# frozen_string_literal: true

require_relative 'pdf_layout_group_builder'
require_relative 'pdf_layout_heuristics'

module Shoko
  module Core
    module BookFormats
      module Pdf
        # Classifies normalized PDF layout lines into headings/epigraph/body groups.
        class PdfLayoutClassifier
          def initialize(heuristics: PdfLayoutHeuristics.new, group_builder: PdfLayoutGroupBuilder.new)
            @heuristics = heuristics
            @group_builder = group_builder
          end

          def line_metrics(lines)
            @group_builder.line_metrics(lines)
          end

          def build_groups(lines, metrics)
            @group_builder.build_groups(lines, metrics: metrics, heuristics: @heuristics)
          end

          def attribution_signature_line?(text)
            @heuristics.attribution_signature_line?(text)
          end
        end
      end
    end
  end
end
