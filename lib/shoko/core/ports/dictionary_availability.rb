# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for checking dictionary backend availability.
      # Adapters implementing this interface should detect whether the
      # required dictionary infrastructure (e.g. SQLite) is available.
      module DictionaryAvailability
        # Check if the SQLite3 library is available
        #
        # @return [Boolean]
        def sqlite3_available?
          raise NotImplementedError, "#{self.class} must implement #sqlite3_available?"
        end

        # Check if dictionary database files are present at the given path
        #
        # @param path [String] Directory path to check for databases
        # @return [Boolean]
        def databases_present?(path)
          raise NotImplementedError, "#{self.class} must implement #databases_present?"
        end

        # Get the default path where dictionary databases are stored
        #
        # @return [String] Default databases directory path
        def default_databases_path
          raise NotImplementedError, "#{self.class} must implement #default_databases_path"
        end

        # Check if dictionary is enabled via environment variable override
        #
        # @return [Boolean]
        def env_override_enabled?
          raise NotImplementedError, "#{self.class} must implement #env_override_enabled?"
        end
      end
    end
  end
end
