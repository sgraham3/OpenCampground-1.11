class AdminController < ApplicationController
  require 'fileutils'
  before_filter :login_from_cookie
  before_filter :check_login

  def index
    @page_title = "Admin Functions"
    # nothing to do
  end

  def list
    redirect_to :action => :index
  end

  def done
    session[:file_list] = nil
    redirect_to :controller => :reservation, :action => :list
  end

  def restart_passenger
    restart(false)
    @page_title = "Admin Functions"
    render :action => :index
  end

  def maintenance
    @page_title = "Maintenance Functions"
    # nothing to do
  end

  def manage_backups
    @page_title = "Manage Backup Files"
    Dir::chdir RAILS_ROOT
    handle_files "backup", "bak"
    Dir::chdir RAILS_ROOT
    session[:next_action] = :manage_backups
  end

  def manage_logs
    @page_title = "Manage Log Files"
    Dir::chdir RAILS_ROOT
    handle_files "log", "log*"
    Dir::chdir RAILS_ROOT
    session[:next_action] = :manage_logs
  end

  def do_delete
    # get the file name
    file_list = session[:file_list]
    id = params[:id].to_i
    debug params[:id]
    debug file_list.inspect
    if @os == "Windows_NT"
      fqfn = session[:dir].gsub("/","\x5c") + file_list[id]
    else
      fqfn = session[:dir] + file_list[id]
    end
    # delete the indicated file
    result = File::delete(fqfn)
    if result
      flash[:notice] = "#{fqfn} deleted"
      debug "#{fqfn} deleted"
    else
      flash[:error] = "#{fqfn} deletion failed"
      error "#{fqfn} deletion failed"
    end
    session[:file_list] = nil
    # go back for more
    redirect_to :action => session[:next_action]
  end

  def do_backup
    @page_title = "Backup Complete"
    # generate the filename
    @filename = RAILS_ROOT + "/backup/"+currentTime.strftime("%Y%m%d%H%M")+".bak"
    debug "doing backup to #{@filename}"
    # get the config variables
    db_config = ActiveRecord::Base.configurations[RAILS_ENV]
    username = db_config['username'] 
    password =  db_config['password'] ? "-p"+db_config['password'].to_s : ""
    database = db_config['database']
    case db_config['adapter']
    when 'mysql'
      if @os == "Windows_NT"
        result = system "..\\..\\mysql\\bin\\mysqldump -u #{username} #{password} -r #{@filename} #{database}"
      else
        result = system "mysqldump -u #{username} #{password} -r #{@filename} #{database}"
      end
      if result
	flash[:notice] = "Backup successful, copy #{@filename} to backup media for storage"
      else
	flash[:error] = "Error in Backup, Backup failed"
	error "Backup failed with status #{$?}"
      end
    when 'sqlite3'
      if @os == "Windows_NT"
        # result = system "..\\..\\mysql\\bin\\mysqldump -u #{username} #{password} -r #{@filename} #{database}"
	flash[:error] = "Unable to backup databases of type: #{db_config['adapter']} on Windows"
      else
        result = system "sqlite3 #{database} .dump > #{@filename}"
      end
      if result
	flash[:notice] = "Backup successful, copy #{@filename} to backup media for storage"
      else
	flash[:error] = "Error in Backup, Backup failed"
	error "Backup failed with status #{$?}"
      end
    else
      flash[:error] = "Unable to backup databases of type: #{db_config['adapter']}"
    end
    session[:file_list] = nil
    render :action => 'index'
  end
 
  def do_restore
    @page_title = "Restore Complete"
    # get the config variables
    db_config = ActiveRecord::Base.configurations[RAILS_ENV]
    username = db_config['username'] 
    password =  db_config['password'] ? "-p"+db_config['password'].to_s : ""
    database = db_config['database']
    # get the file name
    file_list = session[:file_list]
    id = params[:id].to_i
    debug params[:id]
    session[:file_list] = nil
    case db_config['adapter']
    when 'mysql'
      if @os == "Windows_NT"
        debug 'windows nt'
	backupfile = "backup\\" + file_list[id]
        Rake::Task['db:drop'].execute
        Rake::Task['db:create'].execute
        result = system "..\\..\\mysql\\bin\\mysql -u #{username} #{password} -q -e \"source #{backupfile}\" #{database}"
	if result
          Rake::Task['db:migrate'].execute
	  flash[:notice] = 'Restore successful '
	  restart(false)
	else
	  flash[:error] = "Error in Restore, Restore failed"
	  error "Restore failed with status #{$?}"
	end
      else
	debug @os
	backupfile = "backup/" + file_list[id]
        Rake::Task['db:drop'].execute
        Rake::Task['db:create'].execute
        result = system "mysql -u #{username} #{password} -q -e \"source #{backupfile}\" #{database}"
	if result
          Rake::Task['db:migrate'].execute
	  flash[:notice] = 'Restore successful '
	  restart(false)
	else
	  flash[:error] = "Error in Restore, Restore failed"
	  error "Restore failed with status #{$?}"
	end
      end
    when 'sqlite3'
      # untested
      if @os == "Windows_NT"
	flash[:error] = "Unable to restore databases of type: #{db_config['adapter']} on Windows"
      else
        Rake::Task['db:drop'].invoke
        Rake::Task['db:create'].invoke
	backupfile = "backup/" + file_list[id]
        result = system "sqlite3 #{database} < #{backupfile}"
	if result
          Rake::Task['db:migrate'].invoke
	  restart(false)
        else
	  flash[:error] = "Error in Restore, Restore failed"
	  error "Restore failed with status #{$?}"
        end
      end
    else
      flash[:error] = "Unable to restore databases of type: #{db_config['adapter']}"
    end
    # because the user tables may not match current facts, 
    # do a defacto logout
    session[:user_id] = nil
    render :action => 'index'
  end

  def uploadFile
    unless params[:upload]
      flash[:error] = 'File must be selected for upload'
      redirect_to :action => :manage_backups and return
    end
    name =  params[:upload].original_filename
    name = sanitize_filename name
    directory = "backup"
    # create the file path
    path = File.join(directory, name)
    if File::exist? path
      flash[:error] = "File already exists.  Delete the current file if you want to replace it"
    else
      # write the file
      if File.open(path, "wb") { |f| f.write(params[:upload].read) }
        flash[:notice] = "File upload succeeded"
      else
        flash[:error] = "File upload failed"
      end
    end
    redirect_to :action => :manage_backups
  rescue => err
    flash[:error] = "File upload failed.  Did you select a file to upload?"
    error err.to_s
    redirect_to :action => :manage_backups
  end

  def do_download
    file_list = session[:file_list]
    id = params[:id].to_i
    # session[:file_list] = nil
    if params[:dir] == 'backup'
      type = "application/bak"
      session[:next_action] = :manage_backups
    else
      type = "text/plain"
      session[:next_action] = :manage_logs
    end
    send_file params[:dir]+"/#{file_list[id]}", :filename => file_list[id], :type => type
  end

  def user_manual
    if File.exist?  RAILS_ROOT + "/doc/UserManual.pdf"
      send_file RAILS_ROOT + "/doc/UserManual.pdf", :disposition => 'inline'
    elsif File.exist?  RAILS_ROOT + "/doc/User Manual.pdf"
      send_file RAILS_ROOT + "/doc/User Manual.pdf", :disposition => 'inline'
    else
      flash[:error] = "Cannot find User Manual"
      redirect_to :action => :index
    end
  end

  def troubleshoot
    res_array = []
    grp_array = []
    reservations = Reservation.find_all_by_archived false
    reservations.each do  |res|
      if res.space_id == 0
	debug 'space id 0'
        res_array << res.id
      elsif res.camper_id == 0 
	debug 'camper id 0'
        res_array << res.id
      elsif !res.confirm?
	debug 'not confirmed'
        res_array << res.id
      else
        begin
	  Camper.find res.camper_id
	  Space.find res.space_id
	rescue 
	  res_array << res.id
	end	 
      end
    end
    @res_size = res_array.size
    debug "#{@res_size} reservations with problems"

    groups = Group.all
    groups.each do |grp|
      if grp.camper_id == 0
	debug 'wagonmaster id 0'
        grp_array << grp.id
      elsif grp.expected_number < 1 
	debug 'expected number ' + grp.expected_number.to_s
        grp_array << grp.id
      else
        begin
	  Camper.find grp.camper_id
	rescue 
	  grp_array << grp.id
	end	 
      end
    end

    err = ''
    if (res_array.size == 0) && (grp_array.size == 0)
      flash[:notice] = "No problem reservations or groups found"
      redirect_to :controller => :admin, :action => :maintenance and return
    end
    if res_array.size > 0
      err += "#{res_array.size} problem reservations found "
      @reservations = Reservation.find res_array
    end
    if grp_array.size > 0
      err += "#{grp_array.size} problem groups found"
      @groups = Group.find grp_array
    end
    flash[:error] = err if err.size > 0
  end

  def destroy_res
    res = Reservation.find params[:reservation_id]
    res.destroy
    flash[:notice] = "reservation #{params[:reservation_id]} destroyed"
    info "reservation #{params[:reservation_id]} destroyed by #{@option.use_login ? @user_login.name : ' '}"
  rescue
    flash[:error] = 'failed to destroy reservation ' + params[:reservation_id]
    error 'failed to destroy res ' + params[:reservation_id]
  ensure
    redirect_to :controller => :admin, :action => :troubleshoot
  end

  def destroy_grp
    grp = Group.find params[:group_id]
    grp.destroy
    flash[:notice] = "#{grp.name} group destroyed"
    info "group #{params[:group_id]} destroyed by #{@option.use_login ? @user_login.name : ' '}"
  rescue
    flash[:error] = 'failed to destroy group ' + params[:group_id]
    error 'failed to destroy group ' + params[:group_id]
  ensure
    redirect_to :controller => :admin, :action => :troubleshoot
  end

private
  def handle_files(dir, suffix)
    debug "generating new filename list for #{suffix} in #{dir}"
    @file_stats = Array.new
    # get a list of backup files
    Dir::chdir(dir)
    filenames = Dir["*.#{suffix}"]
    @file_list = filenames.sort_by {|filename| File.mtime(filename) }
    @file_list.each { |f| @file_stats << File.stat(f) }
    # debug "before: #{filenames}, after: #{@file_list}"
    Dir::chdir("..")
    session[:dir] = "#{dir}/"
    session[:file_list] = @file_list
  end

end
