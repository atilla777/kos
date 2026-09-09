class ApplicationRecord < ActiveRecord::Base
  IDENTIFIER_FORMAT = /\A[a-z][a-z0-9_-]{0,127}\z/

  primary_abstract_class
end
