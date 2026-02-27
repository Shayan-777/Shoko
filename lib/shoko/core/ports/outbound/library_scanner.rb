# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Outbound port for catalog scanner operations used by application use cases.
        module LibraryScanner
          def load_cached
            raise NotImplementedError, "#{self.class} must implement #load_cached"
          end

          def start_scan(force: false)
            raise NotImplementedError, "#{self.class} must implement #start_scan"
          end

          def process_results
            raise NotImplementedError, "#{self.class} must implement #process_results"
          end

          def entries
            raise NotImplementedError, "#{self.class} must implement #entries"
          end

          def update_entries(entries)
            raise NotImplementedError, "#{self.class} must implement #update_entries"
          end

          def scan_status
            raise NotImplementedError, "#{self.class} must implement #scan_status"
          end

          def scan_message
            raise NotImplementedError, "#{self.class} must implement #scan_message"
          end

          def update_scan_state(status:, message:)
            raise NotImplementedError, "#{self.class} must implement #update_scan_state"
          end

          def cleanup
            raise NotImplementedError, "#{self.class} must implement #cleanup"
          end
        end
      end
    end
  end
end
