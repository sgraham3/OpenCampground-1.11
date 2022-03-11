class RemoteController < ApplicationController
  include MyLib
  before_filter :check_for_remote
  before_filter :check_dates, :only => [:find_space, :update_dates, :change_space]
  before_filter :cleanup_abandoned, :only => [:index, :change_dates, :change_space]
  in_place_edit_for :reservation, :adults
  in_place_edit_for :reservation, :pets
  in_place_edit_for :reservation, :kids
  in_place_edit_for :reservation, :length
  in_place_edit_for :reservation, :slides
  in_place_edit_for :reservation, :rig_age
  in_place_edit_for :reservation, :special_request
  in_place_edit_for :reservation, :rigtype_id

  def index
    @page_title = I18n.t('titles.new_res')
    debug 'In remote index'
    session[:remote] = true
    session[:controller] = :remote
    session[:action] = :index
    ####################################################
    # new reservation.  Just make available all of
    # the fields needed for a reservation
    ####################################################
    flash.now[:error] = params[:flash] if params[:flash]
    begin
      @prompt = Prompt.find_by_display_and_locale!('index', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('index', 'en')
    end
    if session[:reservation_id]
      begin
        @reservation = Reservation.find session[:reservation_id].to_i
	debug "loaded reservation #{session[:reservation_id]} from session"
      rescue
        # reservation in session is not available
	# error 'Could not find reservation that is in session'
	@reservation = Reservation.new
	@reservation.startdate = currentDate
	@reservation.enddate = @reservation.startdate + 1
	session[:reservation_id] = nil
      end
    else
      @reservation = Reservation.new
      @reservation.startdate = currentDate
      @reservation.enddate = @reservation.startdate + 1
      session[:reservation_id] = nil
    end
    unless Campground.open?(@reservation.startdate, @reservation.enddate)
      @reservation.startdate = Campground.next_open
      @reservation.enddate = @reservation.startdate + 1
    end
    @reservation.startdate = Blackout.available(@reservation.startdate, @reservation.enddate)
    @reservation.enddate = @reservation.startdate + 1
    if @option.use_reserve_by_wk
      y,w,d = Date::jd_to_commercial(Date::civil_to_jd(@reservation.startdate.year,
                                                       @reservation.startdate.month,
                                                       @reservation.startdate.day))
      session[:count] = 0
      session[:number] = w
      session[:year] = y
    end
    session[:startdate] = @reservation.startdate
    session[:enddate] = @reservation.enddate
    @seasonal_ok = false
    session[:day] = @reservation.startdate.day.to_s
    session[:month] = @reservation.startdate.month.to_s
    session[:year] = @reservation.startdate.year.to_s
    if @option.show_remote_available?
      @count = Space.available( @reservation.startdate, @reservation.enddate, 0).size
      debug @count.to_s + ' sites available'
    else
      @count = 0
    end
    @extras = Extra.for_remote
  end

  def payment
    @reservation = get_reservation
    if @option.require_gateway? || @option.allow_gateway?
      debug 'gateway used'
      @deposit = @reservation.deposit_amount
      @integration = Integration.first
      begin
	@gateway = @integration.name
      rescue
	debug 'in rescue, @gateway is None'
	error 'configuration error.  Gateway not set up'
	@gateway = 'None'
	redirect_to :action => :confirmation and return
      end
    else
      debug 'no gateway used, @gateway is none'
      @gateway = 'None'
      redirect_to :action => :confirmation and return
    end
    name,d1,d2 = @gateway.partition('_')
    name += '-a' if @option.allow_gateway?
    name += '-payment'
    debug "prompt name is #{name}"
    begin
      @prompt = Prompt.find_by_display_and_locale!(name, I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale(name, 'en')
    end
    # debug @prompt.inspect
    debug '@gateway is ' + @gateway
  end

  def abandon_remote
    res = Reservation.find params[:reservation_id]
    if res.confirm?
      # do not destroy
    else
      res.destroy
    end
  rescue => err
    info err.to_s
  ensure
    redirect_to :controller => :remote, :action => :finished
  end

  def ipn
    # Instant Payment Notification processing from PayPal
    Integration.first.handle_paypal(request, params)
    render :nothing => true
  end

  def wait_for_confirm
    info 'wait for confirm'
    @integration = Integration.first
    begin
      case @integration.name
      when 'PayPal'
	if params[:invoice]
	  info 'got invoice ' + params[:invoice]
	  res_id = params[:invoice].to_i
	  @reservation = Reservation.find res_id
	  @reservation.update_attributes :confirm => @integration.handle_response(request, params)
	elsif params[:id]
	  info 'got id ' + params[:id]
	  res_id = params[:id].to_i
	  @reservation = Reservation.find res_id
	else
	  # now what?
	  info 'did not get id or invoice'
	  # just fall through for now
	end
      when 'FirstDataE4'
	if params[:x_invoice]
	  res_id = params[:x_invoice].to_i
	  @reservation = Reservation.find res_id
	  @reservation.update_attributes :confirm => @integration.handle_response(request, params)
	else
	  res_id = session[:reservation_id]
	  @reservation = Reservation.find res_id
	end
      end
    rescue ActiveRecord::RecordNotFound
      error "reservation #{res_id}"
      @message = 'Error--unable to find your transaction! Please contact us directly.'
      render :action => 'payment_error' and return
    end
    if defined?(@reservation) && @reservation.confirm?
      info 'going to confirmation'
      redirect_to :action => :confirmation and return
    end
    begin
      @prompt = Prompt.find_by_display_and_locale!('wait_for_confirm', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('wait_for_confirm', 'en')
    end
  end

  def confirmation
    @page_title = I18n.t('titles.ConfirmRes')
    @reservation = get_reservation
    @reservation.add_log("remote reservation made")
    @reservation.camper.active
    # check camper in if date <= today
    if @reservation.startdate <= currentDate && @option.auto_checkin_remote? && !@reservation.gateway_transaction.empty?
      debug "doing automatic checkin"
      @reservation.checked_in = true
      @reservation.add_log("automatic checkin")
    end
    @payments = Payment.find_all_by_reservation_id @reservation.id
    recalculate_charges
    @deposit = @reservation.deposit_amount
    begin
      @prompt = Prompt.find_by_display_and_locale!('confirmation', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('confirmation', 'en')
    end

    # send confirmation emails
    @reservation.save!
    if @option.use_confirm_email?
      if validEmail(@reservation.camper.email)
	debug 'send confirmation emails'
	@email = Email.first
	begin
	  email = ResMailer.deliver_remote_reservation_received(@reservation, @email, @option)
	rescue => err
	  error err.to_s
	end
      end
    end
    render :action => :show
  rescue ActiveRecord::RecordNotFound
    error "could not find reservation #{session[:reservation_id]}"
    reset_session
    flash[:error] = 'Error in process, starting over'
    redirect_to :controller => :remote, :action => :index and return
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in process, starting over'
    redirect_to :controller => :remote, :action => :index and return
  end

  def confirm_without_payment
    @page_title = I18n.t('titles.ConfirmRes')
    begin
      @prompt = Prompt.find_by_display_and_locale!('confirmation', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('confirmation', 'en')
    end
    @reservation = get_reservation
    @reservation.add_log("remote reservation made")
    @reservation.camper.active
    @reservation.update_attributes :confirm => true, :unconfirmed_remote => true
    @payments = Payment.find_all_by_reservation_id @reservation.id
    recalculate_charges
    @reservation.save!
    # send confirmation emails
    if @option.use_confirm_email?
      if validEmail(@reservation.camper.email)
	debug 'send confirmation emails'
	@email = Email.first
	begin
	  email = ResMailer.deliver_remote_reservation_received(@reservation, @email, @option)
	rescue => err
	  error 'problem in mail delivery ' + err.to_s
	end
      end
    end
    render :action => :show
  rescue ActiveRecord::RecordNotFound
    error "could not find reservation #{session[:reservation_id]}"
    reset_session
    flash[:error] = 'Error in process, starting over'
    redirect_to :controller => :remote, :action => :index and return
  rescue => err
    error 'other: ' + err.to_s
    flash.now[:error] = 'Error in reservation process'
    render :action => :show
  end

  def space_selected
    @page_title = I18n.t('titles.ReviewRes')
    ####################################################
    # the space has been selected, now compute the total
    # charges and fetch info for display and completion
    ####################################################
    # debug "locale is #{I18n.locale}"
    begin
      @prompt = Prompt.find_by_display_and_locale!('show', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('show', 'en')
    end
    @reservation = get_reservation

    # if we are changing dates we will not have a space in params
    if params[:space_id]
      @space = Space.find(params[:space_id].to_i)
      @reservation.space = @space
    end
    spaces = Space.confirm_available(@reservation.id, @reservation.space_id, @reservation.startdate, @reservation.enddate)
    debug "#{spaces.size} spaces in conflict"
    if spaces.size > 0
      error 'space conflict'
      reset_session
      # flash[:error] = 'Conflicting reservation for space, select again'
      @reservation.destroy
      redirect_to(:action => :index, :flash => 'Conflicting reservation for space, select again') and return
    end
    @reservation.save
    ####################################################
    # calculate charges
    ####################################################
    if @option.require_gateway? || @option.allow_gateway?
      @formatted_total = number_2_currency(@reservation.total)
      begin
	@gateway = Integration.first.name
      rescue
        @gateway = 'None'
      end
    else
      @gateway = 'None'
    end
    recalculate_charges
    @deposit = @reservation.deposit_amount
    debug "@deposit isa #{@deposit.class.to_s}"
    debug "@deposit: #{@deposit.inspect}"
    # session[:reservation_id] = @reservation.id
    render :action => :show
  end

  def find_space
    @page_title = I18n.t('titles.SelSpace')
    ####################################################
    # given the parameters specified find all spaces not
    # already reserved that fit the spec and supply data
    # for presentation
    # We will save the data selected the first time
    # in the session to be used when we advance from
    # page to page.
    ####################################################
    
    begin
      @prompt = Prompt.find_by_display_and_locale!('find_space', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('find_space', 'en')
    end
    if params[:reservation]
      @reservation = Reservation.new(params[:reservation])
      debug 'New reservation'
      debug "sitetype #{@reservation.sitetype_id} initially from reservation" if @reservation.sitetype_id
      @reservation.startdate = @date_start
      @reservation.enddate = @date_end
      @reservation.unconfirmed_remote = true
    else 
      @reservation = get_reservation
    end
    if @reservation.startdate < currentDate
      flash.now[:error] = I18n.t('general.Flash.WrongStart')
      @reservation.startdate = currentDate
      @reservation.enddate = @reservation.startdate + 1 if @reservation.enddate <= @reservation.startdate
    end
    unless Campground.open?(@reservation.startdate, @reservation.enddate)
      debug 'Campground closed'
      reset_session
      flash[:error] = I18n.t('reservation.Flash.SpaceUnavailable') +
		      '<br />' +
		      I18n.t('reservation.Flash.ClosedDates',
			  :closed => DateFmt.format_date(@option.closed_start),
			  :open => DateFmt.format_date(@option.closed_end))
      redirect_to :action => :index and return
    end
    debug 'Campground open'
    if @reservation.discount_id == nil
      @reservation.discount_id = 1
    end
    @reservation.save!
    @reservation.reload
    session[:reservation_id] = @reservation.id
    if params[:extra]
      extras = Extra.active
      extras.each do |e|
	ex_key = "extra#{e.id}".to_sym
	ct_key = "count#{e.id}".to_sym
	
	debug "looking for #{e.id} with keys #{ex_key} and #{ct_key}"
	#if params[:extra].key?("extra#{ex.id}".to_sym) && (params[:extra]["extra#{ex.id}".to_sym] != '0')
	if (params[:extra].key?(ex_key) && (params[:extra][ex_key] != '0')) 
	  debug "found extra #{e.id} and it is true"
	  @reservation.extras << e
	  debug "added extra #{e.id}"
	  ec=ExtraCharge.first(:conditions => [ "extra_id = ? and reservation_id = ?", 
						e.id, @reservation.id] )
	  if e.extra_type == Extra::COUNTED
	    debug "extra count is #{params[:extra][ct_key]}"
	    ec.save_charges((params[:extra][ct_key]).to_i)
	    debug "counted value #{e.id}, value is #{ec.number}"
	  else
	    ec.save_charges( 0 )
	  end
	else
	  debug "not found extra #{e.id}"
	end
      end
    end
    @spaces = remote_for_display(@reservation)
    @map =  '/map/' + @option.remote_map if @option.remote_map && !@option.remote_map.empty? && @option.use_remote_map
    unless @spaces.size > 0
      reset_session
      flash[:error] = "No spaces are available that meet your criteria.  Please change dates or site type and try again"
      redirect_to :action => :index and return
    end
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in find_space. Start over'
    redirect_to :action => :index and return
  end

  def customCompleteRes
    @reservation = get_reservation
    @reservation.confirm = true
    @reservation.deposit = request["amount"]

    if @reservation.save
			flash[:notice] = I18n.t('reservation.Flash.UpdateSuccess',
															:reservation_id => @reservation.id,
						:camper_name => @reservation.camper.full_name)
			if @option.use_confirm_email? && (skip_email == false)
	if validEmail(@reservation.camper.email)
		@email = Email.first
		begin
			email = ResMailer.deliver_reservation_confirmation(@reservation, @email, @option)
			flash[:notice] += "\r" + I18n.t('reservation.Flash.ConfSent')
		rescue => err
			flash[:error] = I18n.t('reservation.Flash.ConfErr')
			error err.to_s
		end
	else
		flash[:notice] += "\r" + I18n.t('reservation.Flash.ConfNotSent')
	end
			end
		else
			raise
		end
		session[:group_id] = nil

    # create row in payment table
    @integration = Integration.first
		debug "creating new payment"
    new_payment = true
    @payment = Payment.create! :reservation_id => request["reservation_id"].to_i
    @payment.reload
    session[:payment_id] = @payment.id
    debug "session payment created and defined as #{session[:payment_id]}"

    # update payment amount
    @payment.amount = request["amount"]
    @payment.save
	end

  def change_dates
    @page_title = I18n.t('titles.ChangeDates')
    @reservation = get_reservation
    @extras = Extra.for_remote
    @seasonal_ok = false
    @available_str = @reservation.get_possible_dates(true)
    session[:early_date] = @reservation.early_date
    session[:late_date] = @reservation.late_date
    session[:startdate] = @reservation.startdate
    session[:enddate] = @reservation.enddate
    session[:day] = @reservation.startdate.day.to_s
    session[:month] = @reservation.startdate.month.to_s
    session[:year] = @reservation.startdate.year.to_s
    session[:canx_action] = session[:action]
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in change dates. Start over'
    redirect_to :action => :index and return
  end

  def select_change
    ####################################################
    # get reservation info for selecting new space
    ####################################################
    @page_title = I18n.t('titles.DateSel')

    @reservation = get_reservation
    @seasonal_ok = false
    @count  = Space.available( @reservation.startdate, @reservation.enddate, @reservation.sitetype_id.to_i).size if @option.show_remote_available?
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in select_change. Start over'
    redirect_to :action => :index and return
  end
  
  def change_space
    @page_title = I18n.t('titles.ChangeSpace')
    ####################################################
    # given the parameters specified find all spaces not
    # already reserved that fit the spec and supply data
    # for presentation
    ####################################################
    
    @reservation = get_reservation
    # these dates come from application_controller
    session[:startdate] = @date_start
    session[:enddate] = @date_end
    session[:desired_type] = (params[:reservation][:sitetype_id]).to_i
    debug "desired type = #{session[:desired_type]}"
    session[:day] = @reservation.startdate.day.to_s
    session[:month] = @reservation.startdate.month.to_s
    session[:year] = @reservation.startdate.year.to_s
    @spaces = remote_for_display(@reservation)
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in change_space. Start over'
    redirect_to :action => :index and return
  end
  
  def space_changed
    ####################################################
    # update the reservation
    ####################################################
    
    @reservation = get_reservation
    @reservation.space_id = params[:space_id].to_i
    @reservation.startdate = session[:startdate]
    @reservation.enddate = session[:enddate]
    @reservation.sitetype_id = session[:desired_type]
    spaces = Space.confirm_available(@reservation.id, @reservation.space_id, @reservation.startdate, @reservation.enddate)
    debug "#{spaces.size} spaces in conflict"
    if spaces.size > 0
      error 'space conflict'
      reset_session
      flash[:error] = "Conflicting reservation for space, select again"
      redirect_to :action => :select_change and return
    end
    @reservation.save
    ####################################################
    # calculate charges
    ####################################################
    redirect_to :action => :space_selected, :reservation_id => @reservation.id and return
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in space_changed. Start over ' + err.to_s
    redirect_to :action => :index and return
  end
  
  def finished
    reset_session
  rescue => err
    error err.to_s
  ensure
    if @option.home.blank?
      render :inline => '<h1>Reservation completed.  Please close this window.</h1>'
    else
      redirect_to @option.home and return
    end
  end

  ####################################################
  # methods called from observers
  ####################################################

  def update_recommend
    if params[:recommender_id]
      begin
	@reservation = Reservation.find session[:reservation_id].to_i
	debug "loaded reservation #{session[:reservation_id]} from session"
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      @reservation.update_attribute :recommender_id, params[:recommender_id].to_i
    end
    render(:nothing => true)
  end

  def update_rigtype
    if params[:rigtype_id]
      begin
	@reservation = Reservation.find session[:reservation_id].to_i
	  debug "loaded reservation #{session[:reservation_id]} from session"
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      @reservation.update_attribute :rigtype_id, params[:rigtype_id].to_i
    end
    render(:nothing => true)
  end

  def update_discount
    if params[:discount_id]
      begin
	@reservation = Reservation.find session[:reservation_id].to_i
	debug "loaded reservation #{session[:reservation_id]} from session"
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      @reservation.update_attribute :discount_id, params[:discount_id].to_i
      recalculate_charges
      render :update do |page|
	page[:charges].reload
      end
    else
      render(:nothing => true)
    end
  end

  def update_counted
    if params[:extra_id]
      extra_id = params[:extra_id].to_i
      debug "extra_id is #{extra_id}"
      cnt = "count_#{extra_id}".to_sym
      render :update do |page|
	if params[:number].to_i == 1
	  # debug "show"
	  page[cnt].show
	else
	  # debug "hide"
	  page[cnt].hide
	end
      end
    else
      render(:nothing => true)
    end
  end

  def update_extras
    if params[:extra]
      debug "in update_extras"
      begin
	@reservation = Reservation.find session[:reservation_id].to_i
	debug "loaded reservation #{session[:reservation_id]} from session"
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      extra = Extra.find params[:extra].to_i
      debug "extra_type is #{extra.extra_type.to_s}"
      case extra.extra_type
      when Extra::MEASURED
	debug 'extra is MEASURED'
      when Extra::OCCASIONAL, Extra::COUNTED
	debug 'extra COUNTED or OCCASIONAL'
	if (ec = ExtraCharge.find_by_extra_id_and_reservation_id(extra.id, @reservation.id))
	  # extra charge currently is applied so we have dropped it
	  ec.destroy
	  hide = true
	  debug "destroyed entity"
	else
	  # extra charge is not currently applied
	  # extra was added, apply it
	  # start out with a value of 1
	  ec = ExtraCharge.create :reservation_id => @reservation.id, 
				  :extra_id => extra.id,
				  :number => 1
	  hide = false
	  debug "created new entity"
	end
      else
	debug 'extra STANDARD'
	if (ec = ExtraCharge.find_by_extra_id_and_reservation_id(extra.id, @reservation.id))
	  # extra charge currently is applied so we have dropped it
	  ec.destroy
	  hide = true
	  debug "destroyed entity, hiding"
	else
	  # extra charge is not currently applied
	  # extra was added, apply it
	  ec = ExtraCharge.create :reservation_id => @reservation.id,
				  :extra_id => extra.id
	  hide = false
	  debug "created new entity, unhiding"
	end
      end
      @skip_render = true
      recalculate_charges
      debug "recalculated charges"
      debug "saved reservation"
      cnt = "count_#{extra.id}".to_sym
      ext = "extra#{extra.id}".to_sym
      render :update do |page|
	case extra.extra_type
	when Extra::COUNTED, Extra::OCCASIONAL
	  # debug "counted"
	  if hide
	    # debug "hide"
	    page[cnt].hide
	  else
	    # debug "show"
	    page[cnt].show
	  end
	when Extra::MEASURED
	  debug "measured"
	end
	# debug "reload charges"
	page[:charges].reload
	if @option.require_gateway? || @option.allow_gateway?
	  @integration = Integration.first
	  if @integration
            case @integration.name
            when "PayPal"
	      debug 'Paypal: nothing to do'
	      # debug "#{dep[:_item_name]},#{ dep[:charge]},#{ dep[:custom]},#{ dep[:tax]}"
            when "FirstDataE4"
              page[:firstdatae4].reload
            when "CardConnect"
              page[:cardconnect].reload
            else
              error "#update_extras: integration not handled #{@integration.name}"
              flash.now[:error] = 'Error in processing payment'
            end
          end
          # debug "done with update_extras"
        end
      end
    else
      render(:nothing => true)
    end
  end

  def update_count
    if params[:extra_id] 
      extra_id = params[:extra_id].to_i
      begin
	@reservation = Reservation.find session[:reservation_id].to_i
	debug "loaded reservation #{session[:reservation_id]} from session"
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      ec = ExtraCharge.first(:conditions => ["EXTRA_ID = ? and RESERVATION_ID = ?",
					    extra_id, @reservation.id])
      debug "updating count to #{params[:number].to_i}"
      ec.update_attributes :number => params[:number].to_i
    
      @skip_render = true
      recalculate_charges
      debug "recalculated charges"
      # render :partial => 'space_summary', :layout => false
      # debug "rendered space_summary"
      render :update do |page|
	# debug "reload charges"
        page[:charges].reload
        if @option.require_gateway? || @option.allow_gateway?
          @integration = Integration.first
          if @integration
            case @integration.name
            when "PayPal"
	      debug 'Paypal: nothing to do'
            when "FirstDataE4"
              page[:firstdatae4].reload
            when "CardConnect"
              page[:cardconnect].reload
            else
              error "#update_count integration not handled #{@integration.name}"
              flash.now[:error] = 'Error in processing payment'
            end
          end
        end
      end
    else
      render(:nothing => true)
    end
  end

  def to_pp
    # make sure the reservation still exists before we send out
    reservation = Reservation.find params[:id].to_i
    integration = Integration.find_by_name 'PayPal'
    @encrypted_basic = integration.paypal_fetch_decrypted(reservation, get_server_path)
    @action_url = ENV['RAILS_ENV'] == "production" ? integration.pp_url : "https://www.sandbox.paypal.com/cgi-bin/webscr" 
    render :layout => false
  rescue
    info 'reservation not found on PayPal attempted payment'
    flash[:error] = "The reservation has been canceled or it has timed out from inactivity.\nThe reservation process will Start Over."
    redirect_to :action => :index
  end
  

  private
  ####################################################
  # methods that cannot be called externally
  ####################################################
  def remote_for_display(res)
    @season = Season.find_by_date(res.startdate)
    debug "season is #{@season.id}"
    spaces = Array.new
    if session[:desired_type]
      dt = session[:desired_type]
    else
      dt = res.sitetype_id
    end
    debug "sitetype_id is #{dt}"
    av_spaces = Space.available_remote(res.startdate,
				     res.enddate,
				     dt.to_i) 
    av_spaces.each do |sp|
      unless Rate.find_current_rate(@season.id, sp.price_id).no_rate?(res.enddate - res.startdate)
	debug "pushing #{sp.name}"
	spaces.push sp
      else
	debug "skipping #{sp.name}, no rate"
      end
    end
    debug "found #{spaces.size} spaces"
    return spaces
  end

  def check_for_remote
    debug 'check_for remote:'
    unless @option.use_remote_reservations?
      redirect_to '/404.html' and return
    end
  end

  def recalculate_charges
    @reservation = get_reservation unless defined?(@reservation)
    # calculate charges
    Charges.new(@reservation.startdate,
		@reservation.enddate,
		@reservation.space.price.id,
		@reservation.discount_id,
		@reservation.id,
		@reservation.seasonal)
    @charges = Charge.stay(@reservation.id)
    total = 0.0
    @charges.each { |c| total += c.amount - c.discount }
    total += calculate_extras(@reservation.id)
    tax_amount = Taxrate.calculate_tax(@reservation.id, @option)
    @reservation.total = total
    @reservation.tax_amount = tax_amount
    @season_cnt = Season.count(:conditions => ["active = ?", true])
    @tax_records = Tax.find_all_by_reservation_id(@reservation.id)
    begin
      unless @reservation.save
	flash.now[:error] = 'Problem updating reservation'
      end
    rescue ActiveRecord::StaleObjectError => err
      error err.to_s
      locking_error(@reservation)
    end
    if @option.require_gateway? || @option.allow_gateway?
      @integration = Integration.first
      if @integration.name == "FirstDataE4"
	@action_url = ENV['RAILS_ENV'] == "production" ? @integration.fd_url : "https://demo.globalgatewaye4.firstdata.com/pay"
      end
    end
  end

  def get_reservation
    if params[:reservation_id]
      reservation = Reservation.find params[:reservation_id]
      debug 'loaded reservation from params'
    elsif session[:reservation_id]
      begin
	reservation = Reservation.find session[:reservation_id].to_i
	debug "loaded reservation #{session[:reservation_id]} from session"
      rescue ActiveRecord::RecordNotFound
	error "could not find reservation #{session[:reservation_id]}"
	reset_session
	flash[:error] = 'Error in process, reservation has been deleted. Starting over'
	redirect_to :controller => :remote, :action => :index and return
      end
    else
      error 'no reservation id in session'
      reset_session
      flash[:error] = 'Error in process, starting over'
      redirect_to :controller => :remote, :action => :index and return
    end
    return reservation
  end

  def get_server_path
    "http://#{request.host.to_s}:#{request.port.to_s}"
  end

end
