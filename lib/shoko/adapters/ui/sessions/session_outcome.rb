# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Sessions
      # Canonical result object returned by UI session mutation commands.
      SessionOutcome = Data.define(:status, :ok, :code, :message, :payload) do
        def self.success(status:, code:, payload: nil, message: nil)
          new(status: status, ok: true, code: code, message: message, payload: payload)
        end

        def self.failure(status:, code:, message:, payload: nil)
          new(status: status, ok: false, code: code, message: message, payload: payload)
        end
      end
      end
    end
  end
end
