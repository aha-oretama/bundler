# frozen_string_literal: true

require "bundler/remote_specification"

module Bundler
  class StubSpecification < RemoteSpecification
    def self.from_stub(stub)
      return stub if stub.is_a?(Bundler::StubSpecification)
      spec = new(stub.name, stub.version, stub.platform, nil)
      spec.stub = stub
      spec
    end

    def initialize(*)
      @_remote_specification = nil
      super
    end

    attr_accessor :ignored
    attr_writer :stub

    # Pre 2.2.0 did not include extension_dir
    # https://github.com/rubygems/rubygems/commit/9485ca2d101b82a946d6f327f4bdcdea6d4946ea
    if Bundler.rubygems.provides?(">= 2.2.0")
      def source=(source)
        super
        # Stub has no concept of source, which means that extension_dir may be wrong
        # This is the case for git-based gems. So, instead manually assign the extension dir
        return unless source.respond_to?(:extension_dir_name)
        path = File.join(stub.extensions_dir, source.extension_dir_name)
        stub.extension_dir = File.expand_path(path)
      end
    end

    def to_yaml
      _remote_specification.to_yaml
    end

    # @!group Stub Delegates

    if Bundler.rubygems.provides?(">= 2.3")
      # This is defined directly to avoid having to load every installed spec
      def missing_extensions?
        stub(true).missing_extensions?
      end
    end

    def activated
      stub.activated
    end

    def activated=(activated)
      stub.instance_variable_set(:@activated, activated)
    end

    def default_gem
      stub.default_gem
    end

    def full_gem_path
      # deleted gems can have their stubs return nil, so in that case grab the
      # expired path from the full spec
      stub.full_gem_path || method_missing(:full_gem_path)
    end

    if Bundler.rubygems.provides?(">= 2.2.0")
      def full_require_paths
        stub.full_require_paths
      end

      # This is what we do in bundler/rubygems_ext
      # full_require_paths is always implemented in >= 2.2.0
      def load_paths
        full_require_paths
      end
    end

    def loaded_from
      stub.loaded_from
    end

    if Bundler.rubygems.stubs_provide_full_functionality?
      def matches_for_glob(glob)
        stub.matches_for_glob(glob)
      end
    end

    def raw_require_paths
      stub.raw_require_paths
    end

    # @note
    #   Cannot be an attr_reader that returns @stub, because the stub can pull it's `to_spec`
    #   from `Gem.loaded_specs`, which can end up being self.
    #   #_remote_specification has logic to handle this case, so delegate to that in that situation,
    #   because otherwise we can end up with a stack overflow when calling #missing_extensions?
    def stub(check = false)
      if check && @_remote_specification.nil? && @stub.instance_variable_get(:@data) && Gem.loaded_specs[name].equal?(self)
        _remote_specification
      end
      @stub
    end

  private

    def _remote_specification
      @_remote_specification ||= begin
        rs = @stub.to_spec
        if rs.equal?(self) # happens when to_spec gets the spec from Gem.loaded_specs
          rs = Bundler.load_gemspec(@stub.loaded_from)
          Bundler.rubygems.stub_set_spec(@stub, rs)
        end

        unless rs
          raise GemspecError, "The gemspec for #{full_name} at #{loaded_from}" \
            " was missing or broken. Try running `gem pristine #{name} -v #{version}`" \
            " to fix the cached spec."
        end

        rs.source = source

        rs
      end
    end
  end
end
