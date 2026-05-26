# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for dictionary database path policy and storage operations.
        module DictionaryStorage
          # @return [String]
          def default_databases_path
            raise NotImplementedError, "#{self.class} must implement #default_databases_path"
          end

          # @param configured_path [String, nil]
          # @return [String]
          def resolve_databases_path(configured_path)
            raise NotImplementedError, "#{self.class} must implement #resolve_databases_path"
          end

          # @param configured_path [String, nil]
          # @return [String]
          def ensure_databases_path(configured_path)
            raise NotImplementedError, "#{self.class} must implement #ensure_databases_path"
          end

          # @param configured_path [String, nil]
          # @return [Boolean]
          def databases_present?(configured_path)
            raise NotImplementedError, "#{self.class} must implement #databases_present?"
          end

          # @param configured_path [String, nil]
          # @return [void]
          def remove_databases_path(configured_path)
            raise NotImplementedError, "#{self.class} must implement #remove_databases_path"
          end

          # @param path [String, nil]
          # @return [String]
          def display_path(path)
            raise NotImplementedError, "#{self.class} must implement #display_path"
          end
        end
      end
    end
  end
end
