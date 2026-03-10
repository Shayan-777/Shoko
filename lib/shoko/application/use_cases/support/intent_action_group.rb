# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Support
        # Shared validation helpers for direct intent action groups.
        module IntentActionGroup
          private

          def validate_payload!(intent, payload)
            allowed_classes = supported_payloads.fetch(intent, [NilClass])
            return if payload.nil? && allowed_classes.include?(NilClass)
            return if allowed_classes.any? { |klass| klass != NilClass && payload.is_a?(klass) }

            expected = allowed_classes.map { |klass| klass == NilClass ? 'nil' : klass.name.split('::').last }.join(' or ')
            actual = payload.nil? ? 'nil' : payload.class.name
            raise ArgumentError, "invalid payload for #{intent}: expected #{expected}, got #{actual}"
          end

          def supported_payloads
            {}
          end

          def positive_delta(payload, intent)
            validate_payload!(intent, payload)
            payload ? payload.delta : nil
          end

          def text_from(payload, intent)
            validate_payload!(intent, payload)
            payload&.text
          end

          def mode_from(payload, intent)
            validate_payload!(intent, payload)
            payload&.mode
          end

          def direction_from(payload, intent)
            validate_payload!(intent, payload)
            payload&.direction
          end
        end
      end
    end
  end
end
