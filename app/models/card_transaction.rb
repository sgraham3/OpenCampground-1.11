class CardTransaction < ActiveRecord::Base
  require 'time'
  require 'net/http'
  require 'faraday'
  require 'base64'
  include MyLib
  belongs_to :reservation
  belongs_to :payment
  validate :expiry_ok
  validate :cvv2_ok
  validates_presence_of :account, :on => :save, :message => "card number required"

  TermCard = 1
  TermManual = 2
  TokenRemote = 3
  TokenLocal = 4

  # virtual methods.  merchid is not needed from the response
  attr_accessor :cardproc
  attr_accessor :commcard
  attr_accessor :entrymode
  attr_accessor :bintype
  attr_accessor :emv
  attr_accessor :emvTagData

  def merchid
  end

  def merchid=(id)
  end

  def token=(tok)
    account = tok
  end

  def fmt_amount
    number_2_currency(amount)
  end

  def fmt_amount=(val)
    ActiveRecord::Base.logger.debug "val is #{val}"
    @amount = val
  end

  def errors_in_transaction
    return false if errors.empty?
    message = ''
    errors.each{|attr,msg| message += "#{attr} - #{msg}\n" }
    return message
  end

  def void_refund
    ################################
    # void or refund a charge
    # first try void then try refund
    ################################
    stat = void
    return stat if respstat == 'A'
    # if that didn't work try refund
    stat = refund
    return stat
  end

  ############################
  # CardPointe Gateway API
  ############################

  ############################
  # not implemented
  ############################
  # capture
  # inquire
  # profile create/update
  # profile get
  # signature capture
  ############################

  def authorize
    ActiveRecord::Base.logger.debug 'authorize:'
    int = Integration.first
    body = {
      "merchid" => int.cc_merchant_id,
      "account" => self.account,
      "expiry" => self.expiry,
      "amount" => (self.amount*100).to_i.to_s,
      "currency" => int.cc_currency_code,
      "capture" => 'Y',
      "orderid" => self.reservation_id
    } 
    body["cvv2"] = self.cvv2 if int.cc_use_cvv
    dest = int.cc_endpoint + '/cardconnect/rest/auth'
    # ActiveRecord::Base.logger.debug "authorize: dest is #{dest}"
    resp = put(dest, body, true)
    ActiveRecord::Base.logger.debug "authorize: #{resp.status}"
    if resp.success?
      body = JSON.parse resp.body
      ActiveRecord::Base.logger.info "body is: #{body.inspect}"
      ActiveRecord::Base.logger.info "respstat is: #{body["respstat"]}"
      update_attributes body
      case body["respstat"]
      when 'A' # Approved
	ActiveRecord::Base.logger.info "authorize: Approved"
	update_attributes body
        # create payment
      when 'B' # retry
	ActiveRecord::Base.logger.info "authorize: Retry"
      when 'C' # declined
	ActiveRecord::Base.logger.info "authorize: Declined"
      else
	ActiveRecord::Base.logger.info "authorize: unrecognized respstat #{body['respstat']}"
      end
    else
      errors.add :base, "communication failure: #{resp.status}"
    end
    return resp
  rescue => err
    errors.add :base, "processing error: #{err.to_s}"
    return false
  end

  def void
    ActiveRecord::Base.logger.debug 'void:'
    int = Integration.first
    body = {
      "merchid" => int.cc_merchant_id,
      "retref"=> self.retref
    } 
    dest = int.cc_endpoint + '/cardconnect/rest/void'
    # ActiveRecord::Base.logger.debug "void: dest is #{dest}"
    resp = put(dest, body, true)
    ActiveRecord::Base.logger.debug "void: #{resp.status}"
    if resp.success?
      body = JSON.parse resp.body
      ActiveRecord::Base.logger.info "void: body is #{body.inspect}"
      case body['respstat']
      when 'A' # Approved
	ActiveRecord::Base.logger.info "void: Approved"
	update_attributes body
	update_attributes :resptext => authcode if respstat == 'A'
      when 'B' # retry
	ActiveRecord::Base.logger.info "void: Retry"
      when 'C' # declined
	ActiveRecord::Base.logger.info "void: Declined"
      else
	ActiveRecord::Base.logger.info "void: unrecognized respstat #{body['respstat']}"
      end
    else
      errors.add :base, "communication failure: #{resp.status}"
    end
    return resp.success?
  rescue => err
    errors.add :base, "processing error: #{err.to_s}"
    return false
  end

  def refund
    ActiveRecord::Base.logger.debug 'refund:'
    int = Integration.first
    body = {
      "retref" => self.retref,
      "merchid" => int.cc_merchant_id,
      "amount" => (self.amount*100).to_i.to_s,
    } 
    dest = int.cc_endpoint + '/cardconnect/rest/refund'
    # ActiveRecord::Base.logger.debug "refund: dest is #{dest}"
    resp = put(dest, body, true)
    ActiveRecord::Base.logger.info "refund: #{resp.status}"
    if resp.success?
      body = JSON.parse resp.body
      case body['respstat']
      when 'A' # Approved
	ActiveRecord::Base.logger.info "refund: Approved"
	update_attributes body
        # create payment
      when 'B' # retry
	ActiveRecord::Base.logger.info "refund: Retry"
      when 'C' # declined
	ActiveRecord::Base.logger.info "refund: Declined"
      else
	ActiveRecord::Base.logger.info "refund: unrecognized respstat #{body['respstat']}"
      end
    else
      errors.add :base, "communication failure: #{resp.status}"
    end
    return resp.success?
  rescue => err
    errors.add :base, "processing error: #{err.to_s}"
    return false
  end

  ############################
  # CardConnect BOLT P2PE API
  ############################

  def ping
    ActiveRecord::Base.logger.debug 'ping:'
    resp = connect
    return resp unless resp.success?
    int = Integration.first
    body = { 
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn
    } 
    dest = int.cc_bolt_endpoint + '/api/v2/ping'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    disconnect
    resp
  end

  def listTerminals
    # no session needed
    ActiveRecord::Base.logger.debug 'listTerminals:'
    int = Integration.first
    if int.cc_merchant_id == nil
      resp = false
      ActiveRecord::Base.logger.debug 'no merchant_id'
    else
      body = { "merchantId" => int.cc_merchant_id }
      dest = int.cc_bolt_endpoint + '/api/v2/listTerminals'
      ActiveRecord::Base.logger.debug "dest is #{dest}"
      resp = post(dest, body)
      ActiveRecord::Base.logger.debug resp.body.inspect
    end
    resp
    # returns: "terminals" : [ "12145SC70108037", 
    #			     "12150SC70110741" ]
  end

  def dateTime
    ActiveRecord::Base.logger.debug 'dateTime:'
    resp = connect
    return resp unless resp.success?
    int = Integration.first
    body = { 
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn ,
      "dateTime" => Time.now.utc.iso8601(6) # "2016-11-29T11:30:45"
    } 
    dest = int.cc_bolt_endpoint + '/api/v2/dateTime'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    disconnect
    # returns html 200 if ok otherwise 400 with errorCode and errorMessage
    resp
  end
  
  def getVersion
    ActiveRecord::Base.logger.debug 'getVersion:'
    resp = connect
    return resp unless resp.success?
    int = Integration.first
    body = { 
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn ,
    } 
    dest = int.cc_bolt_endpoint + '/api/v2/getPanPadVersion'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    # returns {"version" : "1060011"}
    disconnect
    resp
  end


  def authCard
    ActiveRecord::Base.logger.debug 'authCard:'
    resp = connect
    return resp unless resp.success?
    int = Integration.first
    body = {
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn ,
      "amount" => (self.amount*100).to_i.to_s,
      "includeSignature" => int.cc_use_signature.to_s,
      "includeAVS" => int.cc_use_zip.to_s,
      "includeAmountDisplay" => int.cc_display_amount.to_s,
      "includePIN" => "true",
      "beep" => "true" 
    } 
    dest = int.cc_bolt_endpoint + '/api/v3/authCard'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    disconnect
    # ActiveRecord::Base.logger.debug "authCard: resp is #{resp.body}"
    # response contains:
    # "token" : "9445123546981111",
    # "expiry" : "MMYY",
    # "signature" : "<base 64 encoded gzipped BMP>",
    # "name" : "Name on Card",
    # "batchid":"100",
    # "retref":"173006146691",
    # "avsresp":"U",
    # "respproc":"VISA",
    # "amount":"100",
    # "resptext":"Approval",
    # "authcode":"909443",
    # "respcode":"000",
    # "merchid":"1234",
    # "cvvresp":" ",
    # "respstat":"A"
    # ActiveRecord::Base.logger.debug "authCard: #{resp.status}"
    # "token":"9487072434852085","expiry":"0718","name":"SCHERER/NORMAN","batchid":"103","retref":"333975145717","avsresp":"","respproc":"RPCT","amount":"20.00","resptext":"Approval","authcode":"PPS695","respcode":"000","merchid":"800000000074","cvvresp":"","respstat":"A"}
    if resp.success?
      body = JSON.parse resp.body
      # store the returned token in the account member
      body.merge!({"account" => body["token"]})
      update_attributes body
    else
      errors.add :base, "communication failure: #{resp.status}"
    end
    return resp
  rescue => err
    errors.add :base, "processing error: #{err.to_s}"
    return false
  end

  def authManual
    ActiveRecord::Base.logger.debug 'authManual:'
    resp = connect
    return resp unless resp.success?
    int = Integration.first
    body = { 
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn ,
      "amount" => (self.amount*100).to_i.to_s,
      "includeAVS" => int.cc_use_zip.to_s,
      "includeCVV" => int.cc_use_cvv.to_s,
      "includeAmountDisplay" => "false",
      "includePIN" => "true",
      "beep" => "false" 
    } 
    dest = int.cc_bolt_endpoint + '/api/v3/authManual'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    disconnect
    # response contains:
    # "token" : "9445123546981111",
    # "expiry" : "MMYY",
    # "signature" : "<base 64 encoded gzipped BMP>",
    # "batchid":"100",
    # "retref":"173006146691",
    # "avsresp":"U",
    # "respproc":"VISA",
    # "amount":"100",
    # "resptext":"Approval",
    # "authcode":"909443",
    # "respcode":"000",
    # "merchid":"1234",
    # "cvvresp":" ",
    # "respstat":"A"
    # ActiveRecord::Base.logger.debug "authManual: #{resp}"
    if resp.success?
      body = JSON.parse resp.body
      # store the returned token in the account member
      body.merge!({"account" => body["token"]})
      update_attributes body
    else
      errors.add :base, "communication failure: #{resp.status}"
    end
    return resp
  rescue => err
    errors.add :base, "processing error: #{err.to_s}"
    return false
  end
  
  def readCard
    ActiveRecord::Base.logger.debug 'readCard:'
    resp = connect
    return resp unless resp.success?
    int = Integration.first
    body = {
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn ,
      "amount" => (self.amount*100).to_i.to_s,
      "includeSignature" => "true",  
      "includeAmountDisplay" => "true",
      "includePIN" => "true",
      "beep" => "true" 
    } 
    dest = int.cc_bolt_endpoint + '/api/v3/readCard'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    # response contains:
    # "token" : "9445123546981111",
    # "expiry" : "MMYY",
    # "signature" : "<base 64 encoded gzipped BMP>",
    # "name" : "Name on Card"
    ActiveRecord::Base.logger.debug "readCard: #{resp}"
    disconnect
    resp
  end

  def readManual
    ActiveRecord::Base.logger.debug 'readManual:'
    resp = connect
    return resp unless resp.success?
    int = Integration.first
    body = { 
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn ,
      "amount" => (self.amount*100).to_i.to_s,
      "includeSignature" => "true",  
      "includeAmountDisplay" => "true",
      "includePIN" => "true",
      "beep" => "true" 
    } 
    dest = int.cc_bolt_endpoint + '/api/v3/readManual'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    disconnect
    # response contains:
    # "token" : "9445123546981111",
    # "expiry" : "MMYY",
    # "signature" : "<base 64 encoded gzipped BMP>",
    ActiveRecord::Base.logger.debug "readManual: #{resp}"
    resp
  end

  # status of communication
  def commOK?(status)
    if status == '200'
      true
    else
      false
    end
  end

  def commResponse(stat)
    case stat
    when '200'
      'Success'
    when '400'
      'Bad Request'
    when '401'
      'Unauthorized'
    when '403'
      'Invalid HSN for MerchantID'
    when '500'
      'Bolt Client or Server Error'
    else
     "unrecognized #{status}"
    end
  end

  # result of transaction
  def approved?
    case respcode
    # approvals
    when '000','00','008','08','011', '11','085','85'
      # OO,Approval,Approved and completed
      # O8,Honor MasterCard with ID
      # 11,VIP approval
      # 85,,No reason to decline
      true
    else
      false
    end
  end

  private
  ######################
  # custom validators
  ######################
  def cvv2_ok
    int = Integration.first
    case process_mode
    when CardTransaction::TokenLocal, CardTransaction::TokenRemote
      check_cvv
    when CardTransaction::TermCard, CardTransaction::TermManual
      check_cvv if int.cc_use_cvv
    end
  end

  def check_cvv
    # cvv2 must be 3 or 4 digits
    if cvv2.empty?
      errors.add(:cvv2, 'Security code required')
      ActiveRecord::Base.logger.debug "cvv2 missing"
    else
      ActiveRecord::Base.logger.debug "cvv2 is #{cvv2}"
      unless valid_cvv? self.cvv2
	errors.add(:cvv2, 'Security code bad format')
	ActiveRecord::Base.logger.debug "cvv2 #{cvv2} failed validation"
      end
    end
  end

  def valid_cvv?(cvv)
    /\d{3,4}$/ === cvv
  end

  def expiry_ok
  # expiry must be 4 digits.
  # also cannot be earlier than today
    if self.expiry
      # self.expiry.gsub!(/\/|-|[A-z]/,'')
      unless valid_date? self.expiry
	errors.add :expiry, "Expiration date bad format"
	# ActiveRecord::Base.logger.debug 'bad format expiry wrong size'
      else
	yr = expiry[-2,2]
	mo = expiry[0,2]
	# ActiveRecord::Base.logger.debug "Year is #{yr} and month is #{mo}"

	ed = Date.new(yr.to_i + 2000,mo.to_i, 1).end_of_month
	if currentDate > ed
	  errors.add :expiry, "Card expired"
	end
      end
    end
  end

  def valid_date?(dt)
    /^\d{4}$/ === dt
  end

  ######################
  # helpers
  ######################

  def connect
    ActiveRecord::Base.logger.debug 'connect:'
    # ActiveRecord::Base.logger.debug 'connect: getting session key'
    int = Integration.first
    body = { 
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn,
      "force" => "true"
    } 
    dest = int.cc_bolt_endpoint + '/api/v2/connect'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    if resp.success?
      (sk, b, c) = resp.headers['x-cardconnect-sessionkey'].rpartition(';')
      update_attribute :session_key, sk
    end
    ActiveRecord::Base.logger.debug "connect: #{resp.inspect}"
    ActiveRecord::Base.logger.debug "connect: success is #{resp.success?.to_s}"
    resp
  end

  def disconnect
    # ActiveRecord::Base.logger.debug 'disconnect:'
    int = Integration.first
    body = { 
      "merchantId" => int.cc_merchant_id,
      "hsn" => int.cc_hsn 
    }
    dest = int.cc_bolt_endpoint + '/api/v2/disconnect'
    # ActiveRecord::Base.logger.debug "dest is #{dest}"
    resp = post(dest, body)
    update_attribute :session_key, nil
    # ActiveRecord::Base.logger.debug "disconnect: #{resp}"
    resp
  end
  
  def post(dest, body = nil)
    ActiveRecord::Base.logger.debug 'post:'
    ActiveRecord::Base.logger.debug "post: body is #{body.inspect}" if body
    ActiveRecord::Base.logger.debug "post: dest is #{dest}"
    con = Faraday.new :url => dest, :headers => request_header, :ssl => {:verify => false}
    con.options.timeout = 60
    con.options.open_timeout = 5

    xbody = body.to_json
    resp = con.post do |req|
      req.body = xbody
    end
    ActiveRecord::Base.logger.debug "post: resp = #{resp.inspect}"
    ActiveRecord::Base.logger.debug "post: resp headers = #{resp.headers.inspect}"
    ActiveRecord::Base.logger.debug "post: resp status = #{resp.status}"
    ActiveRecord::Base.logger.debug "post: resp body = #{resp.body}" if resp.body
    # ActiveRecord::Base.logger.debug "post: #{resp}"
    resp
  end

  def put(dest, body = nil, auth_hdr = false)
    ActiveRecord::Base.logger.debug 'put:'
    ActiveRecord::Base.logger.debug "put: body is #{body.inspect}" if body
    ActiveRecord::Base.logger.debug "put: dest is #{dest}"
    if auth_hdr
      int = Integration.first
      headers = Hash.new
      headers["Content-Type"] = "application/json"
      con = Faraday.new :url => dest, :headers => headers, :ssl => {:verify => false}
      con.basic_auth(int.cc_api_username, int.cc_api_password)
      ActiveRecord::Base.logger.debug "put: auth_hdr is #{auth_hdr}, headers are #{con.headers.inspect}"
    else
      con = Faraday.new :url => dest, :headers => request_header
      ActiveRecord::Base.logger.debug "put: auth_hdr is #{auth_hdr}, headers are #{con.headers.inspect}"
    end
    xbody = body.to_json
    resp = con.put do |req|
      req.body = xbody
    end
    ActiveRecord::Base.logger.debug "put: resp = #{resp.inspect}"
    ActiveRecord::Base.logger.debug "put: resp headers = #{resp.headers.inspect}"
    ActiveRecord::Base.logger.debug "put: resp status = #{resp.status}"
    ActiveRecord::Base.logger.debug "put: resp body = #{resp.body}" if resp.body
    ActiveRecord::Base.logger.debug "put: #{resp}"
    resp
  rescue => err
    ActiveRecord::Base.logger.debug "put: #{err}"
  end

  def request_header
    # ActiveRecord::Base.logger.debug 'request_header:'
    int = Integration.first
    headers = Hash.new
    headers["Content-Type"] = "application/json"
    # headers["Accept"] = "application/json"
    headers["Authorization"] = int.cc_bolt_api_key
    if session_key != nil
      # ActiveRecord::Base.logger.debug 'request_header: adding key'
      headers["X-CardConnect-SessionKey"] = session_key
    end
    ActiveRecord::Base.logger.debug "request_header: #{headers.inspect}"
    headers
  end
end
