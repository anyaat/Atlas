class Manager < ApplicationRecord

  # Extensions
  passwordless_with :email
  searchable_columns %w[name email]
  audited

  # Associations
  has_many :managed_records
  has_many :countries, through: :managed_records, source: :record, source_type: 'Country', dependent: :destroy
  has_many :provinces, through: :managed_records, source: :record, source_type: 'Province', dependent: :destroy
  has_many :local_areas, through: :managed_records, source: :record, source_type: 'LocalArea', dependent: :destroy
  #has_many :local_area_venues, through: :local_areas, source: :venues
  has_many :events
  has_many :actions, class_name: 'Audit', foreign_type: :user_type, foreign_key: :user_id

  # Validations
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Scopes
  default_scope { order(updated_at: :desc) }
  scope :administrators, -> { where(administrator: true) }
  scope :country_managers, -> { where('managed_countries_counter > 0') }
  scope :local_managers, -> { where('managed_localities_counter > 0') }
  scope :event_managers, -> { joins(:events) }

  # Methods

  def parent
    case type
    when :country
      parent = countries.first
    when :local
      parent = local_areas.international.first || provinces.first || local_areas.cross_province.first || local_areas.first
    when :event
      parent = events.first
    end
    
    parent unless parent&.new_record?
  end

  def managed_by? manager, super_manager: false
    return true if self == manager && !super_manager

    manager.administrator?
  end

  def type
    if administrator?
      :worldwide
    elsif managed_countries_counter.positive?
      :country
    elsif managed_localities_counter.positive?
      :local
    elsif events.exists?
      :event
    else
      :none
    end
  end

  # For audit logs
  def username
    name
  end

  def set_counter record, direction
    Manager.set_counter
  end

  def self.set_counter klass, direction, id
    if klass == 'Country'
      column = :managed_countries_counter
    elsif klass == 'Event'
      column = :managed_events_counter
    elsif %w[Province LocalArea].include?(klass)
      column = :managed_localities_counter
    end

    Manager.send("#{direction}_counter", column, id) if column
  end
  
  def accessible_countries area: false
    if administrator? || area
      Country.default_scoped
    else
      countries_via_province = Country.where(country_code: provinces.select(:country_code))
      countries_via_local_area = Country.where(country_code: local_areas.select(:country_code))
      countries_via_event = Country.where(country_code: events.select(:country_code))
      Country.where(id: countries).or(countries_via_province).or(countries_via_local_area).or(countries_via_event)
    end
  end
  
  def accessible_provinces country_code = nil, area: false
    if administrator? || area
      country_code ? Province.where(country_code: country_code) : Province.default_scoped
    else
      provinces_via_country = Province.where(country_code: countries.select(:country_code))
      provinces_via_local_area = Province.where(province_code: local_areas.select(:province_code)) # TODO: Provinces are probably not unique internationally
      provinces_via_event = Province.where(province_code: events.select(:province_code))
      provinces = Province.where(id: provinces).or(provinces_via_country).or(provinces_via_local_area).or(provinces_via_event)
      provinces = Province.where(id: provinces, country_code: country_code) if country_code
      provinces
    end
  end
  
  def accessible_local_areas
    if administrator?
      LocalArea.default_scoped
    else
      local_areas_via_country = LocalArea.where(country_code: countries.select(:country_code))
      local_areas_via_province = LocalArea.where(province_code: provinces.select(:province_code))
      LocalArea.where(id: local_areas).or(local_areas_via_country).or(local_areas_via_province)
    end
  end
  
  def accessible_venues
    if administrator?
      Venue.default_scoped
    else
      venues_via_countries = Venue.where(country_code: countries.select(:country_code))
      venues_via_provinces = Venue.where(province_code: provinces.select(:province_code))
      #venues_via_local_areas = Venue.where(province_code: local_area_venues.select(:province_code))
      venues_via_events = Venue.where(id: events.select(:venue_id))
      Venue.where(venues_via_countries).or(venues_via_provinces).or(venues_via_events)#.or(local_area_venues)
    end
  end

  def accessible_events
    if administrator?
      Event.default_scoped
    else
      events_via_countries = Event.joins(:venue).where(venues: { country_code: countries.select(:country_code) })
      events_via_provinces = Event.joins(:venue).where(venues: { province_code: provinces.select(:province_code) })
      #events_via_local_areas = Venue.where(province_code: local_area_venues.select(:province_code))
      Event.joins(:venue).where(id: events).or(events_via_countries).or(events_via_provinces)#.or(events_via_local_areas)
    end
  end

  def accessible_registrations
    if administrator?
      Registration.default_scoped
    else
      Registration.where(event_id: accessible_events)
    end
  end

  def accessible_managers
    if administrator?
      Manager.all
    else
      Manager.none
    end
  end

end
