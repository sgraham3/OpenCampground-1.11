class Integration < ActiveRecord::Base
  include ActiveMerchant::Billing::Integrations
  include MyLib
  require 'cryptoOC'
  require 'openssl'

  def cc_gateway
    if ENV['RAILS_ENV'] == 'production'
      'https://boltgw.cardconnect.com:8443'
    else
      'https://boltgw.cardconnect.com:6443'
    end
  end

  def self.first_or_create(attributes = nil, &block)
    first || create(attributes, &block)
  end

  def self.terminal?
    first.cc_bolt_api_key.size > 0
  end

  def self.no_terminal?
    first.cc_bolt_api_key.size == 0
  end

  def handle_response(request, params)
    case name
    when 'PayPal'
      ActiveRecord::Base.logger.debug 'PayPal'
      handle_paypal(request, params)
    when 'FirstDataE4'
      ActiveRecord::Base.logger.debug 'FirstDataE4'
      handle_firstdatae4(request, params)
    else
      ActiveRecord::Base.logger.debug 'unsupported'
      raise 'Unsupported integration'
    end
  end

  def handle_firstdatae4(request, params)
    # from /usr/lib/ruby/gems/1.8/gems/activemerchant-1.33.0/lib/active_merchant/billing/integrations/first_data/notification.rb
    # notify = FirstData::Notification.new(request.raw_post)
    # ActiveRecord::Base.logger.debug notify.inspect
    # passed = notify.complete?
    err_msg = ''
    memo = ''
    passed = params[:x_response_code] == '1'
    #
    begin
      # res = Reservation.find(notify.invoice_num)
      reservation = Reservation.find(params[:x_invoice])
    rescue ActiveRecord::RecordNotFound
      ActiveRecord::Base.logger.error "reservation #{params[:x_invoice]} not found"
      @message = 'Error--unable to find your transaction! Please contact us directly.'
      render :action => 'payment_error' and return
    end
    #
    # if res.total != notify.gross.to_f
    # if reservation.total != params[:x_amount].to_f
      # ActiveRecord::Base.logger.error "First Data said they paid for #{params[:x_amount].to_f} and it should have been #{reservation.total}!"
      # passed = false
    # end
    #
    # # Theoretically, First Data will *never* pass us the same transaction
    # # ID twice, but we can double check that... by using
    # # notify.transaction_id, and checking against previous orders' transaction
    # # id's (which you can save when the order is completed)....
    # unless notify.acknowledge FIRST_DATA_TRANSACTION_KEY, FIRST_DATA_RESPONSE_KEY
      # passed = false
      # error "ALERT POSSIBLE FRAUD ATTEMPT"
    # end
    #
    # Address verification
    unless ['X','D','2'].include? params[:x_avs_code]
      memo += "address verification error code #{params[:x_avs_code]} "
      ActiveRecord::Base.logger.error 'Error: address verification error ' + params[:x_avs_code]
    end

    # cvv2 processing
    unless params[:CVD_Presence_Ind] == '0'
      unless params[:x_cvv2_resp_code] == 'M'
        memo += "cvv2 resp code is ${params[:x_cvv2_resp_code]} "
	ActiveRecord::Base.logger.error 'Error: cvv2 code error ' + params[:x_cvv2_resp_code]
      end
    end
    #
    if passed
      # Set up your session, and render something that will redirect them to
      # your site, most likely.
      unless reservation.confirm?
	ActiveRecord::Base.logger.info 'reservation not confirmed yet'
	err_msg = 'Could not update reservation '
	reservation.update_attributes(:confirm => true,
				      :gateway_transaction => params[:x_trans_id])
	ActiveRecord::Base.logger.info 'updated with transaction ' + params[:x_trans_id]
	begin
	  card = Creditcard.find_by_name! 'FirstData'
	rescue
	  card = Creditcard.first
          memo += 'FirstData'
	end
	begin
	  err_msg = 'Could not create payment '
	  Payment.create!(:reservation_id => reservation.id,
			 :creditcard_id => card.id,
			 :amount => params[:x_amount],
			 :memo => memo)
	  ActiveRecord::Base.logger.info 'created payment with amount ' + params[:x_amount]
	rescue  ActiveRecord::RecordInvalid => err
	  ActiveRecord::Base.logger.error err_msg + err
	end
      end
# acknowledge
#             Digest::MD5.hexdigest(response_key + payment_page_id + params['x_trans_id'] + sprintf('%.2f', gross)) == params['x_MD5_Hash'].downcase
    else
      # Render failure or redirect them to your site where you will render failure
      ActiveRecord::Base.logger.error 'failed' + err_msg
    end
    ActiveRecord::Base.logger.info 'passed is ' + passed.to_s
    return passed
  rescue => err
    ActiveRecord::Base.logger.error err_msg + err.to_s
  end

  def handle_paypal(request, params)
    option = Option.first
    notify = Paypal::Notification.new(request.raw_post)
    if notify.acknowledge
      if notify.complete?
	begin
	  err_msg = 'Could not find reservation '
	  reservation = Reservation.find params[:invoice]
	  unless reservation.confirm?
	    err_msg = 'Could not update reservation '
	    reservation.confirm = true
	    reservation.unconfirmed_remote = true unless option.remote_auto_accept
	    reservation.gateway_transaction = params[:txn_id]
	    amount = 0.0
	    if defined?(params[:mc_gross]) && params[:mc_gross] != ''
	      amount = params[:mc_gross]
	    elsif defined?(params[:payment_gross]) && params[:payment_gross] != ''
	      amount = params[:payment_gross]
	    end
	    reservation.deposit = amount if defined? params[:custom] && params[:custom].include?('Deposit')
	    reservation.save!
	    memo = ''
	    memo += "fee: #{params[:mc_fee]} " if defined?(params[:mc_fee])
	    if defined?(params[:item_name])
	      memo += params[:item_name]
	    elsif defined?(params[:item_name1])
	      memo += params[:item_name1]
	    end
	    begin
	      card = Creditcard.find_by_name! 'PayPal'
	    rescue
	      card = Creditcard.first
	      memo += " PayPal "
	    end
	    memo += " #{params[:custom]}" if defined? params[:custom] && params[:custom] != 'Full'
	    Payment.create(:reservation_id => reservation.id,
                           :creditcard_id => card.id,
                           :amount => amount,
                           :memo => memo) if reservation
            return true
	  end
	rescue => err
	  ActiveRecord::Base.logger.error 'Error: ' + err_msg + err.to_s
	end
      else
	# Reason to be suspicious.. send some notify of a problem
	ActiveRecord::Base.logger.error "transaction #{notify.transaction_id.to_s} notify not completed"
      end
    else # transaction not acknowledged.....
      ActiveRecord::Base.logger.error "transaction #{notify.transaction_id.to_s} not acknowledged"
    end
    return false
  end

  def firstdatae4_hash(res, total)
    hash_str = "#{fd_login}^#{res.id.to_s}^#{res.created_at.strftime("%s")}^#{sprintf("%0.2f", total)}^"
    ActiveRecord::Base.logger.debug hash_str
    hash = OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new('md5'), fd_transaction_key, hash_str)
  end

  def paypal_fetch_decrypted(res, path)

    option = Option.first
    return false if(pp_business == nil || pp_cert_id == nil)
    # cert_id is the certificate we see in paypal when we upload our own certificates
    # cmd _xclick need for buttons
    # item name is what the user will see at the paypal page
    # custom and invoice are passthrough vars which we will get back with the asynchronous
    # notification
    # no_note and no_shipping means the client wont see these extra fields on the paypal payment
    # page
    # return is the url the user will be redirected to by paypal when the transaction is completed.
    disc = 0.0
    if res.discount.id > 1
      Charge.stay(res.id).each { |charge| disc += charge.discount}
    end
    item_name = "Reservation for space #{res.space.name} from #{res.startdate} to #{res.enddate}"
    deposit = res.deposit_amount
    decrypted = {
      "business" => pp_business,
      "cmd" => "_xclick",
      "return" => path + "/remote/wait_for_confirm?id=#{res.id}",
      "notify_url" => path + "/remote/ipn",
      "invoice" => res.id.to_s,
      "cert_id" => pp_cert_id,
      "item_name" => item_name,
      "item_number" => "1",
      "custom" => deposit['custom'],
      "amount" => sprintf("%02f", deposit['amount']),
      "tax" => sprintf("%02f", deposit['tax']),
      "currency_code" => pp_currency_code,
      "country" => pp_country,
      "no_note" => "1",
      "no_shipping" => "1"
    }
    # discount is included in the amount
    # decrypted[:discount_amount] = disc if disc > 0.0
    ActiveRecord::Base.logger.debug decrypted.inspect
    CryptoOC::Button.from_hash(decrypted).get_encrypted_text
  end

end
