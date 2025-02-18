module Types
  class QueryType < Types::BaseObject
    description 'The query root of this schema'

    field :geojson, GeojsonType, null: false do
      description 'Returns all events in the geojson format'
      argument :country, String, required: false
    end

    field :venues, [VenueType], 'Returns all events', null: false
    field :events, [EventType], null: false do
      description 'Returns all events'
      argument :online, Boolean, required: false
      argument :country, String, required: false
      argument :recurrence, String, required: false
      argument :language_code, String, required: false
    end

    field :country, CountryType, null: true do
      description 'Find a country by code'
      argument :code, String, required: true
    end

    field :venue, VenueType, null: true do
      description 'Find a venue by ID'
      argument :id, ID, required: true
    end

    field :event, EventType, null: true do
      description 'Find an event by ID'
      argument :id, ID, required: true
    end

    field :closest_venue, VenueType, null: true do
      description 'Find the closest event to some coordinates'
      argument :latitude, Float, required: true
      argument :longitude, Float, required: true
    end


    def geojson(country: nil)
      scope = Venue
      scope = scope.where(country_code: country) if country
      venues = decorate scope.publicly_visible.has_offline_events

      {
        type: 'FeatureCollection',
        features: venues.map do |venue|
          events = venue.events.publicly_visible
          next if events.empty?

          {
            type: "Feature #{events.length}",
            id: venue.id,
            geometry: {
              type: 'Point',
              coordinates: [venue.longitude, venue.latitude]
            },
            properties: venue,
          }
        end.compact,
        created_at: DateTime.now.to_s,
      }
    end
  
    def event(id:)
      decorate Event.find(id)
    end
  
    def venue(id:)
      decorate Venue.find(id)
    end
  
    def country(code:)
      decorate Country.find_by_country_code(code)
    end

    def events(online: nil, country: nil, recurrence: nil, language_code: nil)
      scope = Event.publicly_visible
      scope = scope.where(online: online) unless online.nil?
      scope = scope.joins(:venue).where(venues: { country_code: country }) unless country.nil?
      scope = scope.where(recurrence: recurrence) if Event.recurrences.key?(recurrence)
      scope = scope.where(language_code: language_code) unless language_code.nil?
      
      decorate scope
    end

    def venues
      decorate Venue.publicly_visible
    end

    def closest_venue(latitude:, longitude:)
      venues = Venue.publicly_visible.by_distance(origin: [latitude, longitude]).joins(:events).where(events: { online: false }).limit(5)

      venues.each do |venue|
        return decorate(venue) if venue.events.present?
      end
    end

    def decorate object
      return nil if object.nil?

      if object.is_a? ActiveRecord::Relation
        object.map { |r| r.extend("#{object.model}Decorator".constantize) }
      else
        object.extend("#{object.class}Decorator".constantize)
      end
    end
  end
end
