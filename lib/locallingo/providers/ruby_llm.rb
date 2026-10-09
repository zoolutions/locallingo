# frozen_string_literal: true

require_relative "../json_extraction"

module Locallingo
  module Providers
    # Thin wrapper over the `ruby_llm` gem. Every translation and quality-review
    # call goes through here so the rest of the gem never touches a provider SDK
    # directly and stays provider-agnostic.
    #
    # A fresh chat is created per call (`assume_model_exists: true` skips
    # RubyLLM's registry lookup — the configured model id is the source of
    # truth) so independent batches don't share conversation history. The
    # response is parsed with the robust JsonExtraction extractor because not
    # every provider guarantees fenceless JSON.
    #
    # The system prompt is built once per locale and reused by every batch, so
    # it is marked as a prompt cache boundary: providers that support caching
    # (Anthropic, OpenAI-compatible) bill the repeated prefix at the cached rate.
    class RubyLLM
      # Maps a RubyLLM provider symbol to the ENV var whose presence indicates
      # credentials are available, so we can fail fast with a clear message
      # before making a network call.
      CREDENTIAL_ENV = {
        openai: "OPENAI_API_KEY",
        anthropic: "ANTHROPIC_API_KEY",
        gemini: "GEMINI_API_KEY",
        deepseek: "DEEPSEEK_API_KEY",
        openrouter: "OPENROUTER_API_KEY"
      }.freeze

      attr_reader :provider

      def initialize(provider:)
        @provider = provider.to_sym
      end

      # True when a key for the configured provider is found in any source
      # (Locallingo settings, host RubyLLM config, ENV). Unknown providers are
      # assumed configured (RubyLLM may source the key elsewhere) rather than
      # blocking.
      def credentials?
        return true unless CREDENTIAL_ENV.key?(provider)

        !resolved_api_key.nil?
      end

      # Raise a precise error when the provider has no credentials.
      def ensure_credentials!
        return if credentials?

        raise MissingCredentialsError,
              "No credentials for provider #{provider.inspect}. " \
              "Set #{CREDENTIAL_ENV[provider]} in ENV, call " \
              "Locallingo.configure { |c| c.#{provider}_api_key = ... }, or add a " \
              ".locallingo.rb setup file at the project root (loaded by the CLI)."
      end

      # Send +instructions+ (system prompt) + +payload+ (user message, JSON) to
      # the model and return the parsed JSON object as a Hash.
      def chat(model:, instructions:, payload:)
        require "ruby_llm"
        configure_credentials!

        conversation = ::RubyLLM.chat(
          model:,
          provider:,
          assume_model_exists: true
        ).with_instructions(instructions, cache_until_here: true)

        response = conversation.ask(JSON.pretty_generate(payload))
        JsonExtraction.extract_object(response.content)
      end

      private

      # RubyLLM does not read provider API keys from ENV on its own, so a
      # standalone CLI run (no Rails initializer to call RubyLLM.configure)
      # would raise "Missing configuration for <provider>". Push the resolved
      # key into RubyLLM's config: an explicit `Locallingo.configure` key wins
      # (re-resolved every chat so callables stay live), then a key the host
      # app already set, then the ENV fallback.
      def configure_credentials!
        return unless CREDENTIAL_ENV.key?(provider)

        config = ::RubyLLM.config
        setting = key_setting
        return unless config.respond_to?(setting) && config.respond_to?("#{setting}=")

        key = settings_api_key
        return if key.nil? && !presence(config.public_send(setting)).nil?

        key ||= env_api_key
        config.public_send("#{setting}=", key) unless key.nil?
      end

      # Key resolution across sources, in precedence order. Used by
      # #credentials? as a fail-fast check before any network call.
      def resolved_api_key
        settings_api_key || host_configured_api_key || env_api_key
      end

      def settings_api_key
        Locallingo.settings.api_key_for(provider)
      end

      # A key the host app set via RubyLLM.configure — only inspected when
      # ruby_llm is already loaded (we never require it just to peek).
      def host_configured_api_key
        return nil unless defined?(::RubyLLM)

        config = ::RubyLLM.config
        return nil unless config.respond_to?(key_setting)

        presence(config.public_send(key_setting))
      end

      def env_api_key
        env = CREDENTIAL_ENV[provider]
        env ? presence(ENV.fetch(env, "")) : nil
      end

      def key_setting = "#{provider}_api_key"

      def presence(value)
        key = value.to_s.strip
        key.empty? ? nil : key
      end
    end
  end
end
