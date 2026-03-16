# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Support
        # Shared validation helpers for direct intent action groups.
        module IntentActionGroup
          PRESERVE_RESULT = Object.new.freeze
          Route = Data.define(:payload_reader, :result, :callable)

          module_function

          def route(payload: :none, result: PRESERVE_RESULT, &callable)
            raise ArgumentError, 'route block is required' unless callable

            Route.new(payload_reader: payload, result: result, callable: callable)
          end

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

          def dispatch_route(intent, payload, routes, unsupported:)
            route = routes[intent]
            raise ArgumentError, "#{unsupported}: #{intent}" if route.nil?

            value = route_payload(intent, payload, route.payload_reader)
            result = if route.payload_reader == :none
                       instance_exec(&route.callable)
                     else
                       instance_exec(value, &route.callable)
                     end

            route.result.equal?(PRESERVE_RESULT) ? result : route.result
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

          def route_payload(intent, payload, payload_reader)
            case payload_reader
            when :none
              validate_payload!(intent, payload)
              nil
            when :delta
              positive_delta(payload, intent)
            when :text
              text_from(payload, intent)
            when :mode
              mode_from(payload, intent)
            when :direction
              direction_from(payload, intent)
            else
              raise ArgumentError, "unsupported route payload reader: #{payload_reader.inspect}"
            end
          end
        end
      end
    end
  end
end
