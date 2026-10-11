# frozen_string_literal: true

module Locallingo
  # Walks a nested Hash/Array value to its leaves, keyed by a KeyFlattener-style
  # path (`steps[1].text`, `table[0][1]`). Unlike KeyFlattener, strings inside
  # nested arrays count, and each leaf carries the Hash keys and Array indices
  # leading to it, so a value can be set back in place without parsing paths.
  module ContentLeaves
    module_function

    # `path => [parts, value]`. Two leaves with the same path (a literal "a.b"
    # key next to a → b) raise: one would be silently dropped from translation.
    def call(value, label: "content")
      collect(value, [], {}, label)
    end

    def collect(value, parts, leaves, label)
      case value
      when Hash then value.each { |key, item| collect(item, parts + [key.to_s], leaves, label) }
      when Array then value.each_with_index { |item, index| collect(item, parts + [index], leaves, label) }
      else
        path = path(parts)
        raise Error, "Ambiguous translation path #{path.inspect} in #{label}" if leaves.key?(path)

        leaves[path] = [parts, value]
      end
      leaves
    end

    def path(parts)
      parts.each_with_index.map do |part, index|
        next "[#{part}]" if part.is_a?(Integer)

        index.zero? ? part : ".#{part}"
      end.join
    end

    private_class_method :collect, :path
  end
end
