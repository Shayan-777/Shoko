# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Commands::AnnotationEditorCommandFactory do
  class DummyState
    attr_reader :updates

    def initialize
      @updates = []
    end

    def update(changes)
      @updates << changes
    end
  end

  class DummyMenuContext
    attr_reader :state, :mode_called_with

    def initialize(mode)
      @mode = mode
      @state = DummyState.new
      @mode_called_with = nil
    end

    def switch_to_mode(mode)
      @mode_called_with = mode
      @state.update({ %i[menu mode] => mode })
    end

    private

    def current_editor_component
      @mode
    end
  end

  class DummyMenuContextNoSwitch
    attr_reader :state

    def initialize(mode)
      @mode = mode
      @state = DummyState.new
    end

    private

    def current_editor_component
      @mode
    end
  end

  class DummyEditor
    attr_reader :chars, :backspace_calls, :enter_calls, :save_calls, :move_calls

    def initialize
      @chars = []
      @backspace_calls = 0
      @enter_calls = 0
      @save_calls = 0
      @move_calls = []
    end

    def handle_character(char)
      @chars << char
    end

    def handle_backspace
      @backspace_calls += 1
    end

    def handle_enter
      @enter_calls += 1
    end

    def save_annotation
      @save_calls += 1
    end

    def handle_move_left
      @move_calls << :left
    end

    def handle_move_right
      @move_calls << :right
    end

    def handle_move_up
      @move_calls << :up
    end

    def handle_move_down
      @move_calls << :down
    end
  end

  it 'routes character input to the private editor component in menu context' do
    editor = DummyEditor.new
    ctx = DummyMenuContext.new(editor)

    cmd = described_class.insert_char
    cmd.execute(ctx, key: 'x')

    expect(editor.chars).to eq(['x'])
  end

  it 'routes cancel to menu switcher when available' do
    editor = DummyEditor.new
    ctx = DummyMenuContext.new(editor)

    cmd = described_class.cancel
    cmd.execute(ctx)

    expect(ctx.mode_called_with).to eq(:annotations)
  end

  it 'routes cancel to menu state when no switcher is available' do
    editor = DummyEditor.new
    ctx = DummyMenuContextNoSwitch.new(editor)

    cmd = described_class.cancel
    cmd.execute(ctx)

    last = ctx.state.updates.last
    expect(last[%i[menu mode]]).to eq(:annotations)
  end

  it 'switches menu mode after save in menu context' do
    editor = DummyEditor.new
    ctx = DummyMenuContext.new(editor)

    cmd = described_class.save
    cmd.execute(ctx)

    expect(editor.save_calls).to eq(1)
    expect(ctx.mode_called_with).to eq(:annotations)
  end

  it 'routes cursor movement actions to the editor' do
    editor = DummyEditor.new
    ctx = DummyMenuContext.new(editor)

    described_class.move_left.execute(ctx)
    described_class.move_right.execute(ctx)
    described_class.move_up.execute(ctx)
    described_class.move_down.execute(ctx)

    expect(editor.move_calls).to eq(%i[left right up down])
  end
end
