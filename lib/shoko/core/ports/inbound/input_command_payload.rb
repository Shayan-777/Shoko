# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        # Typed command payload passed through adapter -> inbound command dispatch.
        InputCommandPayload = Data.define(:key, :triggered_by, :args, :metadata, :key_provided) do
          class << self
            def from(value = nil)
              return default if value.nil?
              return value if value.is_a?(self)
              return from_hash(value) if value.is_a?(Hash)

              raise ArgumentError, "Unsupported command payload type: #{value.class}"
            end

            def default
              new(key: nil, triggered_by: nil, args: [].freeze, metadata: {}.freeze, key_provided: false)
            end

            private

            def from_hash(hash)
              metadata = hash[:metadata].is_a?(Hash) ? hash[:metadata].dup : {}
              hash.each do |key, value|
                next if %i[key triggered_by args metadata key_provided].include?(key)

                metadata[key] = value
              end

              new(
                key: hash[:key],
                triggered_by: hash[:triggered_by],
                args: Array(hash[:args]).freeze,
                metadata: metadata.freeze,
                key_provided: hash.key?(:key) ? hash[:key_provided] != false : false
              )
            end
          end

          def to_h
            {
              key: key,
              triggered_by: triggered_by,
              args: args,
              metadata: metadata,
              key_provided: key_provided,
            }
          end
        end
      end
    end
  end
end
