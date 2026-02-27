# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Focused reader for menu result/status data.
        module MenuDataReader
          def download_status
            raise NotImplementedError, "#{self.class} must implement #download_status"
          end

          def download_progress
            raise NotImplementedError, "#{self.class} must implement #download_progress"
          end

          def download_next
            raise NotImplementedError, "#{self.class} must implement #download_next"
          end

          def download_prev
            raise NotImplementedError, "#{self.class} must implement #download_prev"
          end

          def download_results
            raise NotImplementedError, "#{self.class} must implement #download_results"
          end

          def download_message
            raise NotImplementedError, "#{self.class} must implement #download_message"
          end

          def download_count
            raise NotImplementedError, "#{self.class} must implement #download_count"
          end

          def dictionary_status
            raise NotImplementedError, "#{self.class} must implement #dictionary_status"
          end

          def dictionary_progress
            raise NotImplementedError, "#{self.class} must implement #dictionary_progress"
          end

          def dictionary_results
            raise NotImplementedError, "#{self.class} must implement #dictionary_results"
          end

          def dictionary_message
            raise NotImplementedError, "#{self.class} must implement #dictionary_message"
          end
        end
      end
    end
  end
end
