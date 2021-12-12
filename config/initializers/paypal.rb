# Be sure to restart your server when you modify this file.

if ENV['RAILS_ENV'] == "production"
  ActiveMerchant::Billing::Base.gateway_mode = :production
  ActiveMerchant::Billing::Base.integration_mode = :production
else
  # Ensure the gateway is in test mode
  ActiveMerchant::Billing::Base.gateway_mode = :test
  ActiveMerchant::Billing::Base.integration_mode = :test
end
ActiveMerchant::Billing::PaypalGateway.pem_file = File.read(RAILS_ROOT + '/config/paypal/paypal_cert.pem')
