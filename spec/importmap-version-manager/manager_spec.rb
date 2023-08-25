RSpec.describe ImportmapPackageManager::Manager do
  describe :update! do
    let(:config) { { "imports" => imports } }
    let(:lockfile) { "#{Dir.pwd}/tmp/test-lockfile.rb" }
    let(:npm_response) { { versions: { "1.0.0" => {}, "1.0.1" => {}, "1.0.2" => {}, "1.1.0" => {}, "2.0.0" => {} } } }
    let!(:npm_request) do
      stub_request(:get, "https://registry.npmjs.org/package-name")
        .with(headers: { "Content-Type" => "application/json" })
        .to_return_json(body: npm_response)
    end

    let(:jspm_install_definitions) { [{ target: "package-name@#{expected_version}" }] }
    let(:jspm_package_url) { "https://ga.jspm.io/npm:package-name@#{expected_version}/index.js" }
    let(:jspm_response_imports) { { "package-name" => jspm_package_url } }
    let!(:jspm_request) do
      stub_request(:post, "https://api.jspm.io/generate")
        .with(
          body: {
            install: jspm_install_definitions,
            flattenScope: true,
            env: %w[browser module production],
            defaultProvider: "jspm"
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
        .to_return_json(body: { map: { imports: jspm_response_imports } })
    end

    shared_examples_for "correct behavior" do
      it "requests NPM for versions, requests JSPM for url, and creates the importmap lockfile correctly" do
        ImportmapPackageManager::Manager.update!(config: config, lockfile: lockfile)

        expect(npm_request).to have_been_made
        expect(jspm_request).to have_been_made

        lockfile_contents = File.read(lockfile)

        expect(lockfile_contents).to match("# DO NOT edit this file directly!")
        expect(lockfile_contents).to match(%(pin "package-name", to: "#{jspm_package_url}"))
      end
    end

    context "when given a specific package number" do
      let(:imports) { { "package-name" => "1.0.0" } }
      let(:expected_version) { "1.0.0" }

      it_behaves_like "correct behavior"
    end

    context "when given a package version allowing patch versions" do
      let(:imports) { { "package-name" => "~> 1.0.0" } }
      let(:expected_version) { "1.0.2" }

      it_behaves_like "correct behavior"
    end

    context "when given a package version allowing minor versions" do
      let(:imports) { { "package-name" => "~> 1.0" } }
      let(:expected_version) { "1.1.0" }

      it_behaves_like "correct behavior"
    end

    context "when given a nested package config" do
      let(:imports) { { "package-name" => { "package" => "package-name", "version" => "1.0.0" } } }
      let(:expected_version) { "1.0.0" }

      it_behaves_like "correct behavior"
    end

    context "when given a nested package config w/ subpath" do
      let(:imports) { { "package-name" => { "package" => "package-name", "version" => "1.0.0", "subpath" => "./whatever.js" } } }
      let(:expected_version) { "1.0.0" }
      let(:jspm_install_definitions) { [{ target: "package-name@#{expected_version}", subpath: "./whatever.js" }] }
      let(:jspm_package_url) { "https://ga.jspm.io/npm:package-name@#{expected_version}/whatever.js" }

      it_behaves_like "correct behavior"
    end

    context "when given a package config array" do
      let(:imports) { { "package-name" => ["> 1.0.0", "< 1.0.2"] } }
      let(:expected_version) { "1.0.1" }

      it_behaves_like "correct behavior"
    end

    context "when given a package that has sub-dependencies" do
      let(:imports) { { "package-name" => "1.0.0" } }
      let(:expected_version) { "1.0.0" }
      let(:jspm_subpackage_url) { "https://ga.jspm.io/npm:subpackage-name@1.0.0/index.js" }
      let(:jspm_response_imports) { { "package-name" => jspm_package_url, "subpackage-name" => jspm_subpackage_url } }

      it "pins subdependencies" do
        ImportmapPackageManager::Manager.update!(config: config, lockfile: lockfile)

        expect(npm_request).to have_been_made
        expect(jspm_request).to have_been_made

        lockfile_contents = File.read(lockfile)

        expect(lockfile_contents).to match("# DO NOT edit this file directly!")
        expect(lockfile_contents).to match(%(pin "package-name", to: "#{jspm_package_url}"))
        expect(lockfile_contents).to match(%(pin "subpackage-name", to: "#{jspm_subpackage_url}"))
      end
    end
  end
end
