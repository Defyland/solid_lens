# frozen_string_literal: true

class FakeTableConnection
  IndexDefinition = Struct.new(:name)

  attr_reader :adapter_name

  def initialize(adapter_name:, existing_tables: [], indexes: {}, quote_values: {}, select_values: {}, select_all_rows: {})
    @adapter_name = adapter_name
    @existing_tables = existing_tables
    @indexes = indexes
    @quote_values = quote_values
    @select_values = select_values
    @select_all_rows = select_all_rows
  end

  def table_exists?(table)
    @existing_tables.include?(table)
  end

  def indexes(table)
    Array(@indexes.fetch(table, [])).map { |name| IndexDefinition.new(name) }
  end

  def quote(value)
    @quote_values.fetch(value) { "'#{value}'" }
  end

  def select_value(sql)
    return @select_values.fetch(sql) if @select_values.key?(sql)

    value = @select_values.find { |matcher, _result| matcher === sql }&.last
    raise KeyError, "No value stubbed for #{sql}" if value.nil?

    value
  end

  def select_all(sql)
    rows = @select_all_rows.find { |matcher, _value| matcher === sql }&.last
    raise KeyError, "No rows stubbed for #{sql}" unless rows

    rows
  end
end
