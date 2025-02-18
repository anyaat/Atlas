module Expirable

  extend ActiveSupport::Concern

  if ENV['TEST_EMAILS']
    TRANSITION_STATE_AFTER = {
      should_verify: 0.minutes,
      should_need_review: 10.minutes,
      should_need_urgent_review: 19.minutes,
      should_expire: 28.minutes,
      should_archive: 37.minutes,
    }.freeze
  else
    TRANSITION_STATE_AFTER = {
      should_verify: 0.weeks,
      should_need_review: 8.weeks,
      should_need_urgent_review: 9.weeks,
      should_expire: 10.weeks,
      should_archive: 12.weeks,
    }.freeze
  end

  included do
    enum status: {
      verified: 0,
      needs_review: 1,
      needs_urgent_review: 2,
      expired: 3,
      archived: 4,
      finished: 5,
    }, _scopes: false

    aasm column: :status, enum: true, skip_validation_on_save: true, whiny_transitions: false do
      state :verified, initial: true
      state :needs_review
      state :needs_urgent_review
      state :expired
      state :archived
      state :finished

      after_all_events :update_timestamps

      event :update_status, after_enter: :log_event do
        transitions to: :finished, if: :should_finish?
        transitions from: :verified, to: :needs_review, if: :should_need_review?
        transitions from: :needs_review, to: :needs_urgent_review, if: :should_need_urgent_review?
        transitions from: :needs_urgent_review, to: :expired, if: :should_expire?
        transitions from: :expired, to: :archived, if: :should_archive?
        
        after { try(:log_status_change) }
      end

      event :reset_status do
        transitions to: :finished, if: :should_finish?
        transitions to: :archived, if: :should_archive?
        transitions to: :expired, if: :should_expire?
        transitions to: :needs_urgent_review, if: :should_need_urgent_review?
        transitions to: :needs_review, if: :should_need_review?
        transitions to: :verified
      end

      event :verify do
        transitions to: :verified
      end
    end

    TRANSITION_STATE_AFTER.keys.each do |key|
      define_method :"#{key}_at" do
        result = (updated_at || 1.minute.ago) + TRANSITION_STATE_AFTER[key]
        ENV['TEST_EMAILS'] ? result : result.beginning_of_hour
      end

      define_method :"#{key}?" do
        send(:"#{key}_at") <= Time.now
      end
    end

    before_save :verify

    scope :publishable, -> { where(status: %i[verified needs_review needs_urgent_review]) }
    scope :unpublishable, -> { where(status: %i[expired archived finished]) }
  end

  def update_timestamps
    if new_record?
      self.should_update_status_at = should_need_review_at
    elsif archived? || finished?
      update_column :should_update_status_at, nil
    else
      next_state_index = self.class.statuses[status] + 1
      next_state = TRANSITION_STATE_AFTER.keys[next_state_index]
      update_column :should_update_status_at, send(:"#{next_state}_at")
    end

    if new_record?
      self.verified_at = Time.now
    elsif respond_to?("#{status}_at")
      update_column "#{status}_at", Time.now
    end
  end

  def should_finish?
    end_date < DateTime.now
  end

end
