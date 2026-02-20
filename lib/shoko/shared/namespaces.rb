# frozen_string_literal: true

# Predeclare top-level namespaces so shorthand module definitions
# (e.g., `module Adapters::Monitoring`) remain load-order safe.
module Shoko
  module Adapters
    module BookSources; end
    module Input; end
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
  end

  module Bootstrap; end

  module Application
    module Controllers; end
    module Dependencies; end
    module Ports; end
    module Services; end
    module Ui; end
    module UseCases; end
  end

  module Presentation
    module Ui; end
  end

  module Core
    module BookFormats; end
    module Events; end
    module Models; end
    module Ports; end
    module Services; end
  end

  module Shared; end
end
