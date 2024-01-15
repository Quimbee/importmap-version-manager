require "yaml"

module ImportmapPackageManager
  class Manager
    HTTPError = Class.new(StandardError)

    class << self
      def update!(config: nil, lockfile: nil)
        unless config
          config_file = Rails.root.join("config/importmap_packages.yml")
          config = YAML.load_file(config_file)
        end

        import_map = build_import_map(config)
        update_lockfile!(import_map, lockfile)
      end

      private

      def build_import_map(config)
        imports = config["imports"]

        if imports == nil
          raise "No imports defined. Add import definitions to `config/importmap_packages.yml`"
        end

        import_definitions =
          imports.map do |import, import_config|
            if import_config.is_a?(String) || import_config.is_a?(Array)
              import_config = { "version" => import_config }
            end

            package = import_config["package"] || import
            version_requirement = Gem::Requirement.new(import_config["version"])

            exact_version = resolve_package_version(package, version_requirement)

            target = "#{package}@#{exact_version}"

            import_definition = { target: target }

            if import_config["subpath"]
              import_definition[:subpath] = import_config["subpath"]
            end
            import_definition
          end
        resolve_import_urls(import_definitions)
      end

      def resolve_package_version(package, version_requirement)
        # Step 1: Query NPM registry for all versions
        response = Net::HTTP.get(URI("https://registry.npmjs.org/#{package}"))
        versions = JSON.parse(response)["versions"].keys.map { |version_string| Gem::Version.new(version_string) }

        # Step 2: Find latest version that matches version_requirement
        versions.sort.reverse.find { |version| version_requirement.satisfied_by?(version) && !version.prerelease? }
      rescue StandardError => e
        raise HTTPError, "Unexpected transport error (#{e.class}: #{e.message})"
      end

      def resolve_import_urls(import_definitions)
        response = Net::HTTP.post(
          URI("https://api.jspm.io/generate"),
          {
            install: import_definitions,
            flattenScope: true,
            env: %w[browser module production],
            defaultProvider: "jspm.io"
          }.to_json,
          "Content-Type" => "application/json"
        )

        json_response = JSON.parse(response.body)

        if response.code != "200"
          raise "Error resolving imports: #{json_response['error']}"
        end

        # Note: ideally, we would also want to pull "scopes" out of the response, to support
        # incompatible subdependencies. However, importmap-rails does not support subdependencies
        # yet: https://github.com/rails/importmap-rails/issues/148
        json_response.dig("map", "imports").sort.to_h
      end

      def update_lockfile!(import_map, lockfile)
        lockfile ||= Rails.root.join("config/importmap-packages-lock.rb")

        File.open(lockfile, "w") do |f|
          f << "# NOTE: this file is managed by importmap-package-manager.\n"
          f << "# DO NOT edit this file directly! Instead, edit `config/importmap_packages.yml` and run `rake importmap_package_manager:update`\n"

          import_map.each do |import, url|
            f << %(pin "#{import}", to: "#{url}"\n)
          end
        end
      end
    end
  end
end
