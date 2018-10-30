module ASModel
  # Some low-level details of mapping certain Ruby types to database types.
  module DatabaseMapping

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      JSON_TO_DB_MAPPINGS = {
        'boolean' => {
          :description => "JSON booleans become DB integers",
          :json_to_db => ->(bool) { bool ? 1 : 0 },
          :db_to_json => ->(int) { int === 1 }
        },
        'date' => {
          :description => "Date strings become dates",
          :json_to_db => ->(s) { s.nil? ? s : Date.parse(s) },
          :db_to_json => ->(date) { date.nil? ? date : date.strftime('%Y-%m-%d') }
        }
      }


      def prepare_for_db(jsonmodel_class, hash)
        schema = jsonmodel_class.schema
        hash = hash.clone
        schema['properties'].each do |property, definition|
          mapping = JSON_TO_DB_MAPPINGS[definition['type']]
          if mapping && hash.has_key?(property)
            hash[property] = mapping[:json_to_db].call(hash[property])
          end
        end

        nested_records.each do |nested_record|
          # Nested records will be processed separately.
          hash.delete(nested_record[:json_property].to_s)
        end

        set_position_from_sibling!(jsonmodel_class, hash)

        hash['json_schema_version'] = jsonmodel_class.schema_version


        hash
      end


      # ANW-373
      # if creatomg an ArchivalObject or DigitalObjectComponent, and a sibling is set,
      # find that sibling record and set the position so that this new record is adjacent to it.
      # This may be a strange place for this logic -- not sure why, but running this code in ASModel_crud#create_from_json results in the object being updated, but not saved to the DB with the correct value.
      def set_position_from_sibling!(klass, hash)
        if klass == JSONModel(:digital_object_component) || klass == JSONModel(:archival_object)
          if hash["sibling_id"]

            # TODO: SET POSITION HERE!
            # LOOK up sibling ID, find position and increment it intelligently
            hash['position'] = 72
          end
        end
      end


      def map_db_types_to_json(schema, hash)
        hash = hash.clone
        schema['properties'].each do |property, definition|
          mapping = JSON_TO_DB_MAPPINGS[definition['type']]

          property = property.intern
          if mapping && hash.has_key?(property)
            hash[property] = mapping[:db_to_json].call(hash[property])
          end
        end

        hash
      end
    end
  end
end
