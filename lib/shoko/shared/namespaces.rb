# frozen_string_literal: true

# Predeclare top-level namespaces so shorthand module definitions
# (e.g., `module Adapters::Monitoring`) remain load-order safe.
module Shoko
  module Adapters
    module BookSources; end
    module Input
      module Controllers; end
    end
    module Monitoring; end
    module Output
      module Clipboard; end
      module Formatting; end
      module Kitty; end
      module Layout; end
      module Terminal; end
    end
    module Runtime
      module SessionState; end
    end
    module Storage; end
    module Ui; end
  end

  module Bootstrap
  end

  module Application
    module Services; end
    module UseCases; end
  end

  module Core
    module BookFormats; end
    module Events; end
    module Models; end
    module Ports
      module Inbound; end
      module Outbound; end
    end
    module Services; end
  end

  module Shared; end
end
