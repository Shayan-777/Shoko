# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Action-value resolution and dependency helpers for dictionary settings.
          module DictionarySettingsScreenComponentActionValues
            ACTION_VALUE_HELPERS = {
              back_value: :back_value,
              lookup_value: :lookup_value,
              pair_value: :pair_value,
              storage_value: :storage_value,
              refresh_value: :refresh_value,
            }.freeze

            private

            def action_items
              Shoko::Shared::MenuDefinitions.dictionary_action_items.map do |item|
                DictionarySettingsScreenComponent::ActionItem.new(
                  key: item.key,
                  label: item.label,
                  value: action_value_for(item.value_key),
                  action: item.action
                )
              end
            end

            def action_value_for(value_key)
              helper = ACTION_VALUE_HELPERS[value_key.to_sym]
              helper ? send(helper) : ''
            end

            def back_value
              'Return'
            end

            def lookup_value
              backend_name = config_reader&.dictionary_backend.to_s.downcase
              runtime_override = runtime_config&.dictionary_backend_override.to_s.downcase
              return 'Disabled' if disabled_dictionary_backend?(backend_name, runtime_override)
              return 'Needs sqlite3' unless dictionary_availability&.sqlite3_available?
              return sqlite3_status if sqlite_dictionary_backend?(backend_name, runtime_override)

              dictionary_auto_status
            end

            def disabled_dictionary_backend?(backend_name, runtime_override)
              runtime_override == 'disabled' || backend_name == 'disabled'
            end

            def sqlite_dictionary_backend?(backend_name, runtime_override)
              runtime_override == 'sqlite' || backend_name == 'sqlite'
            end

            def dictionary_auto_status
              return sqlite3_status if dictionary_datasets_present?

              'Enabled (no datasets)'
            end

            def dictionary_datasets_present?
              dictionary_storage&.databases_present?(config_reader&.dictionary_path)
            end

            def sqlite3_status
              dictionary_availability&.sqlite3_available? ? 'Enabled' : 'Needs sqlite3'
            end

            def pair_value
              source = config_reader&.dictionary_source_lang
              target = config_reader&.dictionary_target_lang
              src = dictionary_auto_setting?(source) ? 'Auto' : source.to_s.upcase
              tgt = target.to_s.strip.empty? ? 'EN' : target.to_s.upcase
              "#{src} → #{tgt}"
            end

            def storage_value
              path = config_reader&.dictionary_path.to_s.strip
              return "Default (#{display_path(default_storage_path)})" if path.empty?

              display_path(path)
            end

            def refresh_value
              dictionary_status == :loading ? 'Loading...' : 'Fetch latest list'
            end

            def runtime_config
              return @runtime_config if defined?(@runtime_config)

              @runtime_config = @dependencies&.runtime_config
            end

            def dictionary_availability
              return @dictionary_availability if defined?(@dictionary_availability)

              @dictionary_availability = @dependencies&.dictionary_availability
            end

            def dictionary_storage
              return @dictionary_storage if defined?(@dictionary_storage)

              @dictionary_storage = @dependencies&.dictionary_storage
            end

            def default_storage_path
              dictionary_storage&.default_databases_path.to_s
            end

            def display_path(path)
              dictionary_storage&.display_path(path).to_s
            end

            def dictionary_auto_setting?(value)
              return true if value.nil?

              str = value.to_s.strip
              str.empty? || str.casecmp('auto').zero?
            end
          end
        end
      end
    end
  end
end
