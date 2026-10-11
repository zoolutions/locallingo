# frozen_string_literal: true

module Locallingo
  # Translates records that include Locallingo::Translatable (see
  # `locallingo/active_record`) into one target locale.
  #
  #   Locallingo::RecordTranslator.new(translator:)
  #     .call(Article.where(id: ids), to: "de", style: :prose)
  #   # => { translated: 3, failed: { article_id => [paths] }, skipped: [ids] }
  #
  # The due records' segments (keys prefixed by record id) go out as one
  # batched translation per source locale. Each record is then written under
  # its row lock, after re-checking that its source is unchanged and the
  # target is still due: a source edited or a target hand-written while the
  # model answered is skipped and left for the next run. A record with any
  # failed segment is not written; it stays due and its paths are reported.
  #
  # Records must be persisted and of one model (ids are the key prefix). This
  # class never loads ActiveRecord itself; records only need the concern.
  class RecordTranslator
    DEFAULT_WRITE = ->(record, attributes) { record.update_columns(attributes) }

    # +write+ is called as `write.call(record, attributes)` inside the lock,
    # e.g. to bump a lock version or run validations (`record.update!(attributes)`).
    def initialize(translator:, write: DEFAULT_WRITE)
      @translator = translator
      @write = write
    end

    def call(records, to:, style: :ui, instructions: nil, force: false, include_manual: false)
      @locale = to.to_s
      @force = force
      @include_manual = include_manual
      @result = { translated: 0, failed: {}, skipped: [] }

      due, empty = records.select { |record| due?(record) }.partition { |record| record.translation_segments.any? }
      @result[:skipped].concat(empty.map(&:id))
      due.group_by(&:translation_source_locale).each do |from, group|
        translate_group(group, from:, style:, instructions:)
      end
      @result
    end

    private

    def due?(record) = record.translation_due?(@locale, force: @force, include_manual: @include_manual)

    def translate_group(records, from:, style:, instructions:)
      digests = records.to_h { |record| [record, record.translation_source_digest] }
      owners = {}
      segments = records.each_with_object({}) do |record, all|
        record.translation_segments.each do |path, text|
          key = "#{record.id}.#{path}"
          raise Error, "Segment key #{key} is ambiguous across records (an id containing \".\"?)" if owners.key?(key)

          owners[key] = [record, path]
          all[key] = text
        end
      end

      result = @translator.translate(segments, from:, to: @locale, style:, instructions:)
      records.each do |record|
        translations = own(result.translations, owners, record).to_h
        failed = own(result.failed.to_h { |key| [key, nil] }, owners, record).map(&:first)
        @result[:failed][record.id] = failed if failed.any?
        # All or nothing per record: one state entry covers the whole locale,
        # so a partial write would read as current with values missing.
        write(record, translations, digests[record]) if failed.empty? && translations.any?
      end
    end

    # The +record+'s pairs from +pairs+, keyed by its own segment path.
    def own(pairs, owners, record)
      pairs.filter_map do |key, value|
        owner, path = owners[key]
        [path, value] if owner.equal?(record)
      end
    end

    def write(record, translations, digest)
      record.with_lock do
        next @result[:skipped] << record.id unless record.translation_source_digest == digest && due?(record)

        manual = record.translation_manual?(@locale)
        target = record.build_translation_target(translations)
        @write.call(record, record.translation_attributes(@locale, target, manual:))
        @result[:translated] += 1
      end
    end
  end
end
