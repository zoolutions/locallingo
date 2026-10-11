# frozen_string_literal: true

require "logger"

require_relative "configuration"
require_relative "prompt"
require_relative "providers/ruby_llm"
require_relative "batch_translator"

module Locallingo
  # The public, file-agnostic entry point: translates a plain `{ key => text }`
  # hash between two locales with the configured rules, glossary, language
  # guide, provider and model.
  #
  #   translator = Locallingo::Translator.new(
  #     config: Locallingo.configuration,
  #     context: RubyLLM.context { |c| c.anthropic_api_key = tenant_key } # optional
  #   )
  #   result = translator.translate({ "title" => "Hello" }, from: "en", to: "de", style: :prose)
  #   result.translations # => { "title" => "Hallo" }
  #   result.failed       # => []
  #
  # Batching, retries, batch halving and omitted-key rounds come from
  # BatchTranslator. Blank texts are not sent.
  class Translator
    Result = Data.define(:translations, :failed)

    attr_reader :config

    def initialize(config: Locallingo.configuration, context: nil, model: nil, logger: nil,
                   max_batch_chars: nil, pause: nil)
      @config = config
      @provider = Providers::RubyLLM.new(provider: config.provider, context:)
      @model = model || config.translate_model
      @logger = logger || Logger.new($stderr, level: Logger::WARN)
      @max_batch_chars = max_batch_chars || config.max_batch_chars
      @pause = pause || config.pause
    end

    # Raises MissingCredentialsError before any call when no key is available.
    def translate(texts, from:, to:, style: :ui, instructions: nil)
      @provider.ensure_credentials!

      source = stringify_keys(texts).reject { |_key, text| text.to_s.strip.empty? }
      return Result.new(translations: {}, failed: []) if source.empty?

      prompt = Prompt.translation(config:, from:, to:, style:, instructions:)
      translated, failed = batch_translator.call(source, source.keys, instructions: prompt)
      Result.new(translations: translated.slice(*source.keys).except(*failed), failed:)
    end

    private

    def stringify_keys(texts)
      texts.each_with_object({}) do |(key, text), source|
        raise Error, "Duplicate key #{key.to_s.inspect} (e.g. :#{key} and \"#{key}\")" if source.key?(key.to_s)

        source[key.to_s] = text
      end
    end

    def batch_translator
      @batch_translator ||= BatchTranslator.new(
        provider: @provider, model: @model, batch_size: config.batch_size,
        max_batch_chars: @max_batch_chars, pause: @pause,
        log: ->(message, level: :info) { @logger.public_send(level, message) }
      )
    end
  end
end
