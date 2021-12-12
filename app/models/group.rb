class Group < ActiveRecord::Base
  has_many :reservations
  belongs_to :camper
  validates_uniqueness_of :name
  validates_presence_of :name
  validates_presence_of :startdate
  validates_presence_of :enddate
  before_destroy :check_use
  before_save :check_camper
  
  default_scope :order => "name asc"

  def self.count_by_group(id)
    Reservation.find_all_by_group_id(id).size
  end
  
  private

  def check_use
    res = Reservation.find_all_by_group_id id
    if res.size > 0
      lst = ''
      res.each {|r| lst << " #{r.id},"}
      errors.add "group in use by reservation(s) #{lst}"
      return false
    end
  end

  def check_camper
    self.camper_id ||= Camper.first.id
  end

end
