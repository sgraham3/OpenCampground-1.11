class Blackout < ActiveRecord::Base
  validate :valid_dates?
  validates_presence_of     :name
  validates_uniqueness_of   :name
  named_scope :active, :conditions => ["active = ?", true]
  default_scope :order => :startdate
  
  def self.available(sd, ed)
    avail = sd
    self.all.each do |b|
      dt = b.blacked_out?(sd, ed)
      avail = dt if dt && dt > avail
    end
    avail
  end

  def blacked_out?(sd, ed)
    return false unless active
    return false if ed < startdate || sd > enddate
    return enddate + 1 if sd < startdate && ed > enddate
    return enddate + 1 if sd > startdate && sd < enddate
    return enddate + 1 if ed > startdate && ed < enddate
  end

private
  def valid_dates?
    if enddate < startdate
      errors.add :startdate, "is after enddate"
    end
  end
end
