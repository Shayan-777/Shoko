# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Strict reader document contract used by core/application services.
        module ReaderDocument
          def canonical_path
            raise NotImplementedError, "#{self.class} must implement #canonical_path"
          end

          def cached?
            raise NotImplementedError, "#{self.class} must implement #cached?"
          end

          def chapter_count
            raise NotImplementedError, "#{self.class} must implement #chapter_count"
          end

          def get_chapter(_index)
            raise NotImplementedError, "#{self.class} must implement #get_chapter"
          end

          def toc_entries
            raise NotImplementedError, "#{self.class} must implement #toc_entries"
          end
        end
      end
    end
  end
end
