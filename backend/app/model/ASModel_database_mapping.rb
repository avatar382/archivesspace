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
      # if creating an ArchivalObject or DigitalObjectComponent, and a sibling is set,
      # find that sibling record and set the position so that this new record is adjacent to it.
      # This may be a strange place for this logic -- not sure why, but running this code in ASModel_crud#create_from_json results in the object being updated, but not saved to the DB with the correct value.
      def set_position_from_sibling!(klass, hash)
        new_position = nil
        if klass == JSONModel(:archival_object) && hash["sibling_id"]
          new_position = get_position_between_siblings(hash["sibling_id"], ArchivalObject)

        elsif klass == JSONModel(:digital_object_component) && hash["sibling_id"]
          new_position = get_position_between_siblings(hash["sibling_id"], DigitalObjectComponent)
        end

        if new_position
          hash['position'] = new_position
        end
      end

      # ANW-373
      # we're only going to override the position of this new entity to place it adjacent to it's sibling if:
      # - it has more than one sibling, and
      # - the sibling it should follow isn't itself in the last position
      # - the difference between the physical positions of both siblings is at least 2
      # Otherwise, we'll do nothing and the entity will be placed at the end.
      # This allows for a graceful recovery if something goes wrong, and saves complexity in dealing with edge cases.
      # Given a position step of 1000, in most cases 8 entities can be placed in between before we run out of positions.
      def get_position_between_siblings(sibling_id, klass)
        sibling = klass[sibling_id]
        new_position = nil

        # has a sibling
        if sibling
          sibling_position = sibling.position.to_i

          # if this record has a parent, use that to find siblings at the same level. If not, use the root_record_id to do the same.
          if sibling.parent_id
            siblings = klass.where(parent_id: sibling.parent_id).order(:position).all.map { |s| {"id" => s.id, "position" => s.position.to_i} }
          elsif sibling.root_record_id
            siblings = klass.where(root_record_id: sibling.root_record_id, parent_id: nil).order(:position).all.map { |s| {"id" => s.id, "position" => s.position.to_i} }
          end

          # more than one sibling
          if siblings.length > 1  
            sibling_index = siblings.index {|s| s["id"] == sibling_id.to_i }

            # is our sibling the 'oldest' (highest position?) If so, put this new one at the end
            if sibling_index && sibling_index != siblings.length - 1
              older_sibling = siblings[sibling_index + 1]

              # some defensive programming here. If for some reason our older sibling doesn't have a position, set the value so that this method breaks out at the next if statement.
              older_sibling_position = older_sibling && older_sibling["position"] ? older_sibling["position"] : sibling_position


              # is the gap between our two siblings at least 2?
              if older_sibling_position - sibling_position > 1
                new_position = ((older_sibling_position + sibling_position) / 2).to_i
              end
            end
          end
        end

        return new_position
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
