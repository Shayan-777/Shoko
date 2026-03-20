# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Typed dictionary catalog row used by menu dictionary workflow.
      DictionaryCatalogEntry = Data.define(:name, :path, :installed, :payload) do
        class << self
          def from_h(hash)
            unless hash.is_a?(Hash)
              raise ArgumentError, "DictionaryCatalogEntry payload must be a Hash, got #{hash.class}"
            end

            normalized = hash.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end

            name = normalized[:name].to_s.strip
            raise ArgumentError, 'DictionaryCatalogEntry name cannot be blank' if name.empty?

            entry_path = normalized[:path]
            new(
              name: name,
              path: entry_path&.to_s,
              installed: normalized[:installed] == true,
              payload: normalized.freeze
            )
          end
        end

        def with_installation(installed:, path:)
          self.class.from_h(payload.merge(installed: installed == true, path: path))
        end

        def to_h
          payload.merge(name: name, path: path, installed: installed == true)
        end

        def to_download_h
          download_payload = {}
          payload.each do |key, value|
            next unless %i[name url source target].include?(key)

            download_payload[key] = value
          end
          download_payload[:name] = name
          download_payload
        end
      end
    end
  end
end
