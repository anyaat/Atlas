class Venue < ApplicationRecord

  include Manageable
  acts_as_mappable lat_column_name: :latitude, lng_column_name: :longitude
  
  nilify_blanks
  has_many :events

  validates :street, presence: true
  validates :country_code, presence: true
  validates :latitude, :longitude, presence: true

  def managed_by? manager, super_manager: false
    return true if self.manager == manager && !super_manager

    manager.countries.each do |country|
      return true if country.contains?(venue)
    end

    manager.provinces.each do |province|
      return true if province.contains?(venue)
    end

    manager.local_areas.each do |local_area|
      return true if local_area.contains?(venue)
    end

    return false
  end

  def label
    name || street
  end

  # Check if coordinates have been defined
  def coordinates?
    latitude.present? && longitude.present?
  end
  
  def full_address
    [street, city, province, country].compact.join(', ')
  end

  def address
    {
      street: street,
      city: city,
      province: province,
      country: country,
      postcode: postcode,
    }
  end

  def country
    I18nData.countries(I18n.locale)[country_code]
  end

  def country_code= value
    value = value.to_s.upcase
    # Only accept country codes which are in the language list
    super value if I18nData.countries.keys.include?(value)
  end

end
