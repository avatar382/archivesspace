require 'oai'

require_relative 'aspace_oai_repository'
require_relative 'aspace_oai_record'
require_relative 'ead_format'
require_relative 'dc_terms_format'
require_relative 'marc_format'
require_relative 'mods_format'

# Load our gem overrides
Dir.glob(File.join(File.dirname(__FILE__), "oai_gem_patches", "*.rb")).sort.each do |patch|
  require File.absolute_path(patch)
end

class ArchivesSpaceOaiProvider < OAI::Provider::Base
  # ANW-674: retrieve OAI config vars from database instead of config file
  oai_config = OAIConfig.all.first

  repository_name oai_config[:oai_repository_name]
  repository_url AppConfig[:oai_proxy_url]
  record_prefix oai_config[:oai_record_prefix]
  admin_email oai_config[:oai_admin_email]
  sample_id '/repositories/2/resources/1'

  deletion_support OAI::Const::Delete::PERSISTENT

  source_model ArchivesSpaceOAIRepository.new

  register_format EADFormat.instance
  register_format DCTermsFormat.instance
  register_format MARCFormat.instance
  register_format MODSFormat.instance
end
