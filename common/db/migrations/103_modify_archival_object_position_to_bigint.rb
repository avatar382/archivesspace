require 'db/migrations/utils'

Sequel.migration do
  up do
    # make position column very big
    alter_table(:archival_object) do
      set_column_type(:position, Bignum)
    end
  end

end