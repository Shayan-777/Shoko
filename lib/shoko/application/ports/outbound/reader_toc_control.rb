# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Outbound control port for the Table-of-Contents reader mode. Implemented by
        # the reader adapter; the TOC use case drives the panel lifecycle, the live
        # filter, selection movement, and chapter activation through it.
        module ReaderTocControl
          def open_toc_lookup
            raise NotImplementedError, "#{self.class} must implement #open_toc_lookup"
          end

          def close_toc_lookup
            raise NotImplementedError, "#{self.class} must implement #close_toc_lookup"
          end

          def edit_toc_filter(_edit_op)
            raise NotImplementedError, "#{self.class} must implement #edit_toc_filter"
          end

          def move_toc_selection(_delta)
            raise NotImplementedError, "#{self.class} must implement #move_toc_selection"
          end

          def activate_toc_selection
            raise NotImplementedError, "#{self.class} must implement #activate_toc_selection"
          end
        end
      end
    end
  end
end
