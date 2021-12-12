class Email < ActiveRecord::Base
  belongs_to :smtp_authentication
end
