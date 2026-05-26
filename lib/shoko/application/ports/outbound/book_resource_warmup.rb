# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Optional boundary for precomputing presentation resources after import.
        module BookResourceWarmup
          def warm_book_data(book_data:, book_sha:, epub_path:, progress_reporter: nil)
            raise NotImplementedError, "#{self.class} must implement #warm_book_data"
          end
        end
      end
    end
  end
end
