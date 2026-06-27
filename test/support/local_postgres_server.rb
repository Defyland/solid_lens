# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "socket"
require "tmpdir"

module SolidLens
  module TestSupport
    class LocalPostgresServer
      attr_reader :database_url

      def self.available?
        !external_database_url.nil? || %w[initdb pg_ctl createdb].all? { |command| command_available?(command) }
      end

      def self.external_database_url
        value = ENV["SOLID_LENS_TEST_DATABASE_URL"].to_s.strip
        value.empty? ? nil : value
      end

      def self.command_available?(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
          path = File.join(directory, command)
          File.file?(path) && File.executable?(path)
        end
      end

      def initialize
        @database_url = self.class.external_database_url
        return if external?

        @username = ENV.fetch("USER")
        @database_name = "solid_lens_test"
        @port = self.class.next_port
        @root = Pathname.new(Dir.mktmpdir("solid-lens-postgres-"))
        @data_dir = @root.join("data")
        @log_path = @root.join("postgres.log")
      end

      def self.next_port
        server = TCPServer.new("127.0.0.1", 0)
        server.addr[1]
      ensure
        server&.close
      end

      def start
        return self if external?

        run!("initdb", "-D", data_dir.to_s, "-U", username, "--auth=trust", "--no-instructions")
        run!("pg_ctl", "-D", data_dir.to_s, "-l", log_path.to_s, "-o", "-F -h 127.0.0.1 -p #{port}", "-w", "start")
        run!("createdb", "-h", "127.0.0.1", "-p", port.to_s, "-U", username, database_name)
        @database_url = "postgresql://#{username}@127.0.0.1:#{port}/#{database_name}"
        self
      end

      def stop
        return if external?
        return unless data_dir&.exist?

        run!("pg_ctl", "-D", data_dir.to_s, "-m", "immediate", "-w", "stop")
      ensure
        FileUtils.rm_rf(root) if root
      end

      def env
        {
          "SOLID_LENS_TEST_DATABASE_URL" => database_url,
          "SOLID_LENS_TEST_DB_POOL" => "5"
        }
      end

      private

      attr_reader :data_dir, :database_name, :log_path, :port, :root, :username

      def external?
        !database_url.to_s.empty?
      end

      def run!(*command)
        _stdout, stderr, status = Open3.capture3(*command)
        return if status.success?

        raise "#{command.first} failed: #{stderr}"
      end
    end
  end
end
