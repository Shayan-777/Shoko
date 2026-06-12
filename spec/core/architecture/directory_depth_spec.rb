# frozen_string_literal: true

require 'spec_helper'

# Constitution §IV: max directory depth 4 levels under lib/shoko/<layer>/.
# The trees that predate this rule are held in a ratchet allowlist: no NEW
# directories may go deeper, and prefixes leave the list as the deferred
# flattening (census P2) lands. The require-climb rule (§IV, ≤2 levels) is
# enforced together with that flattening — see constitution amendment
# 2026-06-10.
RSpec.describe 'Directory depth' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  MAX_DEPTH_BELOW_LAYER = 4

  # Ratchet baseline as of 2026-06-10: the composition assembler tree and the
  # reader TOC component tree, both awaiting the deferred §IV flattening.
  DEEP_PREFIX_ALLOWLIST = %w[
    composition/container_factory/controller_composition/reader_runtime_assembler/controller_builder/ui_graph_builder/
    adapters/ui/components/sidebar/toc/layout/
    adapters/ui/components/sidebar/toc/renderers/
  ].freeze

  it 'keeps new files within 4 directory levels below their layer (ratchet)' do
    offenders = Dir[File.join(lib_root, '**', '*.rb')].filter_map do |path|
      rel = path.delete_prefix("#{lib_root}/")
      next if DEEP_PREFIX_ALLOWLIST.any? { |prefix| rel.start_with?(prefix) }

      segments = rel.split('/')
      directories_below_layer = segments.length - 2 # drop the layer dir and the filename
      next unless directories_below_layer > MAX_DEPTH_BELOW_LAYER

      "#{rel} (#{directories_below_layer} levels)"
    end

    expect(offenders).to eq([]),
                         "Files nested deeper than #{MAX_DEPTH_BELOW_LAYER} levels below their layer " \
                         "(constitution §IV — move the file, don't deepen the tree):\n#{offenders.sort.join("\n")}"
  end

  it 'keeps the deep-prefix allowlist honest: every prefix still has files' do
    stale = DEEP_PREFIX_ALLOWLIST.reject { |prefix| Dir[File.join(lib_root, prefix, '**', '*.rb')].any? }

    expect(stale).to eq([]),
                     "Allowlisted deep prefixes no longer exist — remove them so the ratchet tightens:\n#{stale.join("\n")}"
  end
end
