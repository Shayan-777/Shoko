# frozen_string_literal: true

require 'shoko/application/state/snapshot_factory'
require 'shoko/application/state/schema/menu_transient'

module Shoko
  module Application
    module Ports
      module Outbound
        # Immutable state snapshots exposed by outbound state ports.
        module State
          # Port-contract snapshot for the non-persisted menu workflow slice.
          # Data contract for `Application::Ports::Outbound::MenuTransientStore`.
          MenuTransientSnapshot = Shoko::Application::State::SnapshotFactory.define_snapshot(
            fields: Shoko::Application::State::Schema::MenuTransient::FIELDS,
            defaults: Shoko::Application::State::Schema::MenuTransient::DEFAULTS,
            partition: :menu
          )

          MenuTransientSnapshot.class_eval do
            def loading_active? = loading_active == true
            def dictionary_entries = Array(dictionary_results)
          end
        end
      end
    end
  end
end
