class CardTransactionsController < ApplicationController
  # GET /card_transactions
  # GET /card_transactions.xml
  require 'pp'

  def index
    @card_transactions = CardTransaction.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @card_transactions }
    end
  end

  # GET /card_transactions/1
  # GET /card_transactions/1.xml
  def show
    @card_transaction = CardTransaction.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @card_transaction }
    end
  end

  # GET /card_transactions/new
  # GET /card_transactions/new.xml
  def new
    @integration = Integration.first
    # create a card transaction
    debug 'create a card transaction'
    @card_transaction = CardTransaction.new(params[:card_transaction])
    debug @card_transaction.inspect
  end

  # GET /card_transactions/1/edit
  def edit
    @card_transaction = CardTransaction.find(params[:id])
  end

  # POST /card_transactions
  # POST /card_transactions.xml
  def create
    debug 
    expiry = Date.civil(params[:card_transaction]["expiry(1i)"].to_i,
			params[:card_transaction]["expiry(2i)"].to_i,
			params[:card_transaction]["expiry(3i)"].to_i)
    new_params = Hash.new
    # copy params and substitute expiry for the three values.
    params[:card_transaction].each do |key,value|
      case key
      when "expiry(1i)","expiry(2i)","expiry(3i)"
        # just skip over these
      else
	new_params[key] = value
      end
    end
    # insert mmyy as expiry and create the transaction
    new_params[:expiry] = expiry.strftime("%m%y")
    card_transaction = CardTransaction.create(new_params)
    debug 'created'
    err = card_transaction.errors_in_transaction
    if err
      debug 'processing error'
      message = 'create error: '
      flash[:error] =  message + err
      error message + err
      if card_transaction.process_mode == CardTransaction::TokenRemote
	redirect_to :controller => :remote, :action => :payment and return
      else
	redirect_to :controller => :reservation, :action => :show, :reservation_id => card_transaction.reservation.id and return
      end
    end
    debug 'created'
    debug "process mode is #{card_transaction.process_mode}"
    case card_transaction.process_mode
    when CardTransaction::TokenLocal, CardTransaction::TokenRemote
      debug 'CardTransaction::TokenLocal, CardTransaction::TokenRemote'
      # a tokenized transaction
      # and we will process an authorize
      resp = card_transaction.authorize
      err = card_transaction.errors_in_transaction
      debug "err in authorize is #{err}"
      if err
	message = 'processing error: '
	flash[:error] =  message + err
	error message + err
	if card_transaction.process_mode == CardTransaction::TokenRemote
	  redirect_to :controller => :remote, :action => :payment and return
	else
	  redirect_to :controller => :reservation, :action => :show, :reservation_id => card_transaction.reservation.id and return
	end
      end
      debug 'completed authorize'
      debug "card_transaction id is #{card_transaction.id}, reservation_id is #{card_transaction.reservation_id}, success = #{resp.success?}"
      if resp.class == Faraday::Response && resp.success?
	# communication was successful
	if card_transaction.respstat == 'A'
	  info 'transaction approved'
	  # record payment
	  # store payment details
	  # ref no etc are in the card_transaction
	  # debug "account is #{card_transaction.account}"
	  creditcard_name = Creditcard.card_type(card_transaction.account[1].chr)
	  # debug "creditcard name is #{creditcard_name}"
	  creditcard_id = Creditcard.find_or_create_by_name(creditcard_name).id
	  # debug "creditcard_id is #{creditcard_id}"
	  p = Payment.create(:reservation_id => card_transaction.reservation_id,
                             :credit_card_no => '****' + card_transaction.account[-4..-1],
                             :creditcard_id => creditcard_id,
                             :amount => card_transaction.amount,
                             :cc_expire => card_transaction.expiry,
                             :memo => "card not present, retref #{card_transaction.retref}")
	  card_transaction.reservation.update_attributes :confirm => true
	  card_transaction.update_attributes :payment_id => p.id
	  flash[:notice] = "Transaction approved"
	else
	  debug "Transaction not approved: #{card_transaction.resptext} (code #{card_transaction.respcode})"
	  flash[:error] = "Transaction not approved: #{card_transaction.resptext} (code #{card_transaction.respcode})"
	  @success = false
	  if card_transaction.process_mode == CardTransaction::TokenRemote
	    redirect_to :controller => :remote, :action => :payment and return
	  else
	    redirect_to :controller => :reservation, :action => :show, :reservation_id => card_transaction.reservation.id and return
	  end
	end
      else
        err = card_transaction.errors_in_transaction
	message = 'communication error: '
	flash[:error] =  message + err
	error message + err
	if card_transaction.process_mode == CardTransaction::TokenRemote
	  redirect_to :controller => :remote, :action => :payment and return
	else
	  redirect_to :controller => :reservation, :action => :show, :reservation_id => card_transaction.reservation.id and return
	end
      end
      redirect_to :controller => :remote, :action => :confirmation and return if card_transaction.process_mode == CardTransaction::TokenRemote
    when CardTransaction::TermCard, CardTransaction::TermManual
      debug 'CardTransaction::TermCard, CardTransaction::TermManual'
      # card processing
      if card_transaction.process_mode == CardTransaction::TermCard
	debug 'card present processing'
	resp = card_transaction.authCard
	err = card_transaction.errors_in_transaction
	if err
	  message = 'processing error: '
	  flash[:error] =  message + err
	  error message + err
	  redirect_to :controller => :reservation, :action => :show, :reservation_id => card_transaction.reservation.id and return
	end
	debug 'completed authCard'
      else
        # CardTransaction::TermManual
	debug 'manual processing'
	resp = card_transaction.authManual
	err = card_transaction.errors_in_transaction
	if err
	  message = 'processing error: '
	  flash[:error] =  message + err
	  error message + err
	  redirect_to :controller => :reservation, :action => :show, :reservation_id => card_transaction.reservation.id and return
	end
	debug 'completed authManual'
      end
      if resp.class == Faraday::Response && resp.success?
	debug 'comm status success'
	# communication was successful
	if card_transaction.approved?
	  debug 'transaction approved'
	  # record payment
	  # store payment details
	  # ref no etc are in the card_transaction
	  # debug "account is #{card_transaction.account}"
	  creditcard_name = Creditcard.card_type(card_transaction.account[1].chr)
	  # debug "creditcard name is #{creditcard_name}"
	  creditcard_id = Creditcard.find_or_create_by_name(creditcard_name).id
	  # debug "creditcard_id is #{creditcard_id}"
	  memo = card_transaction.card_present?
	  if card_transaction.process_mode == CardTransaction::TermCard 
	    memo = 'card present, ' 
	  else
	    memo = 'card not present, '
	  end
	  p = Payment.create(:reservation_id => card_transaction.reservation_id,
			     :credit_card_no => '****' + card_transaction.account[-4..-1],
			     :creditcard_id => creditcard_id,
			     :amount => card_transaction.amount,
			     :cc_expire => card_transaction.expiry,
			     :memo => memo + "retref #{card_transaction.retref}") 
	  card_transaction.update_attributes :payment_id => p.id
	else
	  debug "Transaction not approved: #{card_transaction.resptext} (code #{card_transaction.respcode[1..2]})"
	  flash[:error] = "Transaction not approved: #{card_transaction.resptext} (code #{card_transaction.respcode[1..2]})"
	end
      else
        err = card_transaction.errors_in_transaction
	message = 'communication error: '
	flash[:error] =  message + err
	error message + err
	if card_transaction.process_mode == CardTransaction::TokenRemote
	  redirect_to :controller => :remote, :action => :payment and return
	else
	  redirect_to :controller => :reservation, :action => :show, :reservation_id => card_transaction.reservation.id and return
	end
        handle_other_error card_transaction
      end
    end
    redirect_to(:controller => 'reservation', :action => 'show', 
                :reservation_id => card_transaction.reservation_id) and return
  end

  # PUT /card_transactions/1
  # PUT /card_transactions/1.xml
  def update
    @card_transaction = CardTransaction.find(params[:id])
    respond_to do |format|
      if @card_transaction.update_attributes(params[:card_transaction])
        format.html { redirect_to(@card_transaction, :notice => 'CardTransaction was successfully updated.') }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @card_transaction.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /card_transactions/1
  # DELETE /card_transactions/1.xml
  def destroy
    @card_transaction = CardTransaction.find(params[:id])
    @card_transaction.destroy

    respond_to do |format|
      format.html { redirect_to(card_transactions_url) }
      format.xml  { head :ok }
    end
  end
  
  private
  
  def error_resp(resp)
    message = ""
    case resp.class
    when Faraday::Response
      JSON.parse(resp).each {|key,val| message << " #{key}: #{val}"}
    when FalseClass
      message = 'processing error: '
      flash[:error] =  message
      error message
    else
      # communication failure details
      message = 'communication or configuration error'
      flash[:error] =  message
      error message 
    end
    message
  end

  def errors_in_transaction(trans)
    if trans.errors.empty?
      debug 'no errors'
      return false 
    else
      debug 'processing error'
      message = 'Processing error: '
      trans.errors.each{|attr,msg| message += "#{attr} - #{msg}\n" }
      flash[:error] =  message
      return true
    end
  end

  def handle_processing_error(trans)
    message = 'processing error: '
    trans.errors.each{|attr,msg| message += "#{attr} - #{msg} \n" }
    flash[:error] =  message
    error message
    @success = false
  end

  def handle_other_error(trans)
    # communication failure details
    message = ''
    trans.errors.each{|attr,msg| message += "#{attr} - #{msg}\n" }
    if message.empty?
      err = error_resp(resp.body)
      flash[:error] =  "communication error: #{err}"
      error "communication error: #{err}"
    else
      flash[:error] =  message
      error message 
    end
    @success = false
  end

end
