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

          def handled_routes(*intents, payload: :none, &callable)
            route_map_for(intents, payload: payload, result: :handled, &callable)
          end

          def route_map_for(intents, payload: :none, result: PRESERVE_RESULT, &callable)
            Array(intents).flatten.to_h do |intent|
              [intent, route(payload: payload, result: result, &callable)]
            end
          end

          def nil_payloads(*intents)
            payload_map_for(intents, NilClass)
          end

          def delta_payloads(*intents)
            payload_map_for(intents, Shoko::Application::UseCases::Requests::SelectionDelta)
          end

          def text_payloads(*intents)
            payload_map_for(intents, Shoko::Application::UseCases::Requests::TextInput)
          end

          def mode_payloads(*intents, allow_nil: false)
            allowed = [Shoko::Application::UseCases::Requests::ModeChange]
            allowed << NilClass if allow_nil
            payload_map_for(intents, allowed)
          end

          def direction_payloads(*intents)
            payload_map_for(intents, Shoko::Application::UseCases::Requests::CursorMove)
          end

          def edit_op_payloads(*intents)
            payload_map_for(intents, Shoko::Application::UseCases::Requests::EditOp)
          end

          def payload_map_for(intents, allowed_types)
            types = Array(allowed_types).freeze
            Array(intents).flatten.to_h { |intent| [intent, types] }
          end

          def validate_payload!(intent, payload)
            allowed_classes = supported_payloads.fetch(intent, [NilClass])
            return if valid_payload?(payload, allowed_classes)

            expected = allowed_classes.map do |klass|
              klass == NilClass ? 'nil' : klass.name.split('::').last
            end.join(' or ')
            actual = payload.nil? ? 'nil' : payload.class.name
            raise ArgumentError, "invalid payload for #{intent}: expected #{expected}, got #{actual}"
          end

          def valid_payload?(payload, allowed_classes)
            return true if payload.nil? && allowed_classes.include?(NilClass)

            allowed_classes.any? { |klass| klass != NilClass && payload.is_a?(klass) }
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
            payload&.delta
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

          def edit_op_from(payload, intent)
            validate_payload!(intent, payload)
            payload
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
            when :edit_op
              edit_op_from(payload, intent)
            else
              raise ArgumentError, "unsupported route payload reader: #{payload_reader.inspect}"
            end
          end
        end
      end
    end
  end
end
