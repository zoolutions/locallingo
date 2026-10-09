# frozen_string_literal: true

require "json"

module Locallingo
  # Sends keys to the provider in batches and collects the translations.
  #
  # - Transport/API errors retry the same payload with backoff.
  # - A reply that cannot be parsed is never resent as-is: one bad value (e.g.
  #   an unescaped quote) would fail it again. The batch is halved instead,
  #   down to single keys, so a bad value costs only its own key.
  # - Keys the model omitted are re-batched for a few rounds; keys whose own
  #   one-key reply could not be parsed are not.
  class BatchTranslator
    MAX_RETRIES = 3
    MAX_MISSING_RETRIES = 2
    BASE_SLEEP_DURATION = 1.0

    # `log` is called as `log.call(message, level: :info)`.
    def initialize(provider:, model:, batch_size:, log:)
      @provider = provider
      @model = model
      @batch_size = batch_size
      @log = log
    end

    # Translates `keys` (looked up in `source`) and returns
    # `[translations, failed_keys]`.
    def call(source, keys, instructions:)
      @source = source
      @instructions = instructions
      @unparseable = []

      translated, missing = translate_keys(keys)
      missing = retry_missing(translated, missing)

      failed = missing + @unparseable
      report_failed(failed)
      [translated, failed]
    end

    private

    def retry_missing(translated, missing)
      missing -= @unparseable
      round = 0
      while missing.any? && round < MAX_MISSING_RETRIES
        round += 1
        log("  Retry round #{round}: #{missing.size} keys remaining...")
        sleep(BASE_SLEEP_DURATION * (2**round))
        retried, missing = translate_keys(missing)
        translated.merge!(retried)
        missing -= @unparseable
      end
      missing
    end

    def report_failed(failed)
      return if failed.empty?

      log("  WARNING: #{failed.size} keys failed after all retries:", level: :warn)
      failed.each { |key| log("    - #{key}", level: :warn) }
    end

    def translate_keys(keys)
      translations = {}
      failed = []

      keys.each_slice(@batch_size) do |batch|
        result = translate_batch(batch.to_h { |key| [key, @source[key]] })
        batch.each do |key|
          if result.key?(key) && !result[key].to_s.empty?
            translations[key] = result[key]
          else
            failed << key
          end
        end
        sleep(BASE_SLEEP_DURATION)
      end

      [translations, failed]
    end

    def translate_batch(payload)
      return {} if payload.empty?

      request_batch(payload)
    rescue JSON::ParserError => e
      split_unparseable_batch(payload, e)
    end

    def split_unparseable_batch(payload, error)
      if payload.size == 1
        log("  Unparseable reply for #{payload.keys.first}: #{error.message}", level: :error)
        @unparseable.concat(payload.keys)
        return {}
      end

      log("  Unparseable reply for #{payload.size} keys, splitting the batch: #{error.message}", level: :warn)
      payload.each_slice((payload.size / 2.0).ceil).with_object({}) do |half, result|
        result.merge!(translate_batch(half.to_h))
      end
    end

    def request_batch(payload)
      retries = 0
      begin
        result = @provider.chat(model: @model, instructions: @instructions, payload:)
        log("  Batch translated: #{result.keys.size}/#{payload.keys.size} keys")
        result
      rescue JSON::ParserError
        raise
      rescue StandardError => e
        retries += 1
        if retries < MAX_RETRIES
          sleep_duration = BASE_SLEEP_DURATION * (2**retries)
          log("  Batch failed (attempt #{retries}), retrying in #{sleep_duration}s: #{e.message}", level: :warn)
          sleep(sleep_duration)
          retry
        end
        log("  Translation batch failed after #{MAX_RETRIES} retries: #{e.message}", level: :error)
        {}
      end
    end

    def log(message, level: :info) = @log.call(message, level:)
  end
end
