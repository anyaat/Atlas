
## SENDINBLUE
# This concern simplifies requests to sendinblue.com

module SendinblueAPI

  LISTS = {
    registrations: 13,
    country_managers: 20,
    client_managers: 19,
    test: 5,
  }.freeze

  TEMPLATES = {
    confirmation: 9,
    reminder: 12,
  }.freeze

  def self.subscribe email, list_id, attributes
    client = SibApiV3Sdk::ContactsApi.new
    list_id = SendinblueAPI::LISTS[list_id]

    # Create a contact
    p client.create_contact(
      'email' => email,
      'attributes' => attributes.deep_transform_keys { |key| key.to_s.upcase },
      'listIds' => [list_id.to_i],
      'updateEnabled' => true
    )
  rescue SibApiV3Sdk::ApiError => e
    puts "Exception when calling ContactsApi->create_contact: #{e} #{e.response_body}"
  end

  def self.update_contact email, attributes
    client = SibApiV3Sdk::ContactsApi.new
    attributes.deep_transform_keys! { |key| key.to_s.upcase }

    # Update a contact
    p client.update_contact(email, 'attributes' => attributes)
  rescue SibApiV3Sdk::ApiError => e
    puts "Exception when calling ContactsApi->update_contact: #{e} #{e.response_body}"
  end

  def self.send_email template, config
    config.reverse_merge!({
      templateId: SendinblueAPI::TEMPLATES[template],
      # sender: { name: 'We Meditate', email: 'admin@wemeditate.com' },
      params: {},
      tags: [],
    })

    config[:tags] << 'atlas'
    config[:tags] << template.to_s

    config[:params][:text].reverse_merge!(I18n.translate('emails.common'))
    pp config

    client = SibApiV3Sdk::TransactionalEmailsApi.new
    p client.send_transac_email(config)
  rescue SibApiV3Sdk::ApiError => e
    puts "Exception when calling TransactionalEmailsApi->send_transac_email: #{e} #{e.response_body}"
  end

  def self.send_confirmation_email registration
    registration = registration.extend(RegistrationDecorator)
    event = registration.event.extend(EventDecorator)
    scope = "emails.confirmation.#{event.layer}"

    text = {
      header: I18n.translate('header', scope: scope, name: registration.first_name)
    }

    %i[subheader invite_a_friend get_directions faqs].each do |field|
      text[field] = I18n.translate(field, scope: scope)
    end

    SendinblueAPI.send_email(:confirmation, {
      subject: I18n.translate('subject', scope: scope, event_name: event.label),
      to: [{ name: registration.name, email: registration.email }],
      params: {
        name: registration.first_name,
        url: event.map_url,
        label: event.label,
        address: event.address,
        timing: [event.start_time, event.end_time].compact.join(' - '),
        date: registration.starting_date.to_s(:short),
        weekday: registration.starting_at_weekday.upcase,
        directions_url: event.decorated_venue&.directions_url,
        text: text,
      },
    })
  end

  def self.schedule_reminder_email registration
    registration = registration.extend(RegistrationDecorator)
    event = registration.event.extend(EventDecorator)
    scope = "emails.reminder.#{event.layer}"

    text = {
      header: I18n.translate('header', scope: scope, name: registration.first_name)
    }

    %i[subheader action].each do |field|
      text[field] = I18n.translate(field, scope: scope)
    end

    schedule_at = registration.starting_at - (event.online? ? 1.hour : 1.day)
    schedule_at = 1.minute.from_now if event.online? && schedule_at < Time.now
    schedule_at = 1.minute.from_now # For development
    return if schedule_at < Time.now

    SendinblueAPI.send_email(:reminder, {
      scheduledAt: schedule_at.utc.iso8601,
      subject: I18n.translate('subject', scope: scope, event_name: event.label),
      to: [{ name: registration.name, email: registration.email }],
      params: {
        name: registration.first_name,
        label: event.label,
        address: event.address,
        timing: [event.start_time, event.end_time].compact.join(' - '),
        date: registration.starting_date.to_s(:short),
        weekday: registration.starting_at_weekday.upcase,
        link: event.online? ? event.online_url : event.decorated_venue&.directions_url,
        text: text,
      },
    })
  end

end