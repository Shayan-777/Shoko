# frozen_string_literal: true

require_relative '../../../state/snapshot_support'
require_relative '../../../state/schema/reader_process'
require_relative '../../../../core/reading/schema'

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Port-contract snapshot for the reader session boundary.
          #
          # Composes the domain reading slice (from `Core::Reading::Schema`)
          # with the application reader-process slice (from
          # `Application::State::Schema::ReaderProcess`). This is the data
          # contract for the `Application::Ports::Outbound::ReaderSessionStore`
          # port and is consumed by adapters that implement that port.
          ReaderSessionSnapshot = Shoko::Application::State::SnapshotSupport.define_snapshot(
            fields: Shoko::Core::Reading::Schema::FIELDS +
                    Shoko::Application::State::Schema::ReaderProcess::FIELDS,
            defaults: Shoko::Core::Reading::Schema::DEFAULTS
                      .merge(Shoko::Application::State::Schema::ReaderProcess::DEFAULTS),
            partition: :reader
          )
        end
      end
    end
  end
end
