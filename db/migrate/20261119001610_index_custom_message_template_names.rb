# NTF-03: a business's own template names are unique, ignoring case (backs the validation
# against two quick saves).
class IndexCustomMessageTemplateNames < ActiveRecord::Migration[8.1]
  def change
    add_index :message_templates, "business_id, lower(name)", unique: true, where: "kind IS NULL", name: "index_message_templates_on_business_and_custom_name"
  end
end
