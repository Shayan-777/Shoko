# frozen_string_literal: true

require_relative '../../../state/snapshot_factory'
require_relative '../../../state/schema/reader_pagination'

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Port-contract snapshot for reader pagination state.
          # Data contract for `Application::Ports::Outbound::ReaderPaginationStore`.
          ReaderPaginationSnapshot = Shoko::Application::State::SnapshotFactory.define_snapshot(
            fields: Shoko::Application::State::Schema::ReaderPagination::FIELDS,
            defaults: Shoko::Application::State::Schema::ReaderPagination::DEFAULTS,
            partition: :reader
          )
        end
      end
    end
  end
end
