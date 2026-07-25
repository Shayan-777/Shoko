# frozen_string_literal: true

module Shoko
  module Shared
    # Ordering rules for a pair of buffer offsets describing a selection.
    #
    # A selection is captured in gesture order — dragging right-to-left yields
    # an end offset lower than its start — so every consumer that slices text
    # by it must first put the pair in ascending order. The renderer and the
    # mouse handler both do, and a disagreement there means one highlights a
    # range the other refuses to copy.
    module IndexRange
      module_function

      # @return [Array(Integer, Integer)] the pair, lowest first
      def ordered(selection)
        start_index = selection[:start_index].to_i
        end_index = selection[:end_index].to_i
        start_index <= end_index ? [start_index, end_index] : [end_index, start_index]
      end
    end
  end
end
