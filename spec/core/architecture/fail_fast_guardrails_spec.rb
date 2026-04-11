# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Fail-fast guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids unreachable code after unconditional raise in rescue blocks' do
    offenders = []
    files = Dir[File.join(lib_root, '**', '*.rb')]

    files.each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(/^\s*rescue\b/)
        next unless lines[index + 1]&.match?(/^\s*raise\s*$/)

        cursor = index + 2
        while cursor < lines.length
          current = lines[cursor]
          break if current.match?(/^\s*(rescue|else|ensure|end)\b/)

          text = current.strip
          if !text.empty? && !text.start_with?('#')
            offenders << "#{path}:#{index + 1}"
            break
          end
          cursor += 1
        end
      end
    end

    expect(offenders).to eq([]),
                         "Unreachable rescue branches detected:\n#{offenders.sort.join("\n")}"
  end

  it 'keeps set_message implementation centralized in message_notifier' do
    files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', '**', '*.rb')]
    offenders = files.reject { |path| path.end_with?('support/message_notifier.rb') }
                     .select { |path| File.read(path).match?(/^\s*def\s+set_message\(/) }

    expect(offenders).to eq([]),
                         "Duplicate set_message implementations detected:\n#{offenders.sort.join("\n")}"
  end

  it 'keeps menu intent action groups exactly aligned with inbound intent symbols' do
    expected = Shoko::Core::Ports::Inbound::MenuIntentHandler::INTENT_SYMBOLS.sort
    actual = (
      Shoko::Application::UseCases::Menu::Actions::Navigation::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::Browse::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::Search::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::Dictionary::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::Download::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::Translator::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::RssReader::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::Annotations::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::Settings::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Menu::Actions::Lifecycle::SUPPORTED_INTENTS
    ).uniq.sort
    expect(actual).to eq(expected)
  end

  it 'keeps reader intent action groups exactly aligned with inbound intent symbols' do
    expected = Shoko::Core::Ports::Inbound::ReaderIntentHandler::INTENT_SYMBOLS.sort
    actual = (
      Shoko::Application::UseCases::Reader::Actions::Navigation::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Reader::Actions::Overlay::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Reader::Actions::Dictionary::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Reader::Actions::Search::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Reader::Actions::AnnotationEditor::SUPPORTED_INTENTS +
      Shoko::Application::UseCases::Reader::Actions::Lifecycle::SUPPORTED_INTENTS
    ).uniq.sort
    expect(actual).to eq(expected)
  end
end
