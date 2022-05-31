class ReservationController < ApplicationController
	include MyLib
	include CalculationHelper
	include ReservationHelper
	before_filter :login_from_cookie
	# before_filter :check_login
	before_filter :check_dates, :only => [:find_space, :update_dates, :change_space, :express_2]
	before_filter :set_defaults
	before_filter :cleanup_abandoned, :only => [:new, :express, :select_change, :change_space]
	before_filter :set_current_user, :except => [:getNextData, :getPreviousData]
	in_place_edit_for :reservation, :adults
	in_place_edit_for :reservation, :pets
	in_place_edit_for :reservation, :kids
	in_place_edit_for :reservation, :length
	in_place_edit_for :reservation, :slides
	in_place_edit_for :reservation, :rig_age
	in_place_edit_for :reservation, :special_request
	in_place_edit_for :reservation, :rigtype_id
	in_place_edit_for :reservation, :vehicle_state
	in_place_edit_for :reservation, :vehicle_license
	in_place_edit_for :reservation, :vehicle_state_2
	in_place_edit_for :reservation, :vehicle_license_2

	def set_defaults
		if params[:controller] == 'reservation'
			session[:remote] = nil
		end
		@skip_render = false
	end

	def index
		####################################################
		# we should never get here except by error
		####################################################
		debug "entered from #{session[:controller]} #{session[:action]}"
		redirect_to :action => 'list'
	end

	def new
		@page_title = I18n.t('titles.new_res')
		####################################################
		# new reservation.  Just make available all of
		# the fields needed for a reservation
		####################################################

		session[:payment_id] = nil if session[:payment_id] 
		if params[:stage] == 'new'
			@reservation = Reservation.new
			@reservation.startdate = currentDate
			@reservation.enddate = @reservation.startdate + 1
			session[:reservation_id] = nil
			session[:payment_id] = nil
			session[:desired_type] = 0
		else
			begin
				@reservation = Reservation.find session[:reservation_id].to_i
				info "loaded reservation #{session[:reservation_id]} from session"
			rescue
				@reservation = Reservation.new
				@reservation.startdate = currentDate
				@reservation.enddate = @reservation.startdate + 1
			end
		end
		debug "checking for open #{@reservation.startdate} to #{@reservation.enddate}"
		unless Campground.open?(@reservation.startdate, @reservation.enddate)
			debug 'not open'
			flash.now[:warning] = I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(@option.closed_start), :open => DateFmt.format_date(@option.closed_end))
			@reservation.startdate = Campground.next_open
			@reservation.enddate = @reservation.startdate + 1
		end
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
		@seasonal_ok = @option.use_seasonal
		@storage_ok = @option.use_storage
		# we will not save the res because if we will 
		# need it later it is already saved
		@count  = Space.available( @reservation.startdate, @reservation.enddate, session[:desired_type]).size if @option.show_available?
		@extras = Extra.active
		session[:canx_action] = 'abandon'
		session[:change] = 'false'
	end

	def express
		@page_title = I18n.t('titles.express')
		####################################################
		# new express reservation.  Just make available all of
		# the fields needed for a reservation
		####################################################

		session[:payment_id] = nil
		session[:reservation_id] = nil
		@reservation = Reservation.new
		@reservation.startdate = currentDate
		@reservation.enddate = @reservation.startdate + 1
		unless Campground.open?(@reservation.startdate, @reservation.enddate)
			flash.now[:warning] = I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(@option.closed_start), :open => DateFmt.format_date(@option.closed_end))
			@reservation.startdate = Campground.next_open
			@reservation.enddate = @reservation.startdate + 1
		end
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
		@storage_ok = false
		# we will not save the res because if we will 
		# need it later it is already saved
		@spaces  = Space.all()
		@count = @spaces.size
		@extras = Extra.active
		session[:canx_action] = 'abandon'
		session[:change] = 'false'
	end

	def express_2
		unless params[:space] && params[:reservation]
			redirect_to :action => :express and return
		end
		# first time through
		@reservation = Reservation.new(params[:reservation])
		@reservation.startdate = @date_start
		@reservation.enddate = @date_end
		if params[:is_remote] == "false"
			@reservation.is_remote = 0
			@reservation.unconfirmed_remote = 0
		else
			@reservation.is_remote = 1
			@reservation.unconfirmed_remote = 1
		end

		unless Campground.open?(@reservation.startdate, @reservation.enddate)
			flash[:error] = I18n.t('reservation.Flash.SpaceUnavailable') +
					"<br />" +
					I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(@option.closed_start), :open => DateFmt.format_date(@option.closed_end))
			redirect_to :action => :express and return
		end
		flash[:warning] = I18n.t('reservation.Flash.EarlyStart') if @reservation.startdate < currentDate
		@reservation.save!
		session[:reservation_id] = @reservation.id
		session[:startdate] = @reservation.startdate
		session[:enddate] = @reservation.enddate
		redirect_to :action => :space_selected, :space_id => params[:space][:space_id].to_i, :reservation_id => @reservation.id, :is_remote => params[:is_remote]
	end

	def confirm_res
		####################################################
		# save the camper in the reservation
		####################################################
		# this is usually called from camper so the parameters contain a camper id
		
		@reservation = get_reservation
		@payments = Payment.find_all_by_reservation_id @reservation.id
		@payment = Payment.new :reservation_id => @reservation.id
		session[:payment_id] = nil
		@page_title = I18n.t('titles.ConfirmResId', :reservation_id => @reservation.id)
		if params[:camper_id]
			@reservation.update_attribute(:camper_id,  params[:camper_id].to_i)
			@reservation.camper.active
		end
		@skip_render = true
		recalculate_charges
		@use_navigation = false
		@integration = Integration.first
		@variable_charge = VariableCharge.new if @option.use_variable_charge
		session[:current_action] = 'confirm_res'
		session[:canx_action] = 'abandon'
		session[:canx_controller] = 'reservation'
		session[:next_action] = session[:action]
		session[:camper_found] = 'confirm_res'
		session[:fini_action] = 'list'
		session[:change] = 'false'
		render :action => :show and return
		rescue => err
		error 'Reservation could not be updated(1). ' + err.to_s
		session[:reservation_id] = nil
		flash[:error] = I18n.t('reservation.Flash.UpdateFail')
		redirect_to :action => :new and return
	end

	def create
		####################################################
		# create and save a new reservation.
		####################################################
		@reservation = get_reservation
		create_res
		session[:reservation_id] = nil
		session[:payment_id] = nil
		redirect_to :action => :list and return
	rescue => err
		error 'Problem in Reservation.  Reservation is not complete!' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.UpdateFail')
		redirect_to :action => :show, :reservation_id => @reservation.id and return
	end

	def expand
		@page_title = I18n.t('titles.res_list')
		####################################################
		# List all reservations with groups expanded.  
		# Sort by the start date, group and space of the reservation
		####################################################
		session[:list] = 'expand'
		session[:reservation_id] = nil
		session[:next_controller] = nil
		session[:next_action] = nil

		if params[:page]
			page = params[:page]
			session[:page] = page
		else
			page = session[:page]
		end
		begin
			reservations = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", false, true, false],
							:include => ["camper", "space", "rigtype"],
							:order => @option.res_list_sort )
		rescue
			@option.update_attribute :res_list_sort, "unconfirmed_remote desc, startdate, group_id, spaces.position asc"
			reservations = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", false, true, false],
							:include => ["camper", "space", "rigtype"],
							:order => @option.res_list_sort )
		end
		@reservations = reservations.paginate(:page => page, :per_page => @option.disp_rows)
		return_here
		session[:reservation_id] = nil if session[:reservation_id] 
		session[:payment_id] = nil if session[:payment_id] 
		session[:current_action] = 'expand'
	end

	def sort_by_res
		@option.update_attribute get_sort.to_sym, "unconfirmed_remote desc, reservations.id asc"
		redirect_to :action => session[:list]
	end

	def sort_by_start
		@option.update_attribute get_sort.to_sym, "unconfirmed_remote desc, startdate, group_id, spaces.position asc"
		redirect_to :action => session[:list]
	end

	def sort_by_end
		@option.update_attribute get_sort.to_sym, "unconfirmed_remote desc, enddate, startdate, group_id, spaces.position asc"
		redirect_to :action => session[:list]
	end

	def sort_by_name
		@option.update_attribute get_sort.to_sym, "unconfirmed_remote desc, campers.last_name, startdate, group_id, spaces.position asc"
		redirect_to :action => session[:list]
	end

	def sort_by_space
		@option.update_attribute get_sort.to_sym, "unconfirmed_remote desc, spaces.position, startdate, group_id, campers.last_name asc"
		redirect_to :action => session[:list]
	end

	def list
		@page_title = I18n.t('titles.res_list')
		if session[:user_id]
			####################################################
			# List all reservations.  This is used
			# as the central focus of the application.  Sort
			# by the start date, group and space of the reservation
			####################################################
			session[:next_controller] = nil
			session[:next_action] = nil
			session[:reservation_id] = nil
			if (Space.first == nil)  # this is for startup with no spaces defined
				if @option.use_login? && session[:user_id] != nil
					if @user_login.admin
						redirect_to :controller => 'setup/index', :action => 'index'
					else
						redirect_to :controller => :admin, :action => :index
					end
				else
					redirect_to :controller => 'setup/index', :action => 'index'
				end
			else
				session[:list] = 'list'
				if params[:page]
					page = params[:page]
					session[:page] = page
				else
					page = session[:page]
				end
				begin
					res = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", false, true, false],
							:include => ["camper", "space", "rigtype"],
							:order => @option.res_list_sort )
				rescue
					@option.update_attribute :res_list_sort, "unconfirmed_remote desc, startdate, group_id, spaces.position asc"
					res = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", false, true, false],
										:include => ["camper", "space"],
										:order => @option.res_list_sort )
				end
				@saved_group = nil
				res = res.reject do |r|
					contract(r)
				end
				reservations = res.compact
				@reservation = Reservation.new
				@reservations = reservations.paginate(:page => page, :per_page => @option.disp_rows)
			end

			####################################################
			# return to here from a camper show
			####################################################
			return_here
			session[:reservation_id] = nil if session[:reservation_id] 
			session[:payment_id] = nil if session[:payment_id] 
			session[:current_action] = 'list'
		else
			redirect_to :controller => :login, :action => :login
		end
	end

	def change_dates
		session[:change] = 'true'
		@page_title = I18n.t('titles.ChangeDates')
		@reservation = get_reservation
		@extras = Extra.active
		@seasonal_ok = @reservation.check_seasonal
		@storage_ok = @reservation.check_storage
		debug "seasonal_ok = #{@seasonal_ok}, storage_ok = #{@storage_ok}"
		@available_str = @reservation.get_possible_dates
		session[:early_date] = @reservation.early_date
		session[:late_date] = @reservation.late_date
		session[:startdate] = @reservation.startdate
		session[:enddate] = @reservation.enddate
		session[:canx_action] = 'cancel_change'
		unless flash[:error] # coming back after an error
			session[:next_action] = session[:action]
		end
		debug 'Cancel action = ' + session[:canx_action]
		@use_navigation = false
		@change_action = 'date'
	rescue => err
		flash[:error]= 'Error handling reservation ' + err.to_s
		error '#change_dates Error handling reservation ' + err.to_s
		redirect_to :action => :list
	end

	def extend_stay
		# fetch reservation
		@reservation = get_reservation
		old_end = @reservation.enddate
		if params[:enddate]
			new_end = params[:enddate]
		else
			new_end = @reservation.enddate + 1.day
		end
		debug "changing enddate to #{new_end}"
		# check that there is no reservation precluding extension
		@reservation.enddate = new_end
		conflict = @reservation.conflicts?
		if conflict == false
			#empty so space is free, up the stay by one day
			@reservation.update_attribute :enddate, new_end
			@reservation.camper.active if @reservation.camper
			@reservation.add_log("end date changed from #{old_end} to #{new_end}")
			@skip_render = true
			recalculate_charges
		else
			flash[:error] = I18n.t('reservation.Flash.ExtendConflict',
															:space_name => @reservation.space.name,
						:enddate => @reservation.enddate,
						:conflict_id => conflict.id)
		end
	rescue => err
		error 'Unable to extend reservation ' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.ExtendFail')
	ensure
		redirect_to :action => :in_park
	end

	def recalculate_charges
		####################################################
		# recalculate the charges for this reservation using
		# the current rates.  We could be coming from checkin
		# or from show.
		####################################################
		debug 'recalculate_charges'
		if defined?(@reservation)
			session[:reservation_id] = @reservation.id
		else
			@reservation = get_reservation
		end
		# calculate charges
		Charges.new( @reservation.startdate,
		 @reservation.enddate,
		 @reservation.space.price.id, 
		 @reservation.discount.id,
		 @reservation.id,
		 @reservation.seasonal,
		 @reservation.storage)
		charges_for_display(@reservation)
		begin
			if @reservation.save
	flash[:notice] = I18n.t('reservation.Flash.UpdateSuccess',
													 :reservation_id => @reservation.id.to_s,
				 :camper_name => @reservation.camper.full_name) if @reservation.camper unless @skip_notice
			else
	flash[:error] = I18n.t('reservation.Flash.UpdateFail') unless @skip_notice
			end
		rescue ActiveRecord::StaleObjectError => err
			error 'Problem updating reservation' + err.to_s 
			flash[:error] = I18n.t('reservation.Flash.UpdateFail') unless @skip_notice
			locking_error(@reservation)
		rescue => err
			error 'Problem updating reservation' + err.to_s 
			flash[:error] = I18n.t('reservation.Flash.UpdateFail') unless @skip_notice
		end
		redirect_to :action => session[:current_action], :reservation_id => @reservation.id unless @skip_render
	end

	def update_camper
		####################################################
		# store the data from an change of camper for a reservation
		####################################################
		session[:change] = 'false'
		@reservation = get_reservation
		former_camper = @reservation.camper.full_name
		@reservation.camper_id = params[:camper_id].to_i
		begin
			if @reservation.save
	flash[:notice] = I18n.t('reservation.Flash.UpdateSuccess',
													 :reservation_id => @reservation.id,
				 :camper_name => @reservation.camper.full_name)
	@reservation.add_log("camper changed from #{former_camper}")
	if session[:camper_found]
		redirect_to :action => session[:camper_found] and return
	elsif @reservation.checked_in?
		redirect_to :action => 'in_park' and return
	else
		redirect_to :action => 'list' and return
	end
			else
	flash.now[:error] = I18n.t('reservation.Flash.UpdateFail')
	@page_title = I18n.t('titles.ChangeRes')
	@available_str = @reservation.get_possible_dates
	session[:early_date] = @reservation.early_date
	session[:late_date] = @reservation.late_date
	render :action => 'edit'
			end
		rescue ActiveRecord::StaleObjectError => err
			locking_error(@reservation)
			error 'Problem updating reservation' + err.to_s 
			flash.now[:error] = I18n.t('reservation.Flash.UpdateFail')
		rescue => err
			error 'Problem updating reservation' + err.to_s 
			flash.now[:error] = I18n.t('reservation.Flash.UpdateFail')
		end
	end

	def space_selected
		@page_title = I18n.t('titles.Review')
		####################################################
		# the space has been selected, now compute the total
		# charges and fetch info for display and completion
		####################################################

		@reservation = get_reservation
		@payments = Payment.find_all_by_reservation_id @reservation.id
		# if we are changing dates we will not have a space in params
		@reservation.space_id = params[:space_id].to_i if params[:space_id]
		check_length @reservation
		spaces = Space.confirm_available(@reservation.id, @reservation.space_id, @reservation.startdate, @reservation.enddate)
		# debug "#{spaces.size} spaces in conflict"
		if spaces.size > 0
			flash[:error] = I18n.t('reservation.Flash.Conflict')
			error 'space conflict'
			redirect_to :action => :new and return
		end
		@reservation.save!
		session[:next_controller] = 'reservation'
		session[:next_action] = 'confirm_res'
		session[:fini_action] = 'confirm_res'
		session[:current_action] = 'space_selected'
		session[:camper_found] = 'confirm_res'
		session[:change] = 'false'
		if @option.use_variable_charge && params[:variable_charge] && params[:variable_charge][:amount] != '0.0'
			new_variable_charge
		end
		@variable_charge = VariableCharge.new if @option.use_variable_charge
		####################################################
		# calculate charges
		####################################################
		Charges.new(@reservation.startdate,
		@reservation.enddate,
		@reservation.space.price.id,
		@reservation.discount.id,
		@reservation.id,
		@reservation.seasonal,
		@reservation.storage)
		charges_for_display @reservation

		####################################################
		# save the reservation
		####################################################
		@reservation.save!
		# session[:reservation_id] = @reservation.id
		@use_navigation = false
		@integration = Integration.first
		session[:canx_action] = 'abandon'
		render :action => :show
		rescue => err
		error 'Reservation could not be updated(3) ' + err.to_s
		session[:reservation_id] = nil
		flash[:error] = I18n.t('reservation.Flash.UpdateFail')
		redirect_to :action => :new
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
		if params[:reservation]
			# first time through
			@reservation = Reservation.new(params[:reservation])
			@reservation.startdate = @date_start
			@reservation.enddate = @date_end
			debug "start #{@date_start}, end #{@date_end}"
			unless Campground.open?(@reservation.startdate, @reservation.enddate) ||
			(@option.use_storage? && @reservation.storage?)
	flash[:error] = I18n.t('reservation.Flash.SpaceUnavailable') +
			"<br />" +
			I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(@option.closed_start), :open => DateFmt.format_date(@option.closed_end))
	redirect_to :action => :new and return
			end
			flash.now[:warning] = I18n.t('reservation.Flash.EarlyStart') if @reservation.startdate < currentDate
			@reservation.save!
			if params[:extra]
	extras = Extra.active
	extras.each do |e|
		ex_key = "extra#{e.id}".to_sym
		ct_key = "count#{e.id}".to_sym

		debug "looking for #{e.id} with keys #{ex_key} and #{ct_key}"
		#if params[:extra].key?("extra#{ex.id}".to_sym) && (params[:extra]["extra#{ex.id}".to_sym] != '0')
		if params[:extra].key?(ex_key)
			debug "found extra #{e.id} "
			if (params[:extra][ex_key] != '0')
				debug "and it is true"
				@reservation.extras << e
				debug "added extra #{e.id}"
				ec=ExtraCharge.first(:conditions => [ "extra_id = ? and reservation_id = ?", 
								 e.id, @reservation.id] )
				if e.extra_type == Extra::COUNTED
		ec.save_charges((params[:extra][ct_key]).to_i)
		debug "counted value #{e.id}, value is #{ec.number}"
				else
		ec.save_charges( 0 )
				end
			else
				debug "and it is false"
			end
		else
			debug "not found extra #{e.id}"
		end
	end
			end
			session[:reservation_id] = @reservation.id
			if @reservation.seasonal?
				session[:season] = 1
			else
	session[:season] = Season.find_by_date(@reservation.startdate).id
			end
			session[:startdate] = @reservation.startdate
			session[:enddate] = @reservation.enddate
		end
		@reservation = Reservation.find session[:reservation_id].to_i unless defined?(@reservation)
		@season = Season.find(session[:season].to_i)
		spaces = spaces_for_display(@reservation, @season, @reservation.sitetype_id)
		@spaces = spaces.paginate :page => params[:page], :per_page => @option.disp_rows
		@use_navigation = false
		@map =  '/map/' + @option.map if @option.map && !@option.map.empty? && @option.use_map
		debug 'map is ' + @map if @map
		if @reservation.confirm?
			session[:canx_action] = 'cancel_change'
		else
			session[:canx_action] = 'abandon'
		end
		debug session[:canx_action]
	rescue => err
		error 'Reservation could not be updated(4) ' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.UpdateFail')
		session[:reservation_id] = nil
		redirect_to :action => :new
	end

	def select_change
		####################################################
		# get reservation info for selecting new space
		####################################################
		session[:change] = 'true'
		@page_title = I18n.t('titles.DateSel')
		@reservation = get_reservation
		session[:startdate] = @reservation.startdate
		session[:enddate] = @reservation.enddate
		@seasonal_ok = @option.use_seasonal
		@storage_ok = @option.use_storage
		@count  = Space.available( @reservation.startdate, @reservation.enddate, @reservation.sitetype_id).size if @option.show_available?
		@use_navigation = false
		@change_action = 'space'
		session[:canx_action] = 'cancel_change'
		debug 'Cancel action = ' + session[:canx_action]
	#  unless flash[:error]
	#    session[:canx_action] = session[:action]
	#    session[:next_action] = session[:action]
	#  end
	rescue => err
		error 'Reservation could not be updated(2) ' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.UpdateFail')
		redirect_to :action => session[:canx_action], :reservation_id => @reservation.id
	end

	def change_space
		####################################################
		# given the parameters specified find all spaces not
		# already reserved that fit the spec and supply data
		# for presentation
		####################################################
		session[:change] = 'true'
		@page_title = I18n.t('titles.ChangeSpace')
		@reservation = get_reservation
		unless params[:page]     
			session[:seasonal] = @reservation.seasonal
			debug "seasonal is #{session[:seasonal]}"
			session[:storage] = @reservation.storage
			debug "storage is #{session[:storage]}"
			if params[:reservation][:sitetype_id]
	session[:desired_type] = params[:reservation][:sitetype_id].to_i
			else
	session[:desired_type] = @reservation.sitetype_id
			end
			debug "desired type is #{session[:desired_type]}"
			if session[:seasonal] == true
	session[:startdate] = @reservation.startdate
	session[:enddate] = @reservation.enddate
			else
	# these dates come from application_controller
	@reservation.startdate = @date_start
	@reservation.enddate = @date_end
	session[:startdate] = @reservation.startdate
	session[:enddate] = @reservation.enddate
	unless Campground.open?(@reservation.startdate, @reservation.enddate) ||
				(@option.use_storage? && @reservation.storage?)
		flash[:error] = I18n.t('reservation.Flash.SpaceUnavailable') +
				"<br />" +
				I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(@option.closed_start), :open => DateFmt.format_date(@option.closed_end))
		if @reservation.camper_id? && @reservation.camper_id > 0
			redirect_to :action => session[:current_action], :reservation_id => @reservation.id and return
		else
			session[:reservation_id] = @reservation.id
			redirect_to :action => 'space_selected', :reservation_id => @reservation.id and return
		end
	end
			end
		end
		debug "seasonal is #{session[:seasonal]}, storage is #{session[:storage]}, desired type is #{session[:desired_type]}"
		@season = Season.find_by_date(@reservation.startdate)
		spaces = spaces_for_display(@reservation, @season, session[:desired_type])
		@count = spaces.size if show_available?
		@spaces = spaces.paginate :page => params[:page], :per_page => @option.disp_rows
		@use_navigation = false
		@change_action = 'space'
	rescue => err
		flash[:error]= 'Error handling reservation ' + err.to_s
		error '#change_space Error handling reservation ' + err.to_s
		redirect_to :action => :list
	end
	
	def space_changed
		####################################################
		# update the reservation
		####################################################

		debug "seasonal is #{session[:seasonal]}, storage is #{session[:storage]}, desired type is #{session[:desired_type]}"
		@reservation = get_reservation
		former_space = @reservation.space.name
		@reservation.space_id = params[:space_id].to_i
		@reservation.sitetype_id = session[:desired_type]
		@reservation.startdate = session[:startdate]
		@reservation.enddate = session[:enddate]
		@reservation.seasonal = session[:seasonal]
		@reservation.storage = session[:storage]
		spaces = Space.confirm_available(@reservation.id, @reservation.space_id, @reservation.startdate, @reservation.enddate)
		# debug "#{spaces.size} spaces in conflict"
		if spaces.size > 0
			flash[:error] = I18n.t('reservation.Flash.Conflict')
			error 'space conflict'
			redirect_to :action => :select_change, :reservation_id => @reservation.id  and return
		end
		####################################################
		# calculate charges
		####################################################
		@skip_render = true
		@skip_notice = true
		begin
			if @reservation.save
	# this reload should not be needed but...
	@reservation.reload
	recalculate_charges
	@reservation.add_log("space changed from #{former_space}")
	if @reservation.camper_id? && @reservation.camper_id > 0
		flash[:notice] = I18n.t('reservation.Flash.SpaceChgName',
														 :reservation_id => @reservation.id.to_s,
					 :camper_name => @reservation.camper.full_name,
					 :space => @reservation.space.name)
	else
		flash[:notice] = I18n.t('reservation.Flash.SpaceChg',
														 :reservation_id => @reservation.id.to_s,
					 :space => @reservation.space.name)
	end
			else
	flash[:error] = I18n.t('reservation.Flash.UpdateFail')
			end
			check_length @reservation
		rescue ActiveRecord::StaleObjectError => err
			error 'Reservation change failed ' + err.to_s
			locking_error(@reservation)    
		rescue => err
			error 'Reservation change failed ' + err.to_s
			flash[:error] = I18n.t('reservation.Flash.UpdateFail')
		ensure
			unless @reservation.camper_id? && @reservation.camper_id > 0
				session[:reservation_id] = @reservation.id
	redirect_to :action => 'space_selected', :reservation_id => @reservation.id
			else
	redirect_to :action => session[:current_action], :reservation_id => @reservation.id
			end
		end
	end

	def find_reservation
		@page_title = I18n.t('titles.find_res')
		session[:reservation_id] = nil
		session[:payment_id] = nil
		session[:next_controller] = 'reservation'
		session[:next_action] = 'show'
		session[:camper_found] = 'find_by_campername'
		@campers = Array.new
	end

	def show
		@reservation = get_reservation
		if @reservation.camper_id == 0
			redirect_to :action => :space_selected, :reservation_id => @reservation.id 
			return
		elsif !@reservation.confirm?
			redirect_to :action => :confirm_res, :reservation_id => @reservation.id 
			return
		end
		if @option.use_variable_charge && params[:variable_charge] && params[:variable_charge][:amount] != '0.0'
			new_variable_charge
		end
		@variable_charge = VariableCharge.new if @option.use_variable_charge
		session[:payment_id] = nil
		@cancel_ci = false
		@payments = Payment.find_all_by_reservation_id @reservation.id
		@payment = Payment.new
		if params[:camper_id] && !@reservation.camper_id && !@reservation.archived?
			@reservation.update_attribute(:camper_id,  params[:camper_id].to_i)
			@reservation.camper.active
		end
		if @reservation.archived?
			begin
				archived = Archive.find_by_reservation_id @reservation.id
				@reason = archived.close_reason
			rescue
				@reason = 'unknown'
			end
		else
			if @reservation.checked_in? && ((Date.today - @reservation.startdate  ) <= 2 ) 
				if @option.use_login? && session[:user_id] != nil
					@cancel_ci = true
				elsif !@option.use_login?
					@cancel_ci = true
				end
			end
		end
		if @reservation.group_id
			@page_title = I18n.t('titles.GroupResId', :reservation_id => @reservation.id, :name => @reservation.group.name)
		else
			@page_title = I18n.t('titles.ResId', :reservation_id => @reservation.id)
		end
		if params[:recalculate]
			@skip_render = true
			@skip_notice = true
			recalculate_charges
		end
		@integration = Integration.first
		debug "integration name is #{@integration.name}"
		if @integration.name == 'CardConnect' || @integration.name == 'CardConnect_o'
			@cash_id = Creditcard.find_or_create_by_name('Cash').id
			@check_id = Creditcard.find_or_create_by_name('Check').id
			if @integration.cc_hsn == 'None' 
				# use 41em if 4 items
				@spacing = '34em' # 3 items
			else
				@spacing = '50em' # 5 items
			end
		end
		charges_for_display @reservation
		session[:current_action] = 'show'
		session[:current_controller] = 'reservation'
		session[:camper_found] = 'show'
		session[:next_action] = session[:action] # this is the last action before this
		session[:canx_action] = 'abandon'
		debug 'Cancel action = ' + session[:canx_action]
		session[:canx_controller] = 'reservation'
		session[:fini_action] = session[:list]
		@final = 0.0
	end

	def find_by_number
		####################################################
		# find a reservation given the reservation number
		####################################################
		session[:reservation_id] = nil
		session[:payment_id] = nil
		begin
			@reservation = Reservation.find(params[:reservation][:id].to_i)
			if @reservation.archived
	begin
		archived = Archive.find_by_reservation_id @reservation.id
		@reason = archived.close_reason
	rescue
		@reason = 'unknown'
	end
			end
			session[:reservation_id] = @reservation.id
			redirect_to :action => :show, :reservation_id => @reservation.id
		rescue ActiveRecord::RecordNotFound => err
			error err.to_s
			flash[:error] = I18n.t('reservation.Flash.NotFound',
														 :id => params[:reservation][:id].to_i)
			redirect_to :action => 'find_reservation'
		end
	end

	def find_by_campername
		session[:reservation_id] = nil
		session[:payment_id] = nil
		@reservations = Reservation.all(:conditions => ["confirm = ? and camper_id = ?", true, params[:camper_id].to_i])
		debug "found #{@reservations.size} reservations"
		if @reservations.size > 1
			@page_title = I18n.t('titles.ResName', :name => @reservations[0].camper.full_name)
		elsif @reservations.size == 1
			@reservation = @reservations[0]
			session[:reservation_id] = @reservation.id
			if @reservation.archived
	begin
		archived = Archive.find_by_reservation_id @reservation.id
		@reason = archived.close_reason
	rescue
		@reason = 'unknown'
	end
			end
			redirect_to :action => :show, :reservation_id => @reservation.id
		else
			begin
	camper = Camper.find params[:camper_id].to_i
	debug "camper #{camper.full_name} found"
	@page_title = I18n.t('titles.NoResFoundName', :name => camper.full_name)
			rescue => err
	error I18n.t('camper.NotFound') + err.to_s
	@page_title = I18n.t('titles.NoResFound')
			end
		end
	end

	def available
		@page_title = I18n.t('titles.site_av')
		#########################################################
		#
		# build an array of all of the spaces with 120 date slots
		# identifying whether the space is reserved or not for each
		# date. 
		#
		#########################################################
		session[:reservation_id] = nil

		if @option.use_closed?
			@closedStart = @option.closed_start.change(:year => currentDate.year)
			@closedEnd = @option.closed_end.change(:year => currentDate.year)
			if @closedEnd > @closedStart
				# start and end are in the same year
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed summer"
				@closedSummer = true
			else
				# start is in one year and end is in the next year
				@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 2))
				else
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed winter"
				@closedSummer = false
			end
		end

		@spaces = Space.active
		# getcurrentyear = currentDate.year
		# getcurrentmonth = currentDate.mon
		# getendofcurrentdate = Date.parse("2021-12-31")
		res = Reservation.all( :conditions => [ "(enddate >= ? or checked_in = ?) and confirm = ? and archived = ? or unconfirmed_remote = ? or unconfirmed_remote = ?",currentDate, true, true, false, true, false],
		:include => ['camper'],
				 :order => "space_id,startdate ASC")
		# check for conflicts aka double booking
		res.each do |r|
			sp = Space.confirm_available r.id, r.space_id, r.startdate, r.enddate
			if sp.size > 0
				sp.each do |s|
					if flash[:error]
						flash[:error] +=  " Conflict between #{r.id} and #{s.id}"
					else
						flash[:error] =  "Conflict between #{r.id} and #{s.id}"
					end
				end
			end
		end
		@res = res.group_by{|sp|sp.space_id}
	end

	def refreshTable
		session[:reservation_id] = nil

		if @option.use_closed?
			@closedStart = @option.closed_start.change(:year => currentDate.year)
			@closedEnd = @option.closed_end.change(:year => currentDate.year)
			if @closedEnd > @closedStart
				# start and end are in the same year
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed summer"
				@closedSummer = true
			else
				# start is in one year and end is in the next year
				@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 2))
				else
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed winter"
				@closedSummer = false
			end
		end

		@spaces = Space.active
		# getcurrentyear = currentDate.year
		# getcurrentmonth = currentDate.mon
		# getendofcurrentdate = Date.parse("2021-12-31")
		res = Reservation.all( :conditions => [ "(enddate >= ? or checked_in = ?) and confirm = ? and archived = ? or unconfirmed_remote = ? or unconfirmed_remote = ?",currentDate, true, true, false, true, false],
		:include => ['camper'],
				 :order => "space_id,startdate ASC")
		# check for conflicts aka double booking
		res.each do |r|
			sp = Space.confirm_available r.id, r.space_id, r.startdate, r.enddate
			if sp.size > 0
				sp.each do |s|
					if flash[:error]
						flash[:error] +=  " Conflict between #{r.id} and #{s.id}"
					else
						flash[:error] =  "Conflict between #{r.id} and #{s.id}"
					end
				end
			end
		end
		@res = res.group_by{|sp|sp.space_id}
		render :json => Reservation.refreshTable(@res, request["startYear"], request["startMonth"], request["startDate"], @option, session[:admin_status], request["controllerName"])
	end

	def getNextData
		session[:reservation_id] = nil

		if @option.use_closed?
			@closedStart = @option.closed_start.change(:year => currentDate.year)
			@closedEnd = @option.closed_end.change(:year => currentDate.year)
			if @closedEnd > @closedStart
				# start and end are in the same year
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed summer"
				@closedSummer = true
			else
				# start is in one year and end is in the next year
				@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 2))
				else
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed winter"
				@closedSummer = false
			end
		end

		@spaces = Space.active
		# getcurrentyear = currentDate.year
		# getcurrentmonth = currentDate.mon
		# getendofcurrentdate = Date.parse("2021-12-31")
		res = Reservation.all( :conditions => [ "(enddate >= ? or checked_in = ?) and confirm = ? and archived = ? or unconfirmed_remote = ? or unconfirmed_remote = ?",currentDate, true, true, false, true, false],
		:include => ['camper'],
				 :order => "space_id,startdate ASC")
		# check for conflicts aka double booking
		res.each do |r|
			sp = Space.confirm_available r.id, r.space_id, r.startdate, r.enddate
			if sp.size > 0
				sp.each do |s|
					if flash[:error]
						flash[:error] +=  " Conflict between #{r.id} and #{s.id}"
					else
						flash[:error] =  "Conflict between #{r.id} and #{s.id}"
					end
				end
			end
		end
		@res = res.group_by{|sp|sp.space_id}
		render :json => Reservation.getNextData(@res, request["startYear"], request["startMonth"], request["startDate"], @option, session[:admin_status], request["controllerName"])
	end

	def getPreviousData
		session[:reservation_id] = nil

		if @option.use_closed?
			@closedStart = @option.closed_start.change(:year => currentDate.year)
			@closedEnd = @option.closed_end.change(:year => currentDate.year)
			if @closedEnd > @closedStart
				# start and end are in the same year
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed summer"
				@closedSummer = true
			else
				# start is in one year and end is in the next year
				@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 2))
				else
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed winter"
				@closedSummer = false
			end
		end

		@spaces = Space.active
		# getcurrentyear = currentDate.year
		# getcurrentmonth = currentDate.mon
		# getendofcurrentdate = Date.parse("2021-12-31")
		res = Reservation.all( :conditions => [ "(enddate >= ? or checked_in = ?) and confirm = ? and archived = ? or unconfirmed_remote = ? or unconfirmed_remote = ?",currentDate, true, true, false, true, false],
		:include => ['camper'],
				 :order => "space_id,startdate ASC")
		# check for conflicts aka double booking
		res.each do |r|
			sp = Space.confirm_available r.id, r.space_id, r.startdate, r.enddate
			if sp.size > 0
				sp.each do |s|
					if flash[:error]
						flash[:error] +=  " Conflict between #{r.id} and #{s.id}"
					else
						flash[:error] =  "Conflict between #{r.id} and #{s.id}"
					end
				end
			end
		end
		@res = res.group_by{|sp|sp.space_id}
		render :json => Reservation.getPreviousData(@res, request["startYear"], request["startMonth"], request["startDate"], @option, session[:admin_status], request["controllerName"])
	end

	def available_csv
		####################################################
		# 
		####################################################
		session[:reservation_id] = nil
		csv_string = header_av_csv
		@spaces = Space.active
		@spaces.each do |s|
			csv_string << space_av_csv(s)
		end
		send_data(csv_string,
							:type => 'text/csv;charset=iso-8859-1;header=present',
							:disposition => 'attachment; filename=Available.csv')
	end

	def checkin
		####################################################
		# Just gather information to present a summary
		# to the customer unless you have a group in which
		# case just complete the checkin.
		####################################################
		@reservation = get_reservation
		@payments = Payment.find_all_by_reservation_id session[:reservation_id].to_i
		@payment = Payment.new
		@page_title = I18n.t('titles.Checkin', :name => @reservation.camper.full_name)
		if params[:camper_id]
			@reservation.update_attribute(:camper_id,  params[:camper_id].to_i)
			@reservation.camper.active
		end
		################################
		# general stuff for display
		################################
		if @reservation.space.unavailable
			flash[:error] = I18n.t('reservation.Flash.CheckinFailUnavail',
														 :space => @reservation.space.name,
					 :camper_name => @reservation.camper.full_name,
					 :reservation_id => @reservation.id)
		elsif rr = @reservation.space.occupied
			flash[:error] = I18n.t('reservation.Flash.CheckinFailOcc',
														 :space => @reservation.space.name,
					 :camper_name => @reservation.camper.full_name,
					 :reservation_id => @reservation.id,
					 :other_camper => rr.camper.full_name,
					 :other_reservation => rr.id)
		end
		unless @reservation.startdate == currentDate
			flash[:notice] = I18n.t('reservation.Flash.CheckinVer',
															:reservation_id => @reservation.id,
						:space => @reservation.space.name,
						:startdate => @reservation.startdate)
		end

		session[:current_action] = 'checkin'
		session[:current_controller] = 'reservation'
		session[:next_action] = session[:action]
		session[:camper_found] = 'checkin'
		if @reservation.group_id? && @reservation.group_id > 0
			if @reservation.space.unavailable
	flash[:error] = I18n.t('reservation.Flash.CheckinFailUnavail',
												 :space => @reservation.space.name,
						 :camper_name => @reservation.camper.full_name,
						 :reservation_id => @reservation.id)
			elsif rr = @reservation.space.occupied
	flash[:error] = I18n.t('reservation.Flash.CheckinFailOcc',
												 :space => @reservation.space.name,
						 :camper_name => @reservation.camper.full_name,
						 :reservation_id => @reservation.id,
						 :other_camper => rr.camper.full_name,
						 :other_reservation => rr.id)
			else
	@reservation.checked_in = true
	@reservation.camper.active
	@reservation.add_log("checkin")
	begin
		if @reservation.save
			flash[:notice] = I18n.t('reservation.Flash.CheckedIn',
															:camper_name => @reservation.camper.full_name,
						:space => @reservation.space.name)
			session[:reservation_id] = nil
			session[:payment_id] = nil
		else
			flash[:error] = I18n.t('reservation.Flash.CheckinFail',
														 :camper_name => @reservation.camper.full_name,
					 :space => @reservation.space.name)
		end
	rescue ActiveRecord::StaleObjectError => err
		error err.to_s
		locking_error(@reservation)
	rescue => err
		error err.to_s
		flash[:error] = I18n.t('reservation.Flash.CheckinFail',
													 :camper_name => @reservation.camper.full_name,
				 :space => @reservation.space.name)
	end
			end
			redirect_to  :action => :list and return
		end
		charges_for_display @reservation
		@integration = Integration.first
		session[:canx_action] = 'abandon'  
		debug 'Cancel action = ' + session[:canx_action]
		session[:canx_controller] = 'reservation'
		session[:fini_action] = session[:list]
		render :action => :show
	end

	def checkin_now
		####################################################
		# immediate checkin of current reservation in session
		# first create and save the res then do the checkin
		####################################################
		@reservation = get_reservation
		create_res(true) # skip email
		@reservation.checked_in = true
		@reservation.camper.active
		complete_checkin
	rescue => err
		error 'checkin not completed ' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.CheckinFail',
													 :camper_name => @reservation.camper.full_name,
				 :space => @reservation.space.name)
		redirect_to :action => :show, :reservation_id => @reservation.id
	end

	def do_checkin
		####################################################
		# do checkin.  Resume on reservation/list
		####################################################
		@reservation = get_reservation
		@reservation.checked_in = true
		@reservation.camper.active
		complete_checkin
	rescue => err
		error 'checkin not completed ' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.CheckinFail',
													 :camper_name => @reservation.camper.full_name,
				 :space => @reservation.space.name)
		redirect_to :action => :show, :reservation_id => @reservation.id
	end

	def cancel_checkin
		@reservation = get_reservation
		if @reservation.checked_in?
			@reservation.update_attribute :checked_in, false
			@reservation.add_log("cancel checkin")
		else
			flash[:error] = "Reservation #{@reservation.id} not checked in, cannot cancel checkin"
		end
		redirect_to :action => :show, :reservation_id => @reservation.id
	rescue
		redirect_to :action => :list
	end

	def cancel
		@page_title = I18n.t('titles.CancelReservation')
		####################################################
		# Just gather information to present a summary
		####################################################
		@reservation = get_reservation
	end

	def destroy
		####################################################
		# complete the destruction of a reservation
		####################################################
		begin
			@reservation = get_reservation
			@reservation.add_log("cancelled")
			@reservation.update_attribute :cancelled, true
			if @option.use_login && defined? @user_login
	Reason.close_reason_is "cancelled by: #{@user_login.name} at: #{currentTime} reason: " + params[:close_reason]
			else
	Reason.close_reason_is "cancelled at: #{currentTime} reason: " + params[:close_reason]
			end
		rescue ActiveRecord::RecordNotFound => err
			info err.to_s
			# probably means the reservation is already gone
			redirect_to :action => 'list' and return
		end
		camper = @reservation.camper.full_name
		id = @reservation.id
		# then archive the reservation
		begin
			@reservation.archive
			flash[:notice] = I18n.t('reservation.Flash.Canceled', :camper_name => camper, :reservation_id => id)
			session[:reservation_id] = nil
			session[:payment_id] = nil
			redirect_to :action => 'list'
		rescue RuntimeError => err
			error err.to_s
			flash[:error] = I18n.t('reservation.Flash.CanxFail',
					 :reservation_id => session[:reservation_id])
			redirect_to :action => 'list'
		rescue ActiveRecord::StaleObjectError => err
			error err.to_s
			locking_error(@reservation)
			redirect_to :action => 'list'
		end
	end

	def undo_cancel
		@reservation = get_reservation
		unless @reservation.cancelled?
			flash[:error] = 'Reservation #{@reservation.id} not cancelled, cannot undo cancel'
		else
			res = Reservation.conflict(@reservation)
			if res
	flash[:error] = I18n.t('reservation.Flash.UndoCanxFail1',:reservation_id => @reservation.id)
	res.each do |r|
		flash[:error] += r.id.to_s + ' '
	end
	flash[:error] += I18n.t('reservation.Flash.UndoCFail2')
			else
	@reservation.add_log("undo cancel")
	arch = Archive.find_by_reservation_id @reservation.id
	arch.destroy if arch
	@reservation.update_attributes :archived => false, :cancelled => false
	flash[:notice] = I18n.t('reservation.Flash.UndoCanxOK', :reservation_id => @reservation.id)
			end  
		end
		redirect_to :action => :show, :reservation_id => @reservation.id
	end

	def undo_checkout
		@reservation = get_reservation
		unless @reservation.checked_out?
			flash[:error] = "Reservation #{@reservation.id} not checked out.  Checkout cannot be undone"
		else  
			res = Reservation.conflict(@reservation)
			if res
	flash[:error] = I18n.t('reservation.Flash.UndoCOFail1',:reservation_id => @reservation.id)
	res.each do |r|
		flash[:error] += r.id.to_s + ' '
	end
	flash[:error] += I18n.t('reservation.Flash.UndoCFail2')
			else
	@reservation.add_log("undo checkout")
	arch = Archive.find_by_reservation_id @reservation.id
	arch.destroy if arch
	@reservation.update_attributes :archived => false, :checked_out => false
	flash[:notice] = I18n.t('reservation.Flash.UndoCOOK', :reservation_id => @reservation.id)
			end  
		end
		redirect_to :action => :show, :reservation_id => @reservation.id
	end

	def in_park
		@page_title = I18n.t('titles.in_park')
		####################################################
		# gather a list of all currently in the park
		# with groups condensed
		####################################################
		session[:list] = 'in_park'
		session[:reservation_id] = nil
		session[:next_controller] = nil
		session[:next_action] = nil

		if params[:page]
			page = params[:page]
			session[:page] = page
		else
			page = session[:page]
		end
		begin
			res = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", true, true, false],
					 :include => ["camper", "space", "rigtype"],
					 :order => @option.inpark_list_sort )
			@count = res.size
		rescue
			@option.update_attribute :inpark_list_sort, "unconfirmed_remote desc, enddate, startdate, group_id, spaces.position asc"
			res = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", true, true, false],
					 :include => ["camper", "space", "rigtype"],
					 :order => @option.inpark_list_sort )
			@count = res.size
		end
		@saved_group = nil
		res = res.reject do |r|
			contract(r)
		end
		reservations = res.compact

		@reservations = reservations.paginate(:page => page, :per_page => @option.disp_rows)
		
		####################################################
		# return to here from a camper show
		####################################################
		return_here
		session[:reservation_id] = nil if session[:reservation_id] 
		session[:payment_id] = nil if session[:payment_id] 
		session[:current_action] = 'in_park'
		render(:action => 'list')
	end

	def in_park_expand
		@page_title = I18n.t('titles.in_park')
		####################################################
		# gather a list of all currently in the park
		# with groups expanded
		####################################################
		session[:list] = 'in_park_expand'
		session[:reservation_id] = nil
		session[:next_controller] = nil
		session[:next_action] = nil
		if params[:page]
			page = params[:page]
			session[:page] = page
		else
			page = session[:page]
		end
		begin
			reservations = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", true, true, false],
							:include => ["camper", "space", "rigtype"],
							:order => @option.inpark_list_sort )
			@count = reservations.size
		rescue
			@option.update_attribute :inpark_list_sort, "unconfirmed_remote desc, enddate, startdate, group_id, spaces.position asc"
			reservations = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", true, true, false],
							:include => ["camper", "space", "rigtype"],
							:order => @option.inpark_list_sort )
			@count = reservations.size
		end
		@reservations = reservations.paginate(:page => page, :per_page => @option.disp_rows)
		return_here
		session[:current_action] = 'in_park_expand'
		session[:reservation_id] = nil if session[:reservation_id] 
		session[:payment_id] = nil if session[:payment_id] 
		render(:action => 'expand')
	end

	def do_checkout
		####################################################
		# complete the checkout process
		####################################################
		@reservation = get_reservation
		if (status = @reservation.checkout(@option, @option.use_login ? @user_login.name : nil))
			session[:reservation_id] = nil if session[:reservation_id] 
			session[:payment_id] = nil if session[:payment_id] 
			flash[:notice] = I18n.t('reservation.Flash.CheckedOut', :camper_name => @reservation.camper.full_name)
			if @option.use_feedback && validEmail(@reservation.camper.email)
	render :action => :feedback
			else
	redirect_to  :action => 'in_park'
			end
		else
			error status.to_s
			flash[:error] = I18n.t('reservation.Flash.CheckoutFail', :camper_name => @reservation.camper.full_name)
			redirect_to  :action => 'in_park'
		end
	rescue => err
		error err.to_s
		flash[:error] = I18n.t('reservation.Flash.CheckoutFail', :camper_name => @reservation.camper.full_name)
		redirect_to  :action => 'in_park'
	rescue ActiveRecord::RecordNotFound => err
		error 'Reservation not found ' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.NotFound', :id => session[:reservation_id])
		redirect_to  :action => 'in_park'
	rescue ActiveRecord::StaleObjectError => err
		error err.to_s
		locking_error(@reservation)
		redirect_to  :action => 'in_park'
	end

	def feedback
		sent = false
		@email = Email.first
		# this is a bogus reservation just for creating the message
		# it will never be saved
		@reservation = Reservation.new :camper_id => params[:camper_id].to_i,
					 :space_id => params[:space_id].to_i,
					 :startdate => params[:startdate],
					 :enddate => params[:enddate],
					 :total => params[:total],
					 :deposit => params[:deposit]
		@reservation.id = params[:reservation_id].to_i
		begin
			email = ResMailer.deliver_reservation_feedback(@reservation, @email, @option)
			flash[:notice] = I18n.t('reservation.Flash.FeedbackSent')
		rescue => err
			error err.to_s
			flash[:error] = I18n.t('reservation.Flash.FeedbackErr')
		end
		redirect_to  :action => 'in_park'
	end

	def get_override
		@reservation = get_reservation
	end

	def override
		@reservation = get_reservation
		if @reservation.update_attributes :override_total => params[:reservation][:override_total]
			@reservation.add_log("override to #{@reservation.override_total}")
			@skip_render = true
			recalculate_charges
			if defined? session[:current_action]
	redirect_to :action => session[:current_action], :reservation_id => @reservation.id
			else
	redirect_to :action => :show, :reservation_id => @reservation.id
			end
		else
			render :action => :get_override and return
		end
	end

	def cancel_override
		@reservation = get_reservation
		if @reservation.update_attributes :override_total => 0.0
			@reservation.add_log("cancel override")
			@skip_render = true
			recalculate_charges
			if defined? session[:current_action]
	redirect_to :action => session[:current_action], :reservation_id => @reservation.id
			else
	redirect_to :action => :show, :reservation_id => @reservation.id
			end
		else
			render :action => :get_override and return
		end
	rescue
		flash[:error] = "reservation #{params[:id]} not found"
		if defined? session[:current_action]
			redirect_to :action => session[:current_action], :reservation_id => @reservation.id
		else
			redirect_to :action => :show, :reservation_id => @reservation.id
		end
	end

	def review
		####################################################
		# review data in a reservation.
		# reservation id is in session at the end of this
		####################################################
		@page_title = I18n.t('titles.ConfirmRes')
		@reservation = get_reservation
		if params[:camper_id]
			@reservation.update_attribute(:camper_id,  params[:camper_id].to_i)
			@reservation.camper.active
		end
		@payments = Payment.find_all_by_reservation_id @reservation.id
		@payment = Payment.new
		@integration = Integration.first
		charges_for_display @reservation
		session[:early_date] = 0
		session[:late_date] = 0
		session[:canx_action] = 'abandon'
		debug 'Cancel action = ' + session[:canx_action]
		session[:next_action] = session[:action]
		session[:camper_found] = 'review'
		session[:current_action] = 'review'
		render :action => :show
	end

	def remote_not_confirmed
		@reservation = get_reservation
		if @option.use_remote_res_reject? 
			if validEmail(@reservation.camper.email)
	sent = false
	@email = Email.first
	begin
		email = ResMailer.deliver_remote_reservation_reject(@reservation, @email, @option)
		flash[:notice] = I18n.t('reservation.Flash.NonConfSent')
	rescue => err
		error err.to_s
		flash[:error] = I18n.t('reservation.Flash.NonConfErr')
	end
			else
	flash[:notice] = I18n.t('reservation.Flash.NonConfNotSent')
			end
		end
		@reservation.add_log("remote reservation not confirmed")
		Reason.close_reason_is "Remote reservation not confirmed"
		begin
			@reservation.archive
			session[:reservation_id] = nil
			session[:payment_id] = nil
			redirect_to :action => 'list'
		rescue RuntimeError => err
			error err.to_s
			redirect_to :action => 'list'
		rescue ActiveRecord::StaleObjectError => err
			error err.to_s
			locking_error(@reservation)
			redirect_to :action => 'list'
		end
	end

	def remote_confirmed
		@reservation = get_reservation
		if @option.use_remote_res_confirm?
			if validEmail(@reservation.camper.email)
	sent = false
	@email = Email.first
	begin
		email = ResMailer.deliver_remote_reservation_confirmation(@reservation, @email, @option)
		flash[:notice] = I18n.t('reservation.Flash.ConfSent')
	rescue => err
		error err.to_s
		flash[:error] = I18n.t('reservation.Flash.ConfErr')
	end
			else
	flash[:notice] = I18n.t('reservation.Flash.ConfNotSent')
			end
		end
		@reservation.update_attribute( :unconfirmed_remote, false)
		@reservation.add_log("remote reservation confirmed")
		redirect_to :action => 'list'
	end

	####################################################
	# methods called from in_place_edit
	####################################################

	def set_payment_deposit_formatted
		@reservation = get_reservation
		if params[:value] 
			pmt = currency_2_number(params[:value])
			if @option.use_login && defined? @user_login
	name = @user_login.name
			else
	name = ""
			end
			if session[:payment_id]
	@payment = Payment.find session[:payment_id].to_i
	@payment.update_attributes :amount => pmt, :name => name
			else
	@payment = Payment.create! :amount => pmt, :reservation_id => session[:reservation_id], :name => name
	@payment.reload
	session[:payment_id] = @payment.id
			end
			debug "#set_payment_deposit_formatted going to charges for display with res #{@reservation.id}"
			charges_for_display(@reservation)
			render :update do |page|
	page[:pmt].replace_html :partial => 'pmt'
	page[:charges].reload
			end
		else
			render :nothing => true
		end
	end

	def set_reservation_onetime_formatted
		@reservation = get_reservation
		if params[:value] 
			discount = currency_2_number(params[:value])
			# debug "discount is #{discount}"
			@reservation.update_attribute :onetime_discount, discount
			@skip_render = true
			recalculate_charges
			charges_for_display(@reservation)
			render :update do |page|
	page[:onetimedisc].replace_html :partial => 'get_one_time_discount'
	page[:charges].reload
			end
		else
			render :nothing => true
		end
	end

	def set_payment_memo
		@reservation = get_reservation
		if params[:value] 
			@payment = Payment.find(session[:payment_id].to_i)
			@payment.update_attribute(:memo, params[:value])
			charges_for_display(@reservation)
			render :update do |page|
	page[:flash].replace_html ""
	page[:pmt].replace_html :partial => 'pmt'
	page[:charges].reload
			end
		else
			render :nothing => true
		end
	end

	def set_payment_credit_card_no
		@reservation = get_reservation
		if params[:value] 
			debug "session payment is #{session[:payment_id]}"
			@payment = Payment.find(session[:payment_id].to_i)
			if @payment.creditcard.validate_cc_number? && !Creditcard.valid_credit_card?(params[:value])
	render :update do |page|
		page[:flash].replace_html I18n.t('reservation.Flash.CardNoInvalid')
		page[:cc_error].replace_html I18n.t('reservation.Flash.CardNoInvalid')
		page[:flash][:style][:color] = 'red'
		page[:flash].visual_effect :highlight
		# debug "editorID = #{params[:editorId]}"
		page[:pmt].replace_html :partial => 'pmt'
		# debug "editorID = #{params[:editorId]}"
		# page[params[:editorId]][:style][:background_color] = 'red'
		# page[params[:editorId]].visual_effect :highlight
		page.visual_effect :highlight, params[:editorId], {:startcolor => 'ff0000'}
	end
			else
	@payment.update_attribute(:credit_card_no, params[:value])
	charges_for_display(@reservation)
	render :update do |page|
		page[:cc_error].replace_html ''
		page[:flash].replace_html ""
		page[:pmt].replace_html :partial => 'pmt'
		page[:charges].reload
	end
			end
		else
			render :nothing => true
		end
	end

	def set_payment_exp_str
		@reservation = get_reservation
		if params[:value] 
			@payment = Payment.find(session[:payment_id].to_i)
			begin
	mo,yr = params[:value].split '/'
	exp_dt = "01-#{mo}-20#{yr}".to_date.end_of_month
	debug "expire date is #{exp_dt}"
			rescue
	exp_dt = currentDate.beginning_of_year
			end
			if @payment.creditcard.card_expired?( exp_dt )
	debug "card expired"
	render :update do |page|
		page[:flash].replace_html I18n.t('reservation.Flash.CardExpired')
		page[:cc_error].replace_html I18n.t('reservation.Flash.CardExpired')
		page[:flash][:style][:color] = 'red'
		page[:flash].visual_effect :highlight
		page[:pmt].replace_html :partial => 'pmt'
		page.visual_effect :highlight, params[:editorId], {:startcolor => 'ff0000'}
	end
			else
	@payment.update_attributes :cc_expire => exp_dt
	render :update do |page|
		page[:cc_error].replace_html ''
		page[:flash].replace_html ""
		page[:pmt].replace_html :partial => 'pmt'
	end
			end
		else
			render :nothing => true
		end
	end

	def set_camper_last_name
		# Parameters: {"action"=>"set_camper_last_name",
		#		   "id"=>"4",
		#		   "value"=>"",
		#		   "controller"=>"reservation",
		#		   "editorId"=>"camper_last_name_4_in_place_editor"}
		unless [:post, :put].include?(request.method) then
			return render(:text => 'Method not allowed', :status => 405)
		end
		@item = Camper.find(params[:id].to_i)
		err = @item.update_attributes(:last_name => params[:value])
		unless err
			@item.reload
		end  
		render :text => CGI::escapeHTML(@item.last_name.to_s)
	end

	####################################################
	# methods called from observers
	####################################################

	def update_group
		@reservation = get_reservation
		if params[:group_id] != ""
			@id = params[:group_id].to_i
			@group = Group.find(@id)
		else
			@id = nil
			@group = Group.find(@reservation.group_id)
		end
		@reservation.update_attribute :group_id, @id
		@group.update_attribute :expected_number, Reservation.find_all_by_group_id_and_archived(@group.id, false).count
		render(:nothing => true)
	end

	def update_cc_expire
		@integration = Integration.first
		@reservation = get_reservation
		if params[:payment]
			if session[:payment_id]
	exp = Date.new(params[:payment]['cc_expire(1i)'].to_i,
					 params[:payment]['cc_expire(2i)'].to_i,
					 params[:payment]['cc_expire(3i)'].to_i)
	exp_dt = exp.end_of_month
				@payment = Payment.find session[:payment_id].to_i
			end
			@payment.update_attributes :cc_expire => exp_dt
			charges_for_display(@reservation)
			if @payment.creditcard.card_expired?( exp_dt )
	render :update do |page|
		page[:flash].replace_html I18n.t('reservation.Flash.CardExpired')
		page[:cc_error].replace_html I18n.t('reservation.Flash.CardExpired')
		page[:flash][:style][:color] = 'red'
		page[:flash].visual_effect :highlight
		page[:pmt].replace_html :partial => 'pmt'
		page.visual_effect :highlight, :cc_expire, {:startcolor => 'ff0000'}
	end
			else
	render :update do |page|
		page[:cc_error].replace_html ''
		page[:flash].replace_html ""
		page[:pmt].replace_html :partial => 'pmt'
		page[:charges].reload
	end
			end
		else
			error 'no params[:payment]'
			render(:nothing => true)
		end
	end 

	def update_check
		@reservation = get_reservation
		#  check if Check is a 'credit card' if not create it
		#  with appropriate options
		creditcard = Creditcard.find_or_create_by_name('Check')
		#  then render the creditcard display
		@payment = Payment.create! :reservation_id => @reservation.id,
						 :creditcard_id => creditcard.id
		session[:payment_id] = @payment.id
		debug "session payment created and defined as #{session[:payment_id]}"
		charges_for_display(@reservation)
		render :update do |page|
			page[:pmt].replace_html :partial => 'pmt'
		end
	end

	def update_cash
		@reservation = get_reservation
		#  check if Cash is a 'credit card' if not create it
		#  with appropriate options
		creditcard = Creditcard.find_or_create_by_name('Cash')
		#  then render the creditcard display
		@payment = Payment.create! :reservation_id => @reservation.id,
						 :creditcard_id => creditcard.id
		session[:payment_id] = @payment.id
		debug "session payment created and defined as #{session[:payment_id]}"
		charges_for_display(@reservation)
		render :update do |page|
			page[:pmt].replace_html :partial => 'pmt'
		end
	end

	def update_cc
		@integration = Integration.first
		@reservation = get_reservation
		if params[:creditcard_id]
			debug 'we have an id!'
			if session[:payment_id]
	debug "session payment defined as #{session[:payment_id]}"
				@payment = Payment.find session[:payment_id].to_i
	@payment.update_attribute :creditcard_id, params[:creditcard_id].to_i
			else
	debug "creating new payment"
	new_payment = true
				@payment = Payment.create! :reservation_id => session[:reservation_id].to_i,
						 :creditcard_id => params[:creditcard_id].to_i
	@payment.reload
	session[:payment_id] = @payment.id
	debug "session payment created and defined as #{session[:payment_id]}"
			end
			charges_for_display(@reservation)
			render :update do |page|
	page[:pmt].replace_html :partial => 'pmt'
	page[:charges].reload unless new_payment
			end
		else
			error 'no params[:creditcard_id]'
			render(:nothing => true)
		end
	end 

	def update_pmt_date
		@reservation = get_reservation
		@payment = Payment.find session[:payment_id].to_i
		begin
			if params[:date]
	@payment.update_attribute :pmt_date, params[:date]
			elsif params[:day]
	pmt = Date.new(@payment.pmt_date.year, @payment.pmt_date.mon, params[:day].to_i)
	@payment.update_attribute :pmt_date, pmt
			elsif params[:month]
	pmt = Date.new(@payment.pmt_date.year, params[:month].to_i, @payment.pmt_date.day)
	@payment.update_attribute :pmt_date, pmt
			elsif params[:year]
	pmt = Date.new(params[:year].to_i, @payment.pmt_date.mon, @payment.pmt_date.day)
	@payment.update_attribute :pmt_date, pmt
			end
		rescue => err
			error err.to_s
		end
		charges_for_display(@reservation)
		render :update do |page|
			page[:pmt].replace_html :partial => 'pmt'
			page[:charges].reload
		end
	end

	def update_recommend
		@reservation = get_reservation
		if params[:recommender_id]
			@recommenders = Recommender.active
			@reservation.update_attribute :recommender_id, params[:recommender_id].to_i
		else
			error 'no params[:recommender_id]'
		end
		render(:nothing => true)
	end 

	def update_rigtype
		@reservation = get_reservation
		if params[:rigtype_id]
			@reservation.update_attribute :rigtype_id, params[:rigtype_id].to_i
		else
			error 'no params[:rigtype_id]'
		end
		render(:nothing => true)
	end 

	def update_seasonal
		if defined?(params[:seasonal])
			if session[:reservation_id]
	res = Reservation.find(session[:reservation_id].to_i)
	space_id = res.space_id
			else
				space_id = 0
			end
			@reservation = Reservation.new(:startdate => @option.season_start,
						 :enddate => @option.season_end,
						 :space_id => space_id,
						 :seasonal => params[:seasonal],
						 :storage => false)
			@seasonal_ok = @reservation.check_seasonal
			@storage_ok = @reservation.check_storage
			debug "seasonal_ok = #{@seasonal_ok}, storage_ok = #{@storage_ok}"
			render :update do |page|
	page[:dates].reload
			end
		else
			error 'no params[:seasonal]'
			render(:nothing => true)
		end
	rescue => err
		error err.to_s
		render(:nothing => true)
	end

	def update_storage
		if defined?(params[:storage])
			if session[:reservation_id]
	res = Reservation.find(session[:reservation_id].to_i)
	space_id = res.space_id
	startdate = res.startdate
	enddate = res.enddate
			else
				space_id = 0
	startdate = session[:startdate]
	enddate = session[:enddate]
			end
			@reservation = Reservation.new(:startdate => startdate,
						 :enddate => enddate,
						 :space_id => space_id,
						 :storage => params[:storage],
						 :seasonal => false)
			@seasonal_ok = @reservation.check_seasonal
			@storage_ok = @reservation.check_storage
			debug "seasonal_ok = #{@seasonal_ok}, storage_ok = #{@storage_ok}"
			render :update do |page|
	page[:dates].reload
			end
		else
			error 'no params[:storage]'
			render(:nothing => true)
		end
	rescue => err
		error err.to_s
		render(:nothing => true)
	end

	def update_discount
		@reservation = get_reservation
		if params[:discount_id]
			if @reservation.seasonal? && Discount.skip_seasonal?
	debug 'rendering nothing and returning'
	render(:nothing => true)
	return
			end
			@payments = Payment.find_all_by_reservation_id @reservation.id
			@reservation.update_attribute :discount_id, params[:discount_id].to_i
			@skip_render = true
			recalculate_charges
			charges_for_display(@reservation)
			render :update do |page|
	page[:charges].reload
			end
		else
			error 'no params[:discount_id]'
			render(:nothing => true)
		end
	end

	def update_extras
		@reservation = get_reservation
		if params[:extra]
			debug "in update_extras"
			@payments = Payment.find_all_by_reservation_id @reservation.id
			extra = Extra.find params[:extra].to_i
			debug "extra_type is #{extra.extra_type.to_s}"
			case extra.extra_type
			when Extra::MEASURED
	debug 'extra is MEASURED'
	if params[:checked] == 'true'
		old = ExtraCharge.find_all_by_extra_id_and_reservation_id_and_charge(extra.id, @reservation.id, 0.0)
		old.each {|o| o.destroy } # get rid of partially filled out records
		ec = ExtraCharge.create :reservation_id => @reservation.id, :extra_id => extra.id
		session[:ec] = ec.id
		@current = @reservation.space.current
		hide = false
		debug "created new measured entity"
	else
		ec = ExtraCharge.find session[:ec].to_i
		ec.destroy
		session[:ec] = nil
		hide = true
		debug "destroyed measured entity"
	end
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
					:number => 1,
					:days => (@reservation.enddate - @reservation.startdate)
		hide = false
		debug "created new entity"
	end
			else 
	debug 'extra STANDARD'
	if (ec = ExtraCharge.find_by_extra_id_and_reservation_id(extra.id, @reservation.id))
		# extra charge currently is applied so we have dropped it
		ec.destroy
		hide = true
		debug "destroyed entity"
	else
		# extra charge is not currently applied
		# extra was added, apply it
		ec = ExtraCharge.create :reservation_id => @reservation.id,
					:extra_id => extra.id
		hide = false
		debug "created new entity"
	end
			end
			@skip_render = true
			# recalculate_charges.. skip recalc because the charges do not change
			charges_for_display(@reservation)
			# debug "recalculated charges"
			debug "saved reservation"
			cnt = "count_#{extra.id}".to_sym
			cntdays = "days_#{extra.id}".to_sym
			ext = "extra#{extra.id}".to_sym
			render :update do |page|
	case ec.extra.extra_type
	when Extra::COUNTED, Extra::OCCASIONAL
		# debug "counted"
		if hide
			# debug "hide"
			page[cnt].hide
			page[cntdays].hide
		else
			# debug "show"
			page[cnt].show
			page[cntdays].show
		end
	when Extra::MEASURED
		# debug "measured"
		measure = "measure_#{extra.id}".to_sym
		if hide
			# debug "hide"
			page[measure].hide
		else
			# debug "show"
			page[measure].show
		end
	end
	# debug "reload charges"
	page[:charges].reload
			end
			# render :partial => 'space_summary', :layout => false
			debug "done with update_extras"
		else
			error 'no params[:extra]'
			render(:nothing => true)
		end
	end 

	def update_count
		@reservation = get_reservation
		if params[:extra_id]
			extra_id = params[:extra_id].to_i
			@payments = Payment.find_all_by_reservation_id @reservation.id
			ec = ExtraCharge.find_by_extra_id_and_reservation_id(extra_id, @reservation.id)
			debug "updating count to #{params[:number]}"
			ec.update_attributes :number => params[:number].to_i

			@skip_render = true
			# recalculate_charges.. skip recalc because the charges do not change
			charges_for_display(@reservation)
			# render :partial => 'space_summary', :layout => false
			# debug "rendered space_summary"
			render :update do |page|
				# debug "reload charges"
				page[:charges].reload
			end
		else
			error 'no params[:extra_id]'
			render :nothing => true
		end
	end

	def update_days
		@reservation = get_reservation
		if params[:extra_id]
			extra_id = params[:extra_id].to_i
			@payments = Payment.find_all_by_reservation_id @reservation.id
			ec = ExtraCharge.find_by_extra_id_and_reservation_id(extra_id, @reservation.id)
			debug "updating days to #{params[:days]}"

			maxDays = @reservation.enddate - @reservation.startdate
			if params[:days].to_i > maxDays
				extraDays = maxDays
			else
				extraDays = params[:days].to_i
			end
			
			ec.update_attributes :days => extraDays

			temp = Charge.first(:conditions => ["reservation_id = ?", @reservation.id])
			Charge.update(temp.id, :period => maxDays)
			# period.update :period => params[:days].to_i

			@skip_render = true
			# recalculate_charges.. skip recalc because the charges do not change
			charges_for_display(@reservation)
			# render :partial => 'space_summary', :layout => false
			# debug "rendered space_summary"
			render :update do |page|
				# debug "reload charges"
				page[:charges].reload
			end
		else
			error 'no params[:extra_id]'
			render :nothing => true
		end
	end

	def update_initial
		@reservation = get_reservation
		if params[:value]
			debug "update initial: current = #{params[:value]}"
			@reservation.space.update_attributes :current => params[:value].to_f
		else
			error 'no params[:value]'
		end
		render :nothing => true
	end

	def update_final
		@reservation = get_reservation
		if params[:value] && params[:extra_id]
			final = params[:value].to_f
			final = 0.0 unless final
			extra_id = params[:extra_id].to_i
			debug "update_final: final = #{final}, extra_id = #{extra_id}"
			@payments = Payment.find_all_by_reservation_id @reservation.id
			@extra = Extra.find params[:extra_id].to_i

			initial = @reservation.space.current ? @reservation.space.current.to_f : 0.0
			used =  final - initial
			debug "initial = #{initial}, final = #{final}, used = #{used}"
			if used > 0
	debug "computing charges"
	# compute charges
	charge = used * @extra.rate
	debug "charge = #{charge}"
	# update charges
	ec = ExtraCharge.create(:extra_id => @extra.id,
				:reservation_id => @reservation.id,
				:initial => initial,
				:measured_rate => @extra.rate,
				:final => final,
				:charge => charge )
	# set new current value
	@reservation.space.update_attributes :current => final
	@skip_render = true
	# recalculate_charges
	charges_for_display(@reservation)
	render :update do |page|
		# debug "reload charges"
		page[:charges].reload
	end
			else
	# flash warning
	debug "computing charges"
	render :nothing => true
			end
		else
			error 'no params[:value] or [:extra_id]'
			render :nothing => true
		end
	end

	def update_mail_msg
		@reservation = get_reservation
		if @reservation.deposit == 0.0
			pmt = Payment.find_by_reservation_id @reservation.id
			@reservation.update_attribute :deposit, pmt.amount if pmt
		end
		sent = false
		if @option.use_confirm_email?
			if validEmail(@reservation.camper.email)
	@email = Email.first
	begin
		email = ResMailer.deliver_reservation_update(@reservation, @email, @option)
		sent = true
	rescue => err
		error err.to_s
	end
			end
		end
		render :update do |page|
			if sent
	page[:flash].replace_html "<span id=\"inputError\">" + I18n.t('reservation.Flash.UpdateSent') + "</span>"
	page[:flash][:style][:color] = 'green'
			else
	page[:flash].replace_html "<span id=\"inputError\">" + I18n.t('reservation.Flash.UpdateErr') + "</span>"
	page[:flash][:style][:color] = 'red'
			end
			page[:flash].visual_effect :highlight
			page[:update_mail_msg].replace_html ""
		end
	end

	def purge
		id = params[:reservation_id]
		if User.authorized?('reservation','purge')
			begin
	Reservation.destroy id
	info "reservation #{id} purged"
			rescue ActiveRecord::RecordNotFound => err
	flash[:error] = I18n.t('reservation.Flash.Purged', :id => id)
			end
			arch = Archive.find_by_reservation_id id
			begin
	Archive.destroy arch.id
	info "archive #{arch.id} for reservation #{id} purged"
			rescue => err
	flash[:error] = I18n.t('reservation.Flash.Purged', :id => id)
			end
			flash[:notice] = I18n.t('reservation.Flash.Purged', :id => id)
		else
			flash[:error] = I18n.t('general.Flash.NotAuth')
		end
		redirect_to :action => 'list'
	rescue => err
		redirect_to :action => 'list'
	end

	def abandon
		res = Reservation.find(params[:reservation_id].to_i)
		if res.id != 0
			Reason.close_reason_is "abandoned"
			begin
	res.archive
			rescue RuntimeError => err
	error 'Abandon: ' + err.to_s
			rescue ActiveRecord::StaleObjectError => err
	error 'Abandon: ' + err.to_s
	locking_error(res)
			end
			flash[:notice] = "Reservation #{res.id} deleted"
		else
			res.destroy
		end
		SpaceAlloc.delete_all(["reservation_id = ?", session[:reservation_id]])
		session[:reservation_id] = nil
		session[:payment_id] = nil
		session[:group_id] = nil
		session[:current_action] = 'show'
	rescue ActiveRecord::RecordNotFound => err
		info err.to_s
		# probably means the reservation is already gone
	rescue => err
		error err.to_s
	ensure
		if session[:list]
			redirect_to :action => session[:list], :controller => :reservation
		else
			redirect_to :action => :list, :controller => :reservation
		end
	end

	private
	####################################################
	# methods that cannot be called externally
	####################################################
	def new_variable_charge
		debug 'new_variable_charge'
		debug "params are #{params[:variable_charge]}"
		variable_charge = VariableCharge.new(params[:variable_charge])
		variable_charge.reservation_id = @reservation.id
		variable_charge.save!
		if params[:taxes]
			params[:taxes].each do |t|
	tax = Taxrate.find_by_name t[0]
	if t[1] == '1'
		variable_charge.taxrates << tax unless variable_charge.taxrates.exists?(tax)
	else
		variable_charge.taxrates.delete(tax) if variable_charge.taxrates.exists?(tax)
	end
			end
		end
	end

	def get_reservation
		if params[:reservation_id]
			reservation = Reservation.find(params[:reservation_id].to_i)
			debug 'got res from params'
			session[:reservation_id] = reservation.id
		else
			reservation = Reservation.find(session[:reservation_id].to_i)
			info 'got res from session'
		end
		reservation
		rescue ActiveRecord::RecordNotFound => err
		error 'Reservation not found ' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.NotFound',
					:id => session[:reservation_id])
		if session[:list]
			redirect_to :action => session[:list] and return
		else
			redirect_to :action => :list and return
		end
	end

	def get_reservation_by_id
		# the set functions from inplace edit pass the 
		# reservation id in an id parameter
		if params[:id]
			reservation = Reservation.find(params[:id].to_i)
			debug 'got res from params'
			session[:reservation_id] = reservation.id
		else
			reservation = Reservation.find(session[:reservation_id].to_i)
			info 'got res from session'
		end
		reservation
		rescue ActiveRecord::RecordNotFound => err
		error 'Reservation not found ' + err.to_s
		flash[:error] = I18n.t('reservation.Flash.NotFound',
					:id => session[:reservation_id])
		if session[:list]
			redirect_to :action => session[:list] and return
		else
			redirect_to :action => :list and return
		end
	end

	def check_length res
		if  res.space.length > 0 &&
	res.length &&
	res.length > res.space.length
		flash[:warning] = I18n.t('reservation.Flash.CamperLong',
						:camper_length => res.length,
						:space_length => res.space.length)
		end
	end

	def spaces_for_display( reservation, season, sitetype)
		sp = []
		spaces = Space.available( session[:startdate], session[:enddate], sitetype)
		debug "#{spaces.size} spaces found"
		spaces.each do |s|
			rate = Rate.find_current_rate(season.id, s.price_id)
			if reservation.storage?
	next unless @option.use_storage? 
	next if rate.not_storage
			elsif reservation.seasonal?
	next unless @option.use_seasonal?
	next if rate.not_seasonal
			else
	next if rate.no_rate?(reservation.enddate - reservation.startdate)
			end
			sp << s
		end
		debug "#{sp.size} spaces kept"
		return sp
	end

	def header_av_csv
		start_date = currentDate - @option.lookback.to_i
		# days = @option.sa_columns
		days = @option.custom_sa_columns
		ret_str = 'Space'
		enddate = start_date + days
		date = start_date
		while date < enddate
			ret_str << ';'
			ret_str << "\"" + I18n.l(date) + "\""
			date = date.succ
		end
		ret_str << "\n"
	end

	def space_av_csv(space)
		# o = occupied
		# r = reserved
		# - = available
		#############################################
		# space is the space we are currently 
		# building up the string for, res_array
		# is the array of all confirmed reservations
		# ordered by space_id and startdate
		#############################################
		start_date = currentDate - @option.lookback
		# days = @option.sa_columns
		days = @option.custom_sa_columns
		enddate = start_date + days
		date = start_date
		res = Reservation.all( :conditions => [ "space_id = ? AND enddate >= ? AND confirm = ? AND archived = ?",space.id, start_date, true, false],
				 :order => "startdate ASC")
		ret_str = "\"" + space.name + "\""

		# for each date from start_date to enddate
		# if res empty
		#  output -
		# elsif current => res[0].start and current < res[0]end
		# elsif current == res[0].end
		#  shift res[1] to res[0]
		#  if res.empty output -
		#  elsif current == res[0].start
		#    output o
		#  else
		#    output -
		#  end
		# end

		while date < enddate
			if res.empty?
				ret_str << ";\"-\""
			elsif date >= res[0].startdate && date < res[0].enddate
				if res[0].checked_in?
		ret_str << ";\"O\""
	else
		ret_str << ";\"R\""
	end
			elsif date == res[0].enddate
				res.shift
	if !res.empty? && date == res[0].startdate
		if res[0].checked_in?
			ret_str << ";\"O\""
		else
			ret_str << ";\"R\""
		end
	else
		ret_str << ";\"-\""
	end
			else
	ret_str << ";\"-\""
			end
			date = date.succ
		end
		ret_str << "\n"
	end

	###################################################################
	# a method to muster the charge variables for display
	###################################################################
	def charges_for_display(res)
		warn = ''
		res.reload
		debug "charges_for_display"
		@charges = Charge.stay(res.id)
		total = 0.0
		@charges.each do |c| 
			warn += "charge rate for season #{c.season.name} is zero. Correct in setup->prices." if c.amount == 0.00
			total += c.amount - c.discount 
		end
		flash[:warning] = warn unless warn.empty?
		debug "charges #{total}"
		total += calculate_extras(res.id)
		debug "added extras #{total}"
		total += VariableCharge.charges(res.id)
		debug "added variable #{total}"
		total -= res.onetime_discount
		debug "after onetime discount #{total}"
		tax_amount = Taxrate.calculate_tax(res.id, @option)
		debug "saving total #{total} and tax_amount #{tax_amount}"
		res.update_attributes(:total => total, :tax_amount => tax_amount)
		debug "getting taxes"
		@tax_records = Tax.find_all_by_reservation_id(res.id)
		debug "getting payments"
		@payments = Payment.find_all_by_reservation_id session[:reservation_id].to_i
		@season_cnt = Season.count(:conditions => ["active = ?", true])
		debug "#{@season_cnt} seasons"
	end


	def get_sort
		####################################################
		# get the sort attribute for options
		####################################################
		list = case session[:list]
			when 'list' then 'res'
			when 'expand' then 'res'
			when 'in_park' then 'inpark'
			when 'in_park_expand' then 'inpark'
		end
		list + '_list_sort'
	end

	def complete_checkin
		####################################################
		# Complete checkin.
		####################################################
		if @reservation.space.unavailable
			flash[:error] = I18n.t('reservation.Flash.CheckinFailUnavail',
														 :space => @reservation.space.name,
					 :camper_name => @reservation.camper.full_name,
					 :reservation_id => @reservation.id)
		elsif rr = @reservation.space.occupied
			flash[:error] = I18n.t('reservation.Flash.CheckinFailOcc',
														 :space => @reservation.space.name,
					 :camper_name => @reservation.camper.full_name,
					 :reservation_id => @reservation.id,
					 :other_camper => rr.camper.full_name,
					 :other_reservation => rr.id)
		else
			@reservation.add_log("checkin")
			begin
	if @reservation.save
		flash[:notice] = I18n.t('reservation.Flash.CheckedIn',
														:camper_name => @reservation.camper.full_name,
					:space => @reservation.space.name)
		session[:reservation_id] = nil
		session[:payment_id] = nil if session[:payment_id] 
	else
		flash[:error] = I18n.t('reservation.Flash.CheckinFail',
													 :camper_name => @reservation.camper.full_name,
				 :space => @reservation.space.name)
	end
			rescue ActiveRecord::StaleObjectError => err
	error err.to_s
	locking_error(@reservation)
			rescue => err
	error err.to_s
	flash[:error] = I18n.t('reservation.Flash.CheckinFail',
												 :camper_name => @reservation.camper.full_name,
						 :space => @reservation.space.name)
			end
		end
		redirect_to :action => 'list'
	end

	def create_res(skip_email = false)
		####################################################
		# save the data in the database
		####################################################
		@reservation.confirm = true
		payment = Payment.find_by_reservation_id(@reservation.id)
		@reservation.deposit = payment.amount if payment
		@reservation.add_log("reservation made")
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
	end

	def contract(res)
		####################################################
		# given the reservation find if it should be displayed
		####################################################
		if res.group_id == nil
			@saved_group = nil
			nil
		else
			if res.group_id == @saved_group
	1
			else
	@saved_group = res.group_id
	nil
			end
		end
	end

end
