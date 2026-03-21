# frozen_string_literal: true

require 'monitor'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-owned registry for live reader UI objects that must not live in core state.
        class ReaderUiSessionRegistry
          LIVE_FIELDS = %i[
            popup_menu
            in_book_search_popup
            annotations_overlay
            annotation_editor_overlay
            translation_popup
            dictionary_popup
            dictionary_panel
          ].freeze

          def initialize
            @monitor = Monitor.new
            @state = blank_state
          end

          def read(field)
            field_name = normalize_field(field)
            @monitor.synchronize { @state.fetch(field_name) }
          end

          def write(attributes)
            updates = normalize_attributes(attributes)
            return if updates.empty?

            @monitor.synchronize do
              @state = @state.merge(updates)
            end
          end

          def slice(fields)
            field_names = Array(fields).map { |field| normalize_field(field) }

            @monitor.synchronize do
              field_names.to_h do |field|
                [field, @state.fetch(field)]
              end
            end
          end

          def clear
            @monitor.synchronize { @state = blank_state }
          end

          private

          def blank_state
            LIVE_FIELDS.to_h { |field| [field, nil] }
          end

          def normalize_attributes(attributes)
            raise ArgumentError, 'attributes must be a Hash' unless attributes.is_a?(Hash)

            attributes.transform_keys do |field|
              normalize_field(field)
            end
          end

          def normalize_field(field)
            field_name = field.to_sym
            return field_name if LIVE_FIELDS.include?(field_name)

            raise ArgumentError, "Unsupported reader UI session field: #{field.inspect}"
          end
        end
      end
    end
  end
end
