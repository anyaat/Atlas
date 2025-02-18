class Event < ApplicationRecord

  # Extensions
  include Publishable
  include AASM # State machine - required for Expirable
  include Expirable
  include ActivityMonitorable
  include Managed

  nilify_blanks
  searchable_columns %w[custom_name description]
  audited except: %i[
    summary_email_sent_at status_email_sent_at latest_registration_at
    should_update_status_at verified_at expired_at archived_at finished_at
    status
  ]

  enum category: { intro: 1, intermediate: 2, course: 3, public_event: 4, concert: 5 }
  enum recurrence: { day: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6, sunday: 7 }
  enum registration_mode: { native: 0, external: 1, meetup: 2, eventbrite: 3, facebook: 4 }, _suffix: true

  # Associations
  belongs_to :venue
  has_many :local_areas, through: :venue
  acts_as_mappable through: :venue

  has_many :pictures, as: :parent, dependent: :destroy
  accepts_nested_attributes_for :pictures

  has_many :registrations, dependent: :delete_all

  # Validations
  validates :custom_name, length: { maximum: 255 }
  validates :category, :language_code, presence: true
  validates :recurrence, :start_date, :start_time, presence: true
  validates :description, length: { minimum: 40, maximum: 600, allow_blank: true }
  validates :registration_url, url: true, unless: :native_registration_mode?
  validates :phone_number, phone: { possible: true, allow_blank: true, country_specifier: -> event { event.venue.country_code } }
  validates :manager, presence: true
  validates :online_url, presence: true, if: :online?
  validates_associated :pictures
  validate :validate_end_time
  validate :validate_end_date
  validate :parse_phone_number

  # Scopes
  scope :with_new_registrations, -> { where('latest_registration_at >= summary_email_sent_at') }
  scope :notifications_enabled, -> { where.not(disable_notifications: true) }
  scope :current, -> { where('end_date IS NULL OR end_date >= ?', DateTime.now) }
  scope :publicly_visible, -> { current.manager_verified.publishable.published }
  scope :manager_verified, -> { joins(:manager).where(managers: { email_verified: true }) }

  scope :ready_for_reminder_email, -> { where("reminder_email_sent_at IS NULL OR reminder_email_sent_at <= ?", 12.hours.ago) }

  scope :online, -> { where(online: true) }
  scope :offline, -> { where.not(online: true) }

  # Delegations
  delegate :full_address, to: :venue
  alias parent venue
  alias associated_registrations registrations

  # Methods
  after_save :verify_manager

  def region_association?
    false
  end

  def language_code= value
    # Only accept languages which are in the language list
    super value if I18nData.languages.key?(value)
  end

  def should_finish?
    next_occurrence_at.nil?
  end

  def duration
    return nil if end_time.nil?

    start_time = self.start_time.split(':').map(&:to_f)
    end_time = self.end_time.split(':').map(&:to_f)
    (end_time[0] - start_time[0]) + ((end_time[1] - start_time[1]) / 60.0)
  end

  def next_occurrences_after first_datetime, limit: 10
    first_date = first_datetime.to_date
    return [] if end_date && end_date < first_date

    occurrences = []
    
    date = start_date > first_date ? start_date : first_date
    time = start_time.split(':').map(&:to_i)
    datetime = date.to_time(:utc).in_time_zone(venue.time_zone).change(hour: time[0], min: time[1])

    if recurrence == 'day'
      if datetime > first_datetime
        occurrences.push(datetime)
      else
        occurrences.push(datetime + 1.day)
      end
    else
      next_datetime = (datetime + 1.week).beginning_of_week(recurrence.to_sym)
      next_datetime = next_datetime.change(hour: time[0], min: time[1])
      occurrences.push(next_datetime)
    end

    while occurrences.length < limit
      next_datetime = occurrences.last + (recurrence == 'day' ? 1.day : 1.week)
      break if end_date && next_datetime.to_date > end_date

      occurrences.push(next_datetime)
    end

    occurrences
  end

  def next_occurrence_at
    @next_occurrence_at ||= next_occurrences_after(Time.now, limit: 1).first
  end

  def label
    custom_name || venue.street
  end

  def log_status_change
    return if archived? || new_record?
    
    if needs_urgent_review?
      venue.parent.managers.each do |parent_manager|
        EventMailer.with(event: self, manager: parent_manager).status.deliver_later
      end
    end

    EventMailer.with(event: self, manager: self.manager).status.deliver_later
  end

  def cache_key
    "#{super}-#{status}-#{last_activity_on.strftime("%d%m%Y")}"
  end

  def manager_verified?
    manager.email_verified?
  end

  private

    def validate_end_time
      return if end_time.nil? || duration.positive?
      
      self.errors.add(:end_time, I18n.translate('cms.messages.event.invalid_end_time'))
    end

    def validate_end_date
      self.end_date = start_date if recurrence == 'day' && !end_date.present?
      return if end_date.nil?
      
      self.errors.add(:end_date, I18n.translate('cms.messages.event.invalid_end_date')) if end_date < start_date
      self.errors.add(:end_date, I18n.translate('cms.messages.event.passed_end_date')) if end_date < Date.today
    end

    def parse_phone_number
      self.phone_number = Phonelib.parse(phone_number, venue.country_code).international
    end

    def verify_manager
      return if manager.email_verified?

      ManagerMailer.with(manager: manager, context: self).verify.deliver_later
      manager.touch(:email_verification_sent_at)
    end

end
