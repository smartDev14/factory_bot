module FactoryBot
  class DefinitionProxy
    UNPROXIED_METHODS = %w(__send__ __id__ nil? send object_id extend instance_eval initialize block_given? raise caller method).freeze

    (instance_methods + private_instance_methods).each do |method|
      undef_method(method) unless UNPROXIED_METHODS.include?(method.to_s)
    end

    delegate :before, :after, :callback, to: :@definition

    attr_reader :child_factories

    def initialize(definition, ignore = false)
      @definition      = definition
      @ignore          = ignore
      @child_factories = []
    end

    def singleton_method_added(name)
      message = "Defining methods in blocks (trait or factory) is not supported (#{name})"
      raise FactoryBot::MethodDefinitionError, message
    end

    # Adds an attribute to the factory.
    # The attribute value will be generated "lazily"
    # by calling the block whenever an instance is generated.
    # The block will not be called if the
    # attribute is overridden for a specific instance.
    #
    # Arguments:
    # * name: +Symbol+ or +String+
    #   The name of this attribute. This will be assigned using "name=" for
    #   generated instances.
    def add_attribute(name, &block)
      declaration = Declaration::Dynamic.new(name, @ignore, block)
      @definition.declare_attribute(declaration)
    end

    def transient(&block)
      proxy = DefinitionProxy.new(@definition, true)
      proxy.instance_eval(&block)
    end

    # Calls add_attribute using the missing method name as the name of the
    # attribute, so that:
    #
    #   factory :user do
    #     name { 'Billy Idol' }
    #   end
    #
    # and:
    #
    #   factory :user do
    #     add_attribute(:name) { 'Billy Idol' }
    #   end
    #
    # are equivalent.
    #
    # If no argument or block is given, factory_bot will look for a sequence
    # or association with the same name. This means that:
    #
    #   factory :user do
    #     email { create(:email) }
    #     association :account
    #   end
    #
    # and:
    #
    #   factory :user do
    #     email
    #     account
    #   end
    #
    # are equivalent.
    def method_missing(name, *args, &block) # rubocop:disable Style/MethodMissing
      if args.empty?
        __declare_attribute__(name, block)
      elsif args.first.respond_to?(:has_key?) && args.first.has_key?(:factory)
        association(name, *args)
      else
        raise NoMethodError.new(
          "undefined method '#{name}' in '#{@definition.name}' factory",
        )
      end
    end

    # Adds an attribute that will have unique values generated by a sequence with
    # a specified format.
    #
    # The result of:
    #   factory :user do
    #     sequence(:email) { |n| "person#{n}@example.com" }
    #   end
    #
    # Is equal to:
    #   sequence(:email) { |n| "person#{n}@example.com" }
    #
    #   factory :user do
    #     email { FactoryBot.generate(:email) }
    #   end
    #
    # Except that no globally available sequence will be defined.
    def sequence(name, *args, &block)
      sequence_name = "__#{@definition.name}_#{name}__"
      sequence = Sequence.new(sequence_name, *args, &block)
      FactoryBot.register_sequence(sequence)
      add_attribute(name) { increment_sequence(sequence) }
    end

    # Adds an attribute that builds an association. The associated instance will
    # be built using the same build strategy as the parent instance.
    #
    # Example:
    #   factory :user do
    #     name 'Joey'
    #   end
    #
    #   factory :post do
    #     association :author, factory: :user
    #   end
    #
    # Arguments:
    # * name: +Symbol+
    #   The name of this attribute.
    # * options: +Hash+
    #
    # Options:
    # * factory: +Symbol+ or +String+
    #    The name of the factory to use when building the associated instance.
    #    If no name is given, the name of the attribute is assumed to be the
    #    name of the factory. For example, a "user" association will by
    #    default use the "user" factory.
    def association(name, *options)
      if block_given?
        raise AssociationDefinitionError.new(
          "Unexpected block passed to '#{name}' association "\
          "in '#{@definition.name}' factory",
        )
      else
        declaration = Declaration::Association.new(name, *options)
        @definition.declare_attribute(declaration)
      end
    end

    def to_create(&block)
      @definition.to_create(&block)
    end

    def skip_create
      @definition.skip_create
    end

    def factory(name, options = {}, &block)
      @child_factories << [name, options, block]
    end

    def trait(name, &block)
      @definition.define_trait(Trait.new(name, &block))
    end

    def initialize_with(&block)
      @definition.define_constructor(&block)
    end

    private

    def __declare_attribute__(name, block)
      if block.nil?
        declaration = Declaration::Implicit.new(name, @definition, @ignore)
        @definition.declare_attribute(declaration)
      else
        add_attribute(name, &block)
      end
    end
  end
end
