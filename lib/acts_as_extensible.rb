# Delegates columns of a has_one association and creates the proxy methods
# in the caller. For instance, if a class +User+ defines +has_one :user_extension+,
# then after the statement +delegate_colums_of :user_extension+ it is possible to
# query the object instances for methods in the associated class, i.e:
#
#   @user.can_set_as_final? # false
#   @user.can_set_as_final = 1
#   @user.can_set_as_final? # true
#   @user.can_set_as_final  # 1
#
# The following options are allowed:
#
#   :except => array    # Excludes the column names form the delegation.
#   :prefix => true     # Prefixes each column with the model name.
#
module ActsAsExtensible
  module ColumnDelegation
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def acts_as_extensible extension = extension_model, options = {}
        has_one extension, options
        delegate_columns_of extension
        validates_columns_for extension
        after_destroy do |record|
          record.send(extension).destroy
        end
      end

      def extension_model
        :"#{self.name.underscore}_extension"
      end

      def delegate_columns_of model, options = {}
        exceptions = (options[:except] ||= []) << 'id'
        prefix = options[:prefix] ? "#{model}_" : ''
        model_class = model.to_s.camelcase
        columns = model_class.constantize.column_names
        for column in columns - exceptions
          for suffix in ['', '= value', '?']
            class_eval <<-eos
              def #{prefix}#{column}#{suffix}
                build_#{model} if #{model}.nil?
                #{model}.#{column}#{suffix}
              end
            eos
          end

          class_eval <<-eos
            after_save :update_#{model}_attributes

            protected

            def update_#{model}_attributes
              build_#{model} if #{model}.nil?
              #{model}.save
            end
          eos

          class_eval <<-eos
            def column_for_attribute_#{prefix}#{column}
              #{model_class}.columns_hash["#{column}"]
            end
          eos
        end
        include ActsAsExtensible::ColumnDelegation::InstanceMethods
      end

      def validates_columns_for model, options = {}
        prefix = options[:prefix] ? "#{model}_" : ''
        class_eval <<-eos
          protected :validate

          def validate
            super
            unless errors.any?
              build_#{model} if #{model}.nil?
              unless #{model}.valid?
                #{model}.errors.each do |k, v|
                  errors.add("#{prefix}" + k, v)
                end
              end
            end
          end
        eos
      end
    end

    module InstanceMethods
      def column_for_attribute name
        respond_to?("column_for_attribute_#{name}") ?
          send("column_for_attribute_#{name}".intern) : super(name)
      end
    end
  end
end

ActiveRecord::Base.send(:include, ActsAsExtensible::ColumnDelegation)
