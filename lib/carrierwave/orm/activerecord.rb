# encoding: utf-8

require 'active_record'
require 'carrierwave/validations/active_model'

module CarrierWave
  module ActiveRecord

    include CarrierWave::Mount

    ##
    # See +CarrierWave::Mount#mount_uploader+ for documentation
    #
    def mount_uploader(column, uploader=nil, options={}, &block)
      super

      class_eval <<-RUBY, __FILE__, __LINE__+1
        def remote_#{column}_url=(url)
          column = _mounter(:#{column}).serialization_column
          send(:"\#{column}_will_change!")
          super
        end
      RUBY
    end

    ##
    # See +CarrierWave::Mount#mount_uploaders+ for documentation
    #
    def mount_uploaders(column, uploader=nil, options={}, &block)
      super

      class_eval <<-RUBY, __FILE__, __LINE__+1
        def remote_#{column}_urls=(url)
          column = _mounter(:#{column}).serialization_column
          send(:"\#{column}_will_change!")
          super
        end
      RUBY
    end

  private

    def mount_base(column, uploader=nil, options={}, &block)
      super

      alias_method :read_uploader, :read_attribute
      alias_method :write_uploader, :write_attribute
      public :read_uploader
      public :write_uploader

      include CarrierWave::Validations::ActiveModel

      validates_integrity_of column if uploader_option(column.to_sym, :validate_integrity)
      validates_processing_of column if uploader_option(column.to_sym, :validate_processing)
      validates_download_of column if uploader_option(column.to_sym, :validate_download)

      after_save :"store_#{column}!"
      before_save :"write_#{column}_identifier"
      after_commit :"remove_#{column}!", :on => :destroy
      after_commit :"mark_remove_#{column}_false", :on => :update

      after_save :"store_previous_changes_for_#{column}"
      after_commit :"remove_previously_stored_#{column}", :on => :update

      def write_uploader(column, identifier)
        ar_store = self.class.stored_attributes.find { |_store, attributes| attributes.include?(column) }.try(:first)
        if ar_store
          __send__("#{ar_store}_will_change!".to_sym)
          __send__(ar_store)[column.to_s] = identifier
        else
          write_attribute(column, identifier)
        end
      end

      def read_uploader(column)
        ar_store = self.class.stored_attributes.find { |_store, attributes| attributes.include?(column) }.try(:first)
        if ar_store
          __send__(ar_store)[column.to_s]
        else
          read_attribute(column)
        end
      end

      class_eval <<-RUBY, __FILE__, __LINE__+1
        def #{column}=(new_file)
          column = _mounter(:#{column}).serialization_column
          if !(new_file.blank? && send(:#{column}).blank?)
            send(:"\#{column}_will_change!")
          end

          super
        end

        def remove_#{column}=(value)
          send(:"#{column}_will_change!")
          super
        end

        def remove_#{column}!
          super
          self.remove_#{column} = true
          write_#{column}_identifier
        end

        # Reset cached mounter on record reload
        def reload(*)
          @_mounters = nil
          super
        end

        # Reset cached mounter on record dup
        def initialize_dup(other)
          @_mounters = nil
          super
        end
      RUBY
    end

  end # ActiveRecord
end # CarrierWave

ActiveRecord::Base.extend CarrierWave::ActiveRecord
