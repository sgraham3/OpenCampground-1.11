class PaymentsController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login

  # GET /payments
  def index
    @page_title = 'Payments by Reservation'
    if params[:page]
      page = params[:page]
      session[:page] = page
    else
      page = session[:page]
    end
    @payments = Payment.paginate(:page => page, :per_page => @option.disp_rows - 3, :order => "reservation_id desc, created_at")
  end

  # GET /payments/1/edit
  def edit
    @payment = Payment.find(params[:id].to_i)
    @page_title = "Edit Payment #{@payment.id} for Reservation #{@payment.reservation_id}"
  end

  # PUT /payments/1
  def update
    @payment = Payment.find(params[:id].to_i)

    if @payment.update_attributes(params[:payment])
      flash[:notice] = 'Payment updated'
      Reservation.find(@payment.reservation_id).add_log("payment #{@payment.id} updated")
      redirect_to(payments_url)
    else
      flash[:error] = 'Payment update failed'
      render :action => "edit"
    end
  end

  # DELETE /payments/1
  def destroy
    payment = Payment.find(params[:id].to_i)
    ct = CardTransaction.find_by_payment_id(payment.id)
    if ct
      trans = CardTransaction.new(:account => ct.account, :reservation_id => ct.reservation_id, :retref => ct.retref, :amount => ct.amount)
      stat = trans.void_refund
      if stat
	if trans['respstat'] == 'A'
	  flash[:notice] = "Credit card transaction for reservation #{ct.reservation_id} cancelled"
	  # keep a record of the void
	  trans.save
	  # success 
	  payment.destroy
	else
	  flash[:error] = "credit card transaction not canceled: #{trans['resptext']}(#{trans['respcode']})"
	  error "credit card transaction not canceled: #{trans['resptext']}(#{trans['respcode']})"
	  redirect_to(payments_url) and return
	end
      else
	# communication failure details
	message = ''
	trans.errors.each{|attr,msg| message += "#{attr} - #{msg}\n" }
	if message.empty?
	  flash[:error] =  "communication error"
	  error "communication error"
	else
	  flash[:error] =  "communication error, credit card transaction not canceled: #{message}"
	  error "communication error, credit card transaction not canceled: #{message }"
	end
	redirect_to(payments_url) and return
      end
    else
      payment.destroy
    end
    begin
      Reservation.find(payment.reservation_id).add_log("payment #{payment.id} cancelled")
    rescue
    end
    redirect_to(payments_url)
  end
end
